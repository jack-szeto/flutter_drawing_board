import 'package:flutter/material.dart';
import 'paint_content.dart';

/// A no-op tool used to let users pan/zoom the canvas without drawing.
class Pointer extends PaintContent {
  Pointer() : super();
  Pointer.paint(super.paint) : super.paint();

  @override
  PaintContent copy() {
    // Copy common paint fields to avoid sharing the same Paint instance.
    final Paint p = Paint()
      ..color = paint.color
      ..strokeWidth = paint.strokeWidth
      ..style = paint.style
      ..strokeCap = paint.strokeCap
      ..strokeJoin = paint.strokeJoin
      ..blendMode = paint.blendMode
      ..shader = paint.shader
      ..maskFilter = paint.maskFilter
      ..filterQuality = paint.filterQuality
      ..isAntiAlias = paint.isAntiAlias;
    return Pointer.paint(p);
  }

  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    // Intentionally no-op: Pointer tool doesn't render anything.
  }

  @override
  void drawing(Offset nowPoint) {
    // no-op
  }

  @override
  void startDraw(Offset startPoint) {
    // no-op
  }

  @override
  Map<String, dynamic> toContentJson() {
    return <String, dynamic>{};
  }
}
