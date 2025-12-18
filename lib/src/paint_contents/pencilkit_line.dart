import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

import '../paint_extension/ex_paint.dart';
import 'paint_content.dart';

class InkPoint {
  InkPoint(this.x, this.y, this.p);
  final double x;
  final double y;
  final double p; // 0..1
}

class PencilKitLine extends PaintContent {
  PencilKitLine({
    this.thinning = 0.65,
    this.smoothing = 0.60,
    this.streamline = 0.55,

    /// ✅ 你要求：速度同粗幼無關
    /// 所以冇真 pressure 時預設唔用 simulatePressure（避免用速度推估）
    this.simulatePressureWhenNoRealPressure = false,

    /// 點距離太密會耗 CPU，太疏會鋸齒
    this.minPointDistance = 0.8,
  });

  PencilKitLine.data({
    required Paint paint,
    required this.points,
    required this.thinning,
    required this.smoothing,
    required this.streamline,
    required this.simulatePressureWhenNoRealPressure,
    required this.minPointDistance,
  }) : super.paint(paint);

  factory PencilKitLine.fromJson(Map<String, dynamic> data) {
    return PencilKitLine.data(
      paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
      points: (data['points'] as List).map((e) {
        final m = e as Map<String, dynamic>;
        return InkPoint(
          (m['x'] as num).toDouble(),
          (m['y'] as num).toDouble(),
          (m['p'] as num).toDouble(),
        );
      }).toList(),
      thinning: (data['thinning'] as num).toDouble(),
      smoothing: (data['smoothing'] as num).toDouble(),
      streamline: (data['streamline'] as num).toDouble(),
      simulatePressureWhenNoRealPressure: data['simulatePressureWhenNoRealPressure'] as bool,
      minPointDistance: (data['minPointDistance'] as num).toDouble(),
    );
  }

  final double thinning;
  final double smoothing;
  final double streamline;
  final bool simulatePressureWhenNoRealPressure;
  final double minPointDistance;

  late List<InkPoint> points;

  bool _hasRealPressure = false;
  bool _dirty = true;
  Path? _cachedPath;

  /// ✅ 給 ObjectEraser 用（粗略 hit test）
  List<Offset> get polylinePoints => points.map((v) => Offset(v.x, v.y)).toList(growable: false);

  @override
  String get contentType => 'PencilKitLine';

  @override
  void startDraw(Offset startPoint) {
    points = <InkPoint>[InkPoint(startPoint.dx, startPoint.dy, 0.5)];
    _dirty = true;
    _cachedPath = null;
  }

  @override
  void drawing(Offset nowPoint) {
    // fallback：如果冇走 event pipeline，就用固定壓力
    points.add(InkPoint(nowPoint.dx, nowPoint.dy, 0.5));
    _dirty = true;
  }

  @override
  void onPointerDown(PointerDownEvent e) {
    _hasRealPressure = PaintContent.hasRealPressure(e);
    final p = e.localPosition;
    points = <InkPoint>[InkPoint(p.dx, p.dy, _pressure01(e))];
    _dirty = true;
    _cachedPath = null;
  }

  @override
  void onPointerMove(PointerMoveEvent e) {
    // ✅ 兼容 coalesced（你 PaintContent 已加 helper）
    final events = PaintContent.coalescedOf(e);
    if (events.isNotEmpty) {
      for (final pe in events) {
        _addPoint(pe);
      }
    } else {
      _addPoint(e);
    }
  }

  void _addPoint(PointerEvent e) {
    final p = e.localPosition;

    if (points.isNotEmpty) {
      final last = Offset(points.last.x, points.last.y);
      if ((p - last).distance < minPointDistance) return;
    }

    points.add(InkPoint(p.dx, p.dy, _pressure01(e)));
    _dirty = true;
  }

  double _pressure01(PointerEvent e) {
    // ✅ 有真 pressure：用 pressure 變粗幼（似 PencilKit）
    if (PaintContent.hasRealPressure(e)) {
      final v = PaintContent.normalizedPressure(e);
      // 輕壓更敏感、重壓更穩：曲線更似 PencilKit
      return math.pow(v, 0.7).toDouble().clamp(0.0, 1.0);
    }

    // ✅ 冇 pressure：固定，唔用速度推斷
    return 0.5;
  }

  List<dynamic> _toFreehandPoints() {
    // 以「[x,y,pressure]」vector 形式餵比 perfect_freehand
    return points.map((p) => <double>[p.x, p.y, p.p]).toList(growable: false);
  }

  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    if (points.length < 2) return;

    if (_dirty || _cachedPath == null) {
      final outline = getStroke(
        _toFreehandPoints().cast(),
        options: StrokeOptions(
          size: paint.strokeWidth,
          thinning: thinning,
          smoothing: smoothing,
          streamline: streamline,
          simulatePressure: (!_hasRealPressure && simulatePressureWhenNoRealPressure),
        ),
      );

      _cachedPath = _polygonToPath(outline);
      _dirty = false;
    }

    // ✅ PencilKit-like：fill polygon
    final fillPaint = paint.copyWith(style: PaintingStyle.fill);
    canvas.drawPath(_cachedPath!, fillPaint);
  }

  Path _polygonToPath(List<Offset> poly) {
    final path = Path();
    if (poly.isEmpty) return path;
    path.moveTo(poly.first.dx, poly.first.dy);
    for (int i = 1; i < poly.length; i++) {
      path.lineTo(poly[i].dx, poly[i].dy);
    }
    path.close();
    return path;
  }

  @override
  PencilKitLine copy() => PencilKitLine(
        thinning: thinning,
        smoothing: smoothing,
        streamline: streamline,
        simulatePressureWhenNoRealPressure: simulatePressureWhenNoRealPressure,
        minPointDistance: minPointDistance,
      );

  @override
  Map<String, dynamic> toContentJson() {
    return <String, dynamic>{
      'thinning': thinning,
      'smoothing': smoothing,
      'streamline': streamline,
      'simulatePressureWhenNoRealPressure': simulatePressureWhenNoRealPressure,
      'minPointDistance': minPointDistance,
      'points': points.map((v) => {'x': v.x, 'y': v.y, 'p': v.p}).toList(),
      'paint': paint.toJson(),
    };
  }
}
