import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 绘制对象
abstract class PaintContent {
  PaintContent();

  PaintContent.paint(this.paint);

  /// 画笔
  late Paint paint;

  /// 复制实例，避免对象传递
  PaintContent copy();

  /// 绘制核心方法
  /// * [deeper] 当前是否为底层绘制
  /// * 出于性能考虑
  /// * 绘制过程为表层绘制，绘制完成抬起手指时会进行底层绘制
  void draw(Canvas canvas, Size size, bool deeper);

  /// 正在绘制
  void drawing(Offset nowPoint);

  /// 开始绘制
  void startDraw(Offset startPoint);

  /// toJson
  Map<String, dynamic> toContentJson();

  /// contentType for web
  String get contentType => runtimeType.toString();

  /// toJson
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': contentType,
      ...toContentJson(),
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  // ===== Optional end hook (default empty) =====
  void endDraw() {}

  // ===== PointerEvent hooks (default fallback to old Offset API) =====
  void onPointerDown(PointerDownEvent e) => startDraw(e.localPosition);

  void onPointerMove(PointerMoveEvent e) {
    // ✅ 兼容新/舊 Flutter：有 coalesced 用 coalesced，冇就 fallback
    final List<PointerEvent> events = PaintContent.coalescedOf(e);
    if (events.isNotEmpty) {
      for (final pe in events) {
        drawing(pe.localPosition);
      }
    } else {
      drawing(e.localPosition);
    }
  }

  void onPointerUp(PointerUpEvent e) => endDraw();
  void onPointerCancel(PointerCancelEvent e) => endDraw();

  // =========================
  // ✅ pressure / coalesced / predicted helpers
  // =========================

  /// Flutter 3.38：唔一定有 getCoalescedEvents()，
  /// 而且你可能開咗 implicit-casts: false，所以要用 dynamic + is-check
  static List<PointerEvent> coalescedOf(PointerMoveEvent e) {
    try {
      final dynamic d = e; // dynamic invocation
      final dynamic got = d.getCoalescedEvents(); // dynamic result
      if (got is Iterable) {
        return got.whereType<PointerEvent>().toList(growable: false);
      }
      return const <PointerEvent>[];
    } catch (_) {
      return const <PointerEvent>[];
    }
  }

  /// ✅ predicted events：iOS（特別係 Pencil）會有；其他平台可能冇
  /// Flutter 版本差異好大，所以做多個 fallback：
  /// 1) e.predictedEvents（getter）
  /// 2) e.getPredictedEvents()（method）
  static List<PointerEvent> predictedOf(PointerMoveEvent e) {
    try {
      // 1) getter
      final dynamic d = e;
      final dynamic gotGetter = d.predictedEvents;
      if (gotGetter is Iterable) {
        return gotGetter.whereType<PointerEvent>().toList(growable: false);
      }
    } catch (_) {}
    try {
      // 2) method
      final dynamic d = e;
      final dynamic gotMethod = d.getPredictedEvents();
      if (gotMethod is Iterable) {
        return gotMethod.whereType<PointerEvent>().toList(growable: false);
      }
      return const <PointerEvent>[];
    } catch (_) {
      return const <PointerEvent>[];
    }
  }

  /// 有真 pressure（通常 stylus）
  static bool hasRealPressure(PointerEvent e) {
    final bool stylusLike =
        e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;
    final double min = e.pressureMin;
    final double max = e.pressureMax;
    return stylusLike && (max > min);
  }

  /// normalize 到 0..1
  static double normalizedPressure(PointerEvent e) {
    final double min = e.pressureMin;
    final double max = e.pressureMax;
    if (max <= min) return 0.5;
    final double v = (e.pressure - min) / (max - min);
    return v.clamp(0.0, 1.0);
  }
}
