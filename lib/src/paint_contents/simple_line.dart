import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

import '../draw_path/draw_path.dart';
import '../paint_extension/ex_offset.dart';
import '../paint_extension/ex_paint.dart';
import 'paint_content.dart';

/// 自由线条绘制内容
///
/// 支持两种绘制模式：
/// 1. 传统路径模式：直接连接绘制点
/// 2. 贝塞尔曲线模式：使用二次贝塞尔曲线平滑连接，提供更流畅的线条效果
class SimpleLine extends PaintContent {
  SimpleLine({
    this.minPointDistance = 2.0,
    this.useBezierCurve = true,
  });

  SimpleLine.data({
    this.minPointDistance = 2.0,
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

    if (hasPoints) {
      return SimpleLine.data(
        minPointDistance: (data['minPointDistance'] ?? 0.0) as double,
        useBezierCurve: (data['useBezierCurve'] ?? true) as bool,
        points: (data['points'] as List<dynamic>)
            .map((dynamic e) => jsonToOffset(e as Map<String, dynamic>))
            .toList(),
        paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
      );
    } else {
      return SimpleLine.data(
        minPointDistance: (data['minPointDistance'] ?? 0.0) as double,
        useBezierCurve: (data['useBezierCurve'] ?? false) as bool,
        path: DrawPath.fromJson(data['path'] as Map<String, dynamic>),
        paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
      );
    }
  }

  /// 最小点距离
  final double minPointDistance;

  /// 是否使用贝塞尔曲线
  final bool useBezierCurve;

  /// 传统路径模式用
  DrawPath path = DrawPath();

  /// 贝塞尔模式用：真实采样点（会序列化）
  List<Offset>? points;

  /// 上一个真实点的位置，用于点过滤
  Offset? _lastPoint;

  /// 已确认的渲染 path（不会每帧从头重建）
  Path _renderPath = Path();

  /// 实时尾巴（当前真实末端 + predicted 末端）
  Path _tailPath = Path();

  /// 已确认 path 当前结束位置（通常是上一个 midpoint）
  Offset? _lastMidPoint;

  /// predicted 点（只用于预览，不写入 history / json）
  List<Offset> _predictedPoints = <Offset>[];

  // object eraser usage
  List<Offset> get hitTestPoints {
    if (useBezierCurve) {
      return points ?? const <Offset>[];
    }
    return path.points;
  }

  @override
  String get contentType => 'SimpleLine';

  @override
  void startDraw(Offset startPoint) {
    _lastPoint = startPoint;
    _predictedPoints = <Offset>[];
    _lastMidPoint = null;
    _renderPath = Path();
    _tailPath = Path();

    if (useBezierCurve) {
      points = <Offset>[startPoint];
      _renderPath.moveTo(startPoint.dx, startPoint.dy);
    } else {
      path = DrawPath();
      path.moveTo(startPoint.dx, startPoint.dy);
    }
  }

  @override
  void drawing(Offset nowPoint) {
    if (_lastPoint != null) {
      final double distance = (nowPoint - _lastPoint!).distance;
      if (distance < minPointDistance) {
        return;
      }
    }

    if (useBezierCurve) {
      _appendRealPoint(nowPoint);
    } else {
      path.lineTo(nowPoint.dx, nowPoint.dy);
    }

    _lastPoint = nowPoint;
  }

  @override
  void onPointerMove(PointerMoveEvent e) {
    if (!useBezierCurve) {
      super.onPointerMove(e);
      return;
    }

    final List<PointerEvent> events = PaintContent.coalescedOf(e);
    if (events.isNotEmpty) {
      for (final PointerEvent pe in events) {
        drawing(pe.localPosition);
      }
    } else {
      drawing(e.localPosition);
    }

    _updatePredictedPoints(
      PaintContent.predictedOf(e).map((PointerEvent pe) => pe.localPosition).toList(),
    );
  }

  @override
  void endDraw() {
    if (!useBezierCurve) {
      return;
    }

    _predictedPoints = <Offset>[];

    final List<Offset>? pts = points;
    if (pts == null || pts.isEmpty) {
      _tailPath = Path();
      return;
    }

    if (pts.length == 1) {
      _tailPath = Path();
      return;
    }

    final Offset last = pts.last;
    _renderPath.quadraticBezierTo(last.dx, last.dy, last.dx, last.dy);
    _tailPath = Path();
    _lastMidPoint = last;
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
      canvas.drawCircle(points!.first, paint.strokeWidth / 8, paint);
      return;
    }

    canvas.drawPath(_renderPath, paint);
    canvas.drawPath(_tailPath, paint);
  }

  void _appendRealPoint(Offset p) {
    points ??= <Offset>[];

    if (points!.isEmpty) {
      points!.add(p);
      _renderPath.moveTo(p.dx, p.dy);
      _lastMidPoint = null;
      _predictedPoints = <Offset>[];
      _rebuildTailPath();
      return;
    }

    if (points!.length == 1) {
      final Offset first = points!.first;
      points!.add(p);

      final Offset mid = _midPoint(first, p);
      _renderPath.lineTo(mid.dx, mid.dy);
      _lastMidPoint = mid;
      _predictedPoints = <Offset>[];
      _rebuildTailPath();
      return;
    }

    final Offset prev = points!.last;
    points!.add(p);

    final Offset mid = _midPoint(prev, p);
    _renderPath.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    _lastMidPoint = mid;
    _predictedPoints = <Offset>[];
    _rebuildTailPath();
  }

  void _updatePredictedPoints(List<Offset> rawPredicted) {
    if (!useBezierCurve) {
      return;
    }

    final List<Offset>? pts = points;
    if (pts == null || pts.isEmpty) {
      _predictedPoints = <Offset>[];
      _tailPath = Path();
      return;
    }

    final List<Offset> filtered = <Offset>[];
    Offset anchor = pts.last;

    for (final Offset p in rawPredicted) {
      if ((p - anchor).distance < minPointDistance) {
        continue;
      }
      if (filtered.isNotEmpty && (p - filtered.last).distance < minPointDistance) {
        continue;
      }
      filtered.add(p);
      anchor = p;
    }

    _predictedPoints = filtered;
    _rebuildTailPath();
  }

  void _rebuildTailPath() {
    _tailPath = Path();

    final List<Offset>? pts = points;
    if (!useBezierCurve || pts == null || pts.isEmpty) {
      return;
    }

    if (pts.length == 1) {
      return;
    }

    final Offset start = _lastMidPoint ?? pts.first;
    final List<Offset> tailPts = <Offset>[
      pts.last,
      ..._predictedPoints,
    ];

    if (tailPts.isEmpty) {
      return;
    }

    _tailPath.moveTo(start.dx, start.dy);

    if (tailPts.length == 1) {
      final Offset p = tailPts.first;
      _tailPath.quadraticBezierTo(p.dx, p.dy, p.dx, p.dy);
      return;
    }

    for (int i = 0; i < tailPts.length - 1; i++) {
      final Offset control = tailPts[i];
      final Offset end = _midPoint(control, tailPts[i + 1]);
      _tailPath.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }

    final Offset last = tailPts.last;
    _tailPath.quadraticBezierTo(last.dx, last.dy, last.dx, last.dy);
  }

  void _rebuildFinalBezierPathFromPoints() {
    _renderPath = Path();
    _tailPath = Path();
    _predictedPoints = <Offset>[];

    final List<Offset>? pts = points;
    if (pts == null || pts.isEmpty) {
      _lastMidPoint = null;
      _lastPoint = null;
      return;
    }

    _renderPath.moveTo(pts.first.dx, pts.first.dy);

    if (pts.length == 1) {
      _lastMidPoint = null;
      _lastPoint = pts.first;
      return;
    }

    if (pts.length == 2) {
      final Offset mid = _midPoint(pts[0], pts[1]);
      _renderPath.lineTo(mid.dx, mid.dy);
      _renderPath.quadraticBezierTo(pts[1].dx, pts[1].dy, pts[1].dx, pts[1].dy);
      _lastMidPoint = pts[1];
      _lastPoint = pts.last;
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
    _lastMidPoint = last;
    _lastPoint = last;
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
        useBezierCurve: useBezierCurve,
      );

  @override
  Map<String, dynamic> toContentJson() {
    if (useBezierCurve && points != null) {
      return <String, dynamic>{
        'minPointDistance': minPointDistance,
        'useBezierCurve': useBezierCurve,
        'points': points!.map((Offset e) => e.toJson()).toList(),
        'paint': paint.toJson(),
      };
    } else {
      return <String, dynamic>{
        'minPointDistance': minPointDistance,
        'useBezierCurve': useBezierCurve,
        'path': path.toJson(),
        'paint': paint.toJson(),
      };
    }
  }
}
