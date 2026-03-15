import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

import '../draw_path/draw_path.dart';
import '../paint_extension/ex_offset.dart';
import '../paint_extension/ex_paint.dart';
import 'paint_content.dart';

/// 自由线条绘制内容
///
/// 这版只保留真正有效的逻辑：
///
/// 1. 主干使用二次贝塞尔平滑
/// 2. 当前最新末端使用 live cursor 补尾
/// 3. 使用 coalesced events 提高点密度
/// 4. 不同输入装置使用不同最小采样距离
///
/// 已移除：
///
/// - predicted points
/// - synthetic prediction
/// - 实验性 tip / tail 逻辑
class SimpleLine extends PaintContent {
  SimpleLine({
    this.minPointDistance = 2.0,
    this.stylusMinPointDistance = 0.75,
    this.touchMinPointDistance = 2.0,
    this.mouseMinPointDistance = 1.2,
    this.useBezierCurve = true,
  });

  SimpleLine.data({
    this.minPointDistance = 2.0,
    this.stylusMinPointDistance = 0.75,
    this.touchMinPointDistance = 2.0,
    this.mouseMinPointDistance = 1.2,
    this.useBezierCurve = false,
    this.points,
    DrawPath? path,
    required Paint paint,
  })  : path = path ?? DrawPath(),
        super.paint(paint) {
    if (useBezierCurve) {
      points ??= <Offset>[];
      _rebuildFinalBezierPathFromPoints();
    }
  }

  factory SimpleLine.fromJson(Map<String, dynamic> data) {
    final bool hasPoints = data.containsKey('points');

    final double minPointDistance = ((data['minPointDistance'] ?? 2.0) as num).toDouble();
    final double stylusMinPointDistance =
        ((data['stylusMinPointDistance'] ?? 0.75) as num).toDouble();
    final double touchMinPointDistance = ((data['touchMinPointDistance'] ?? 2.0) as num).toDouble();
    final double mouseMinPointDistance = ((data['mouseMinPointDistance'] ?? 1.2) as num).toDouble();
    final bool useBezierCurve = (data['useBezierCurve'] ?? true) as bool;

    if (hasPoints) {
      return SimpleLine.data(
        minPointDistance: minPointDistance,
        stylusMinPointDistance: stylusMinPointDistance,
        touchMinPointDistance: touchMinPointDistance,
        mouseMinPointDistance: mouseMinPointDistance,
        useBezierCurve: useBezierCurve,
        points: (data['points'] as List<dynamic>)
            .map((dynamic e) => jsonToOffset(e as Map<String, dynamic>))
            .toList(),
        paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
      );
    } else {
      return SimpleLine.data(
        minPointDistance: minPointDistance,
        stylusMinPointDistance: stylusMinPointDistance,
        touchMinPointDistance: touchMinPointDistance,
        mouseMinPointDistance: mouseMinPointDistance,
        useBezierCurve: useBezierCurve,
        path: DrawPath.fromJson(data['path'] as Map<String, dynamic>),
        paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
      );
    }
  }

  /// 旧版统一门槛（保留兼容）
  final double minPointDistance;

  /// Apple Pencil / stylus 门槛
  final double stylusMinPointDistance;

  /// 手指门槛
  final double touchMinPointDistance;

  /// mouse / 其他门槛
  final double mouseMinPointDistance;

  /// 是否使用贝塞尔曲线
  final bool useBezierCurve;

  /// 传统路径模式
  DrawPath path = DrawPath();

  /// 贝塞尔模式真实采样点（会序列化 / history / hit-test）
  List<Offset>? points;

  /// 当前输入装置类型
  PointerDeviceKind? _activeKind;

  /// 最新已确认的真实点
  Offset? _lastCommittedPoint;

  /// 最新实时点（即使未达提交门槛）
  Offset? _liveCursor;

  /// 已确认主路径
  Path _renderPath = Path();

  /// 当前最新尾巴
  Path _liveTipPath = Path();

  /// 已确认主路径当前结束位置（通常为上一个 midpoint）
  Offset? _lastMidPoint;

  List<Offset> get hitTestPoints {
    if (useBezierCurve) {
      return points ?? const <Offset>[];
    }
    return path.points;
  }

  @override
  String get contentType => 'SimpleLine';

  @override
  void onPointerDown(PointerDownEvent e) {
    _activeKind = e.kind;
    super.onPointerDown(e);
  }

  @override
  void startDraw(Offset startPoint) {
    _lastCommittedPoint = startPoint;
    _liveCursor = startPoint;
    _lastMidPoint = null;
    _renderPath = Path();
    _liveTipPath = Path();

    if (useBezierCurve) {
      points = <Offset>[startPoint];
      _renderPath.moveTo(startPoint.dx, startPoint.dy);
      _rebuildLiveTipPath();
    } else {
      path = DrawPath();
      path.moveTo(startPoint.dx, startPoint.dy);
    }
  }

  @override
  void drawing(Offset nowPoint) {
    if (!useBezierCurve) {
      if (_lastCommittedPoint != null &&
          (nowPoint - _lastCommittedPoint!).distance < minPointDistance) {
        return;
      }
      path.lineTo(nowPoint.dx, nowPoint.dy);
      _lastCommittedPoint = nowPoint;
      _liveCursor = nowPoint;
      return;
    }

    _handleRealtimePoint(nowPoint);
  }

  @override
  void onPointerMove(PointerMoveEvent e) {
    if (!useBezierCurve) {
      super.onPointerMove(e);
      return;
    }

    _activeKind = e.kind;

    final List<PointerEvent> events = PaintContent.coalescedOf(e);
    if (events.isNotEmpty) {
      for (final PointerEvent pe in events) {
        _handleRealtimePoint(pe.localPosition);
      }
    } else {
      _handleRealtimePoint(e.localPosition);
    }
  }

  @override
  void onPointerUp(PointerUpEvent e) {
    if (useBezierCurve) {
      _activeKind = e.kind;
      _liveCursor = e.localPosition;
      _commitFinalLiveCursorIfNeeded();
      _rebuildLiveTipPath();
    }
    super.onPointerUp(e);
  }

  @override
  void endDraw() {
    if (!useBezierCurve) {
      return;
    }

    final List<Offset>? pts = points;
    if (pts == null || pts.length < 2) {
      _liveTipPath = Path();
      return;
    }

    final Offset last = pts.last;
    if (_lastMidPoint == null || (_lastMidPoint! - last).distance > 0.001) {
      _renderPath.quadraticBezierTo(last.dx, last.dy, last.dx, last.dy);
      _lastMidPoint = last;
    }

    _liveCursor = last;
    _liveTipPath = Path();
  }

  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    if (useBezierCurve && points != null && points!.isNotEmpty) {
      _drawIncrementalBezier(canvas);
    } else {
      canvas.drawPath(path.path, paint);
    }
  }

  void _drawIncrementalBezier(Canvas canvas) {
    if (points == null || points!.isEmpty) {
      return;
    }

    if (points!.length == 1) {
      final Offset p = points!.first;
      canvas.drawCircle(p, paint.strokeWidth / 8, paint);
      canvas.drawPath(_liveTipPath, paint);
      return;
    }

    canvas.drawPath(_renderPath, paint);
    canvas.drawPath(_liveTipPath, paint);
  }

  void _handleRealtimePoint(Offset point) {
    _liveCursor = point;

    if (_shouldCommitPoint(point)) {
      _appendRealPoint(point);
    }

    _rebuildLiveTipPath();
  }

  bool _shouldCommitPoint(Offset point) {
    final List<Offset>? pts = points;
    if (!useBezierCurve || pts == null || pts.isEmpty) {
      return true;
    }

    return (point - pts.last).distance >= _effectiveMinPointDistance();
  }

  double _effectiveMinPointDistance() {
    final PointerDeviceKind? kind = _activeKind;

    if (kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus) {
      return stylusMinPointDistance;
    }
    if (kind == PointerDeviceKind.touch) {
      return touchMinPointDistance;
    }
    return mouseMinPointDistance <= 0 ? minPointDistance : mouseMinPointDistance;
  }

  void _appendRealPoint(Offset p) {
    points ??= <Offset>[];

    if (points!.isEmpty) {
      points!.add(p);
      _renderPath.moveTo(p.dx, p.dy);
      _lastCommittedPoint = p;
      _lastMidPoint = null;
      return;
    }

    if ((p - points!.last).distance <= 0.001) {
      _lastCommittedPoint = p;
      return;
    }

    if (points!.length == 1) {
      final Offset first = points!.first;
      points!.add(p);

      final Offset mid = _midPoint(first, p);
      _renderPath.lineTo(mid.dx, mid.dy);
      _lastMidPoint = mid;
      _lastCommittedPoint = p;
      return;
    }

    final Offset prev = points!.last;
    points!.add(p);

    final Offset mid = _midPoint(prev, p);
    _renderPath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    _lastMidPoint = mid;
    _lastCommittedPoint = p;
  }

  void _commitFinalLiveCursorIfNeeded() {
    final List<Offset>? pts = points;
    final Offset? live = _liveCursor;
    if (!useBezierCurve || pts == null || pts.isEmpty || live == null) {
      return;
    }

    if ((live - pts.last).distance <= 0.001) {
      return;
    }

    _appendRealPoint(live);
  }

  void _rebuildLiveTipPath() {
    _liveTipPath = Path();

    final List<Offset>? pts = points;
    final Offset? live = _liveCursor;

    if (!useBezierCurve || pts == null || pts.isEmpty || live == null) {
      return;
    }

    if (pts.length == 1) {
      final Offset start = pts.first;
      if ((live - start).distance <= 0.001) {
        return;
      }

      _liveTipPath.moveTo(start.dx, start.dy);
      _liveTipPath.lineTo(live.dx, live.dy);
      return;
    }

    final Offset start = _lastMidPoint ?? pts.first;
    final Offset committed = pts.last;

    _liveTipPath.moveTo(start.dx, start.dy);
    _liveTipPath.quadraticBezierTo(
      committed.dx,
      committed.dy,
      live.dx,
      live.dy,
    );
  }

  void _rebuildFinalBezierPathFromPoints() {
    _renderPath = Path();
    _liveTipPath = Path();

    final List<Offset>? pts = points;
    if (pts == null || pts.isEmpty) {
      _lastCommittedPoint = null;
      _lastMidPoint = null;
      _liveCursor = null;
      return;
    }

    _renderPath.moveTo(pts.first.dx, pts.first.dy);

    if (pts.length == 1) {
      _lastCommittedPoint = pts.first;
      _lastMidPoint = null;
      _liveCursor = pts.first;
      return;
    }

    if (pts.length == 2) {
      final Offset mid = _midPoint(pts[0], pts[1]);
      _renderPath.lineTo(mid.dx, mid.dy);
      _renderPath.quadraticBezierTo(pts[1].dx, pts[1].dy, pts[1].dx, pts[1].dy);
      _lastCommittedPoint = pts.last;
      _lastMidPoint = pts.last;
      _liveCursor = pts.last;
      return;
    }

    final Offset firstMid = _midPoint(pts[0], pts[1]);
    _renderPath.lineTo(firstMid.dx, firstMid.dy);

    for (int i = 1; i < pts.length - 1; i++) {
      final Offset control = pts[i];
      final Offset end = _midPoint(control, pts[i + 1]);
      _renderPath.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }

    final Offset last = pts.last;
    _renderPath.quadraticBezierTo(last.dx, last.dy, last.dx, last.dy);

    _lastCommittedPoint = last;
    _lastMidPoint = last;
    _liveCursor = last;
  }

  Offset _midPoint(Offset a, Offset b) {
    return Offset(
      (a.dx + b.dx) / 2,
      (a.dy + b.dy) / 2,
    );
  }

  @override
  SimpleLine copy() => SimpleLine(
        minPointDistance: minPointDistance,
        stylusMinPointDistance: stylusMinPointDistance,
        touchMinPointDistance: touchMinPointDistance,
        mouseMinPointDistance: mouseMinPointDistance,
        useBezierCurve: useBezierCurve,
      );

  @override
  Map<String, dynamic> toContentJson() {
    if (useBezierCurve && points != null) {
      return <String, dynamic>{
        'minPointDistance': minPointDistance,
        'stylusMinPointDistance': stylusMinPointDistance,
        'touchMinPointDistance': touchMinPointDistance,
        'mouseMinPointDistance': mouseMinPointDistance,
        'useBezierCurve': useBezierCurve,
        'points': points!.map((Offset e) => e.toJson()).toList(),
        'paint': paint.toJson(),
      };
    } else {
      return <String, dynamic>{
        'minPointDistance': minPointDistance,
        'stylusMinPointDistance': stylusMinPointDistance,
        'touchMinPointDistance': touchMinPointDistance,
        'mouseMinPointDistance': mouseMinPointDistance,
        'useBezierCurve': useBezierCurve,
        'path': path.toJson(),
        'paint': paint.toJson(),
      };
    }
  }
}
