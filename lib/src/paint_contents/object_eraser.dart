import 'package:flutter/material.dart';
import '../draw_path/draw_path.dart';
import '../paint_extension/ex_paint.dart';
import 'paint_content.dart';

class ObjectEraser extends PaintContent {
  ObjectEraser();

  ObjectEraser.data({
    required this.drawPath,
    required Paint paint,
  }) : super.paint(paint);

  factory ObjectEraser.fromJson(Map<String, dynamic> data) {
    return ObjectEraser.data(
      drawPath: DrawPath.fromJson(data['path'] as Map<String, dynamic>),
      paint: jsonToPaint(data['paint'] as Map<String, dynamic>),
    );
  }

  DrawPath drawPath = DrawPath();

  @override
  String get contentType => 'ObjectEraser';

  @override
  void startDraw(Offset startPoint) => drawPath.moveTo(startPoint.dx, startPoint.dy);

  @override
  void drawing(Offset nowPoint) => drawPath.lineTo(nowPoint.dx, nowPoint.dy);

  // 物件式擦除：不畫 clear；（可選）畫提示線
  @override
  void draw(Canvas canvas, Size size, bool deeper) {
    // optional: 只在表層畫提示
    // if (!deeper) canvas.drawPath(drawPath.path, paint);
  }

  @override
  ObjectEraser copy() => ObjectEraser();

  @override
  Map<String, dynamic> toContentJson() => {
        'path': drawPath.toJson(),
        'paint': paint.toJson(),
      };
}
