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

  // ===== Coalesced events compatibility helper =====
  static List<PointerEvent> coalescedOf(PointerMoveEvent e) {
    final dynamic d = e;

    // 有啲版本係 property: e.coalescedEvents
    try {
      final List? raw = d.coalescedEvents as List?;
      if (raw != null && raw.isNotEmpty) return raw.cast<PointerEvent>();
    } catch (_) {}

    // 有啲版本係 method: e.getCoalescedEvents()
    // ⚠️ 用 dynamic 呼叫先唔會編譯期報錯
    try {
      final List? raw = d.getCoalescedEvents() as List?;
      if (raw != null && raw.isNotEmpty) return raw.cast<PointerEvent>();
    } catch (_) {}

    return const <PointerEvent>[];
  }

  // ===== Pressure helpers (also compatible via dynamic) =====
  static bool isStylus(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  static double normalizedPressure(PointerEvent e) {
    final dynamic d = e;
    try {
      final double p = (d.pressure as num?)?.toDouble() ?? 0.5;
      final double min = (d.pressureMin as num?)?.toDouble() ?? 0.0;
      final double max = (d.pressureMax as num?)?.toDouble() ?? 1.0;
      if (max <= min) return 0.5;
      return ((p - min) / (max - min)).clamp(0.0, 1.0);
    } catch (_) {
      return 0.5;
    }
  }

  static bool hasRealPressure(PointerEvent e) {
    if (!isStylus(e)) return false;
    final dynamic d = e;
    try {
      final double min = (d.pressureMin as num?)?.toDouble() ?? 0.0;
      final double max = (d.pressureMax as num?)?.toDouble() ?? 0.0;
      return max > min;
    } catch (_) {
      return false;
    }
  }
}
