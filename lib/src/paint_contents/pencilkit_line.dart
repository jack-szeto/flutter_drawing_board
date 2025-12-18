import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:perfect_freehand/src/types/easings.dart';

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
    // =========================
    // 粗幼（pressure → 線寬變化）
    // Range: 0.0 ~ 1.2
    // 越大：壓力變化越明顯；越細：越接近固定粗幼
    // ✅ 建議（手寫）：0.85
    this.thinning = 0.85,

    // =========================
    // 輪廓平滑（邊緣消鋸齒 / 抖動）
    // Range: 0.0 ~ 1.0
    // 越大：更圓滑但更「膠」；越細：更貼手但更易見手震
    // ✅ 建議（手寫）：0.90
    this.smoothing = 0.90,

    // =========================
    // 路徑收斂（穩定 vs 跟手）⭐️「跟筆」關鍵
    // Range: 0.0 ~ 1.0
    // 越大：更穩但更拖（筆尖會領先筆跡）；越細：更貼手
    // ✅ 建議（跟筆優先）：0.48
    this.streamline = 0.48,

    /// =========================
    /// easing（壓力曲線）
    /// ✅ 建議：easeInOut（筆壓變化更自然）
    this.easing = StrokeEasings.easeInOut,

    /// =========================
    /// 冇真 pressure 時，是否用速度「估算」pressure
    /// true：手指/滑鼠都會有粗幼（由速度推估）
    /// false：冇 pressure 就固定粗幼
    /// ✅ 你要求「速度同粗幼無關」：保持 false
    this.simulatePressureWhenNoRealPressure = false,

    /// =========================
    /// 點距離門檻（過濾太密/噪點）
    /// Range: 0.25 ~ 1.2
    /// 太大：快寫會漏點 → 斷開/折線；太細：點數爆炸 → 掉幀 → 唔跟筆
    /// ✅ 建議：0.35 ~ 0.55（先用 0.40）
    this.minPointDistance = 0.40,

    /// =========================
    /// 最大段長（插值上限段長）⭐️「快寫折線」核心
    /// Range: 1.2 ~ 3.0（視乎 strokeWidth）
    /// 越細：越圓但更食 CPU；越大：更省但快寫會折線
    /// ✅ 4px 筆建議：1.6
    this.maxPointDistance = 1.6,

    /// =========================
    /// 動態插值：最低段長（速度越快越接近呢個值）
    /// Range: 0.6 ~ 1.4
    /// ✅ 建議：0.85（唔好太細，否則點數爆→掉幀→唔跟筆）
    this.dynamicMaxPointDistanceMin = 0.85,

    /// =========================
    /// 速度→加密強度（越大越容易因快寫加密）
    /// Range: 0.5 ~ 2.5
    /// ✅ 建議（跟筆優先）：1.0
    this.speedDensify = 1.0,

    /// =========================
    /// 速度尺度（px/ms）：越大代表「要更快先觸發加密」
    /// Range: 4.0 ~ 10.0
    /// ✅ 建議：6.0（避免一般書寫就加密爆點）
    this.speedScale = 6.0,

    /// =========================
    /// 轉彎保留（減弧線折線）
    /// Range: 0.0 ~ 1.0（越大越容易保留轉彎點）
    /// ✅ 建議：0.85
    this.cornerPreserve = 0.85,

    /// =========================
    /// 是否用 Catmull-Rom 做點位平滑
    /// true：更圓但「天生有 1 點 latency」→ 唔跟筆更明顯
    /// ✅ 跟筆優先：false
    this.useCatmull = false,

    /// Catmull alpha（0.0=uniform, 0.5=centripetal）
    /// ✅ 如果你開 useCatmull，建議 0.5
    this.catmullAlpha = 0.5,

    /// =========================
    /// predicted events（表層預覽用）⭐️提升跟筆/圓滑
    /// Range: 0 ~ 8（建議 4~7）
    /// ✅ 建議：6
    this.predictedEventCount = 6,

    /// predicted gate（相對 minPointDistance）
    /// 越細：predicted 更易入（更順）但更食
    /// ✅ 建議：0.40
    this.predictedGateFactor = 0.40,

    /// predicted 最大段長倍率（相對 maxPointDistance）
    /// 越細：predicted 插值更密（更圓）但更食
    /// ✅ 建議：0.65
    this.predictedMaxPointDistanceFactor = 0.65,

    /// =========================
    /// 線頭 taper
    /// ✅ 建議：弱一點（短少少）
    this.startTaperEnabled = true,
    this.startCustomTaper = 6.0,

    /// =========================
    /// 線尾 taper（你覺得太強就再減）
    /// ✅ 建議：8.0
    this.endTaperEnabled = true,
    this.endCustomTaper = 8.0,

    /// =========================
    /// 線頭/線尾 cap（圓頭）
    /// ✅ PencilKit feel：true
    this.capStart = true,
    this.capEnd = true,

    /// =========================
    /// 單點 dot 大小比例（相對 strokeWidth）
    /// Range: 0.25 ~ 0.80
    /// ✅ 建議：0.42（比你之前更細，避免「點太大」）
    this.dotScale = 0.42,
  });

  PencilKitLine.data({
    required Paint paint,
    required this.points,
    required this.thinning,
    required this.smoothing,
    required this.streamline,
    required this.easing,
    required this.simulatePressureWhenNoRealPressure,
    required this.minPointDistance,
    required this.maxPointDistance,
    required this.dynamicMaxPointDistanceMin,
    required this.speedDensify,
    required this.speedScale,
    required this.cornerPreserve,
    required this.useCatmull,
    required this.catmullAlpha,
    required this.predictedEventCount,
    required this.predictedGateFactor,
    required this.predictedMaxPointDistanceFactor,
    required this.startTaperEnabled,
    required this.startCustomTaper,
    required this.endTaperEnabled,
    required this.endCustomTaper,
    required this.capStart,
    required this.capEnd,
    required this.dotScale,
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
      thinning: (data['thinning'] as num?)?.toDouble() ?? 0.85,
      smoothing: (data['smoothing'] as num?)?.toDouble() ?? 0.90,
      streamline: (data['streamline'] as num?)?.toDouble() ?? 0.48,

      easing: StrokeEasings.easeInOut, // easing functions 唔 serialize（保持合理預設）

      simulatePressureWhenNoRealPressure:
          (data['simulatePressureWhenNoRealPressure'] as bool?) ?? false,

      minPointDistance: (data['minPointDistance'] as num?)?.toDouble() ?? 0.40,
      maxPointDistance: (data['maxPointDistance'] as num?)?.toDouble() ?? 1.6,
      dynamicMaxPointDistanceMin: (data['dynamicMaxPointDistanceMin'] as num?)?.toDouble() ?? 0.85,
      speedDensify: (data['speedDensify'] as num?)?.toDouble() ?? 1.0,
      speedScale: (data['speedScale'] as num?)?.toDouble() ?? 6.0,

      cornerPreserve: (data['cornerPreserve'] as num?)?.toDouble() ?? 0.85,
      useCatmull: (data['useCatmull'] as bool?) ?? false,
      catmullAlpha: (data['catmullAlpha'] as num?)?.toDouble() ?? 0.5,

      predictedEventCount: (data['predictedEventCount'] as num?)?.toInt() ?? 6,
      predictedGateFactor: (data['predictedGateFactor'] as num?)?.toDouble() ?? 0.40,
      predictedMaxPointDistanceFactor:
          (data['predictedMaxPointDistanceFactor'] as num?)?.toDouble() ?? 0.65,

      startTaperEnabled: (data['startTaperEnabled'] as bool?) ?? true,
      startCustomTaper: (data['startCustomTaper'] as num?)?.toDouble() ?? 6.0,

      endTaperEnabled: (data['endTaperEnabled'] as bool?) ?? true,
      endCustomTaper: (data['endCustomTaper'] as num?)?.toDouble() ?? 8.0,

      capStart: (data['capStart'] as bool?) ?? true,
      capEnd: (data['capEnd'] as bool?) ?? true,

      dotScale: (data['dotScale'] as num?)?.toDouble() ?? 0.42,
    );
  }

  final double thinning;
  final double smoothing;
  final double streamline;
  final double Function(double) easing;
  final bool simulatePressureWhenNoRealPressure;

  final double minPointDistance;

  final double maxPointDistance;
  final double dynamicMaxPointDistanceMin;
  final double speedDensify;
  final double speedScale;

  final double cornerPreserve;

  final bool useCatmull;
  final double catmullAlpha;

  final int predictedEventCount;
  final double predictedGateFactor;
  final double predictedMaxPointDistanceFactor;

  final bool startTaperEnabled;
  final double? startCustomTaper;

  final bool endTaperEnabled;
  final double? endCustomTaper;

  final bool capStart;
  final bool capEnd;

  final double dotScale;

  late List<InkPoint> points;

  // ✅ predicted points：只用於表層預覽（deeper=false），唔 commit
  final List<InkPoint> _predictedPoints = <InkPoint>[];

  bool _hasRealPressure = false;
  bool _dirty = true;
  Path? _cachedPath;

  /// ✅ 給 ObjectEraser 用（粗略 hit test）
  List<Offset> get polylinePoints => points.map((v) => Offset(v.x, v.y)).toList(growable: false);

  @override
  String get contentType => 'PencilKitLine';

  // 用於角度估算（減折線）
  Offset? _lastDir;
  Offset? _lastPos;
  Duration? _lastTime; // ✅ 用時間估速度（快寫折線 vs 跟筆）

  @override
  void startDraw(Offset startPoint) {
    points = <InkPoint>[InkPoint(startPoint.dx, startPoint.dy, 0.5)];
    _predictedPoints.clear();
    _lastPos = startPoint;
    _lastDir = null;
    _lastTime = null;
    _dirty = true;
    _cachedPath = null;
  }

  @override
  void drawing(Offset nowPoint) {
    // fallback：如果冇走 event pipeline，就用固定壓力
    points.add(InkPoint(nowPoint.dx, nowPoint.dy, 0.5));
    _predictedPoints.clear();
    _lastPos = nowPoint;
    _dirty = true;
  }

  @override
  void onPointerDown(PointerDownEvent e) {
    _hasRealPressure = PaintContent.hasRealPressure(e);
    final p = e.localPosition;
    points = <InkPoint>[InkPoint(p.dx, p.dy, _pressure01(e))];
    _predictedPoints.clear();
    _lastPos = p;
    _lastDir = null;
    _lastTime = e.timeStamp;
    _dirty = true;
    _cachedPath = null;
  }

  @override
  void onPointerMove(PointerMoveEvent e) {
    // ✅ coalesced：補回高採樣點，減折線
    final events = PaintContent.coalescedOf(e);
    if (events.isNotEmpty) {
      for (final pe in events) {
        _addPoint(pe);
      }
    } else {
      _addPoint(e);
    }

    // ✅ predicted：只做表層預覽（唔 commit）
    _predictedPoints.clear();
    final preds = PaintContent.predictedOf(e);
    if (preds.isNotEmpty && predictedEventCount > 0) {
      final takeN = math.min(predictedEventCount, preds.length);
      for (int i = 0; i < takeN; i++) {
        _addPredicted(preds[i]);
      }
    }
  }

  // =========================
  // ✅ 核心：加點 + 動態插值（解決快寫折線 + 提升跟筆）
  // =========================

  void _addPoint(PointerEvent e) {
    final p = e.localPosition;

    // 1) gate：過濾噪點（但太嚴會斷開）
    if (_lastPos != null) {
      final dist = (p - _lastPos!).distance;
      if (dist < minPointDistance) return;
    }

    // 2) 轉彎保留（減「弧線→折線」）
    if (_lastPos != null) {
      final v = p - _lastPos!;
      final vd = v.distance;
      if (vd > 0) {
        final dir = Offset(v.dx / vd, v.dy / vd);
        if (_lastDir != null) {
          final dot = (dir.dx * _lastDir!.dx) + (dir.dy * _lastDir!.dy);
          final turning = (1.0 - dot).clamp(0.0, 1.0);
          final keepBecauseCorner = turning > (1.0 - cornerPreserve);
          if (keepBecauseCorner) {
            // keep
          }
        }
        _lastDir = dir;
      }
    }

    // 3) 估速度（px/ms）→ 動態決定 max segment length
    final double speed = _speedOf(e, p);
    final double dynMaxD = _dynamicMaxD(speed);

    // 4) 插值：確保快寫大段距離會補點（避免折線/斷開成點）
    _insertWithInterpolation(
      to: p,
      pTo: _pressure01(e),
      store: points,
      maxD: dynMaxD,
    );

    _lastPos = p;
    _lastTime = e.timeStamp;
    _dirty = true;
  }

  void _addPredicted(PointerEvent e) {
    // predicted 係「表層預覽」：用較鬆 gate，令更順更跟筆
    if (points.isEmpty) return;

    final p = e.localPosition;
    final last = Offset(points.last.x, points.last.y);

    final gate = minPointDistance * predictedGateFactor;
    if ((p - last).distance < gate) return;

    final double speed = _speedOf(e, p, from: last);
    final double maxD = _dynamicMaxD(speed) * predictedMaxPointDistanceFactor;

    _insertWithInterpolation(
      from: last,
      pFrom: points.last.p,
      to: p,
      pTo: _pressure01(e),
      store: _predictedPoints,
      maxD: math.max(0.6, maxD),
    );

    _dirty = true;
  }

  double _speedOf(PointerEvent e, Offset p, {Offset? from}) {
    final Offset? a = from ?? _lastPos;
    final Duration? t0 = _lastTime;
    final Duration t1 = e.timeStamp;

    if (a == null || t0 == null) return 0.0;
    final double dist = (p - a).distance;
    final int dtUs = (t1 - t0).inMicroseconds;
    if (dtUs <= 0) return 0.0;

    // px/ms
    return dist / (dtUs / 1000.0);
  }

  double _dynamicMaxD(double speed) {
    // speed / speedScale → 0..1（越快越接近 1）
    final double t = (speed / math.max(0.001, speedScale)).clamp(0.0, 1.0);

    // speedDensify 控制「快寫加密強度」
    final double k = (t * speedDensify).clamp(0.0, 1.0);

    final double maxD = math.max(0.6, maxPointDistance);
    final double minD = math.min(maxD, math.max(0.6, dynamicMaxPointDistanceMin));

    // k=0 → maxD，k=1 → minD
    return maxD - (maxD - minD) * k;
  }

  void _insertWithInterpolation({
    Offset? from,
    double? pFrom,
    required Offset to,
    required double pTo,
    required List<InkPoint> store,
    required double maxD,
  }) {
    final Offset a;
    final double pa;

    if (from != null && pFrom != null) {
      a = from;
      pa = pFrom;
    } else if (points.isNotEmpty) {
      a = Offset(points.last.x, points.last.y);
      pa = points.last.p;
    } else {
      store.add(InkPoint(to.dx, to.dy, pTo));
      return;
    }

    final double dist = (to - a).distance;
    final double m = math.max(0.6, maxD);

    if (dist > m) {
      final int n = (dist / m).ceil();
      for (int i = 1; i < n; i++) {
        final double tt = i / n;
        final Offset ip = Offset.lerp(a, to, tt)!;
        final double pp = (pa + (pTo - pa) * tt).clamp(0.0, 1.0);
        store.add(InkPoint(ip.dx, ip.dy, pp));
      }
    }

    store.add(InkPoint(to.dx, to.dy, pTo));
  }

  double _pressure01(PointerEvent e) {
    if (PaintContent.hasRealPressure(e)) {
      final v = PaintContent.normalizedPressure(e);
      return math.pow(v, 0.7).toDouble().clamp(0.0, 1.0);
    }
    return 0.5;
  }

  // ✅✅ 重要：perfect_freehand 需要 List<PointVector>
  List<PointVector> _toFreehandPoints({required bool deeper}) {
    final List<InkPoint> src = deeper
        ? points
        : <InkPoint>[
            ...points,
            ..._predictedPoints,
          ];

    // ✅ 可選：Catmull（更圓但更慢半拍）
    final List<InkPoint> out = useCatmull ? _catmullResample(src) : src;

    return out.map((p) => PointVector(p.x, p.y, p.p)).toList(growable: false);
  }

  List<InkPoint> _catmullResample(List<InkPoint> src) {
    if (src.length < 4) return src;

    final List<InkPoint> out = <InkPoint>[src.first];
    for (int i = 0; i < src.length - 3; i++) {
      final a = src[i];
      final b = src[i + 1];
      final c = src[i + 2];
      final d = src[i + 3];

      // 每段插 2 點（唔好太多，避免爆點）
      for (int k = 1; k <= 2; k++) {
        final t = k / 3.0;
        final p = _catmullPoint(a, b, c, d, t, alpha: catmullAlpha);
        out.add(p);
      }
      out.add(src[i + 2]);
    }
    out.add(src.last);
    return out;
  }

  InkPoint _catmullPoint(InkPoint p0, InkPoint p1, InkPoint p2, InkPoint p3, double t,
      {required double alpha}) {
    // centripetal Catmull-Rom（alpha=0.5）較少自交
    double tj(double ti, InkPoint a, InkPoint b) {
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dd = math.sqrt(dx * dx + dy * dy);
      return math.pow(dd, alpha).toDouble() + ti;
    }

    final t0 = 0.0;
    final t1 = tj(t0, p0, p1);
    final t2 = tj(t1, p1, p2);
    final t3 = tj(t2, p2, p3);

    final tt = t1 + (t2 - t1) * t;

    InkPoint lerp(InkPoint a, InkPoint b, double t) => InkPoint(
          a.x + (b.x - a.x) * t,
          a.y + (b.y - a.y) * t,
          (a.p + (b.p - a.p) * t).clamp(0.0, 1.0),
        );

    final A1 = lerp(p0, p1, ((tt - t0) / (t1 - t0)).clamp(0.0, 1.0));
    final A2 = lerp(p1, p2, ((tt - t1) / (t2 - t1)).clamp(0.0, 1.0));
    final A3 = lerp(p2, p3, ((tt - t2) / (t3 - t2)).clamp(0.0, 1.0));

    final B1 = lerp(A1, A2, ((tt - t0) / (t2 - t0)).clamp(0.0, 1.0));
    final B2 = lerp(A2, A3, ((tt - t1) / (t3 - t1)).clamp(0.0, 1.0));

    final C = lerp(B1, B2, ((tt - t1) / (t2 - t1)).clamp(0.0, 1.0));
    return C;
  }

  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    // ✅ 單點：畫細粒圓點（避免點太大、避免短筆劃 commit 後消失）
    if (points.length == 1) {
      final p = points.first;
      final center = Offset(p.x, p.y);

      final double base = (paint.strokeWidth * 0.5) * dotScale;
      final double pr = (0.65 + 0.35 * p.p).clamp(0.6, 1.0);
      final double r = base * pr;

      final dotPaint = paint.copyWith(style: PaintingStyle.fill);
      canvas.drawCircle(center, r, dotPaint);
      return;
    }

    if (points.length < 2) return;

    if (_dirty || _cachedPath == null) {
      final outline = getStroke(
        _toFreehandPoints(deeper: deeper),
        options: StrokeOptions(
          size: paint.strokeWidth,
          thinning: thinning,
          smoothing: smoothing,
          streamline: streamline,
          easing: easing,
          simulatePressure: (!_hasRealPressure && simulatePressureWhenNoRealPressure),

          // ✅ 用你版本的 start/end（可調線尾收窄）
          start: StrokeEndOptions.start(
            cap: capStart,
            taperEnabled: startTaperEnabled,
            customTaper: startCustomTaper,
            easing: StrokeEasings.easeInOut,
          ),
          end: StrokeEndOptions.end(
            cap: capEnd,
            taperEnabled: endTaperEnabled,
            customTaper: endCustomTaper,
            easing: StrokeEasings.easeOutCubic,
          ),

          // ✅ deeper=true：收口更完整；deeper=false：表層更跟筆
          isComplete: deeper,
        ),
      );

      _cachedPath = _polygonToPath(outline);
      _dirty = false;
    }

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
        easing: easing,
        simulatePressureWhenNoRealPressure: simulatePressureWhenNoRealPressure,
        minPointDistance: minPointDistance,
        maxPointDistance: maxPointDistance,
        dynamicMaxPointDistanceMin: dynamicMaxPointDistanceMin,
        speedDensify: speedDensify,
        speedScale: speedScale,
        cornerPreserve: cornerPreserve,
        useCatmull: useCatmull,
        catmullAlpha: catmullAlpha,
        predictedEventCount: predictedEventCount,
        predictedGateFactor: predictedGateFactor,
        predictedMaxPointDistanceFactor: predictedMaxPointDistanceFactor,
        startTaperEnabled: startTaperEnabled,
        startCustomTaper: startCustomTaper,
        endTaperEnabled: endTaperEnabled,
        endCustomTaper: endCustomTaper,
        capStart: capStart,
        capEnd: capEnd,
        dotScale: dotScale,
      );

  @override
  Map<String, dynamic> toContentJson() {
    return <String, dynamic>{
      'thinning': thinning,
      'smoothing': smoothing,
      'streamline': streamline,
      'simulatePressureWhenNoRealPressure': simulatePressureWhenNoRealPressure,
      'minPointDistance': minPointDistance,
      'maxPointDistance': maxPointDistance,
      'dynamicMaxPointDistanceMin': dynamicMaxPointDistanceMin,
      'speedDensify': speedDensify,
      'speedScale': speedScale,
      'cornerPreserve': cornerPreserve,
      'useCatmull': useCatmull,
      'catmullAlpha': catmullAlpha,
      'predictedEventCount': predictedEventCount,
      'predictedGateFactor': predictedGateFactor,
      'predictedMaxPointDistanceFactor': predictedMaxPointDistanceFactor,
      'startTaperEnabled': startTaperEnabled,
      'startCustomTaper': startCustomTaper,
      'endTaperEnabled': endTaperEnabled,
      'endCustomTaper': endCustomTaper,
      'capStart': capStart,
      'capEnd': capEnd,
      'dotScale': dotScale,
      'points': points.map((v) => {'x': v.x, 'y': v.y, 'p': v.p}).toList(),
      'paint': paint.toJson(),
    };
  }
}
