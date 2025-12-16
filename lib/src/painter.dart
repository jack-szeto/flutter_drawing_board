import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../paint_contents.dart';
import 'drawing_controller.dart';
import 'helper/ex_value_builder.dart';
import 'paint_contents/paint_content.dart';

/// 绘图板
class Painter extends StatelessWidget {
  const Painter({
    super.key,
    required this.drawingController,
    this.clipBehavior = Clip.antiAlias,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.allowedKinds,
  });

  /// 绘制控制器
  final DrawingController drawingController;

  /// 开始拖动
  final void Function(PointerDownEvent pde)? onPointerDown;

  /// 正在拖动
  final void Function(PointerMoveEvent pme)? onPointerMove;

  /// 结束拖动
  final void Function(PointerUpEvent pue)? onPointerUp;

  /// 边缘裁剪方式
  final Clip clipBehavior;

  final Set<PointerDeviceKind>? allowedKinds;

  bool _acceptsDevice(PointerEvent e) => allowedKinds == null || allowedKinds!.contains(e.kind);

  /// 手指落下
  void _onPointerDown(PointerDownEvent pde) {
    if (!_acceptsDevice(pde)) return;
    if (!drawingController.couldStartDraw) {
      return;
    }

    drawingController.startDraw(pde.localPosition);
    onPointerDown?.call(pde);
  }

  /// 手指移动
  void _onPointerMove(PointerMoveEvent pme) {
    if (!_acceptsDevice(pme)) return;
    if (!drawingController.couldDrawing) {
      if (drawingController.hasPaintingContent) {
        drawingController.endDraw();
      }

      return;
    }

    if (!drawingController.hasPaintingContent) {
      return;
    }

    drawingController.drawing(pme.localPosition);
    onPointerMove?.call(pme);
  }

  /// 手指抬起
  void _onPointerUp(PointerUpEvent pue) {
    if (!_acceptsDevice(pue)) return;
    if (!drawingController.couldDrawing || !drawingController.hasPaintingContent) {
      return;
    }

    if (drawingController.startPoint == pue.localPosition) {
      drawingController.drawing(pue.localPosition);
    }

    drawingController.endDraw();
    onPointerUp?.call(pue);
  }

  void _onPointerCancel(PointerCancelEvent pce) {
    if (!_acceptsDevice(pce)) return;
    if (!drawingController.couldDrawing) {
      return;
    }

    drawingController.endDraw();
  }

  /// GestureDetector 占位
  void _onPanDown(DragDownDetails ddd) {}

  void _onPanUpdate(DragUpdateDetails dud) {}

  void _onPanEnd(DragEndDetails ded) {}

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      // behavior: HitTestBehavior.opaque,
      child: ExValueBuilder<DrawConfig>(
        valueListenable: drawingController.drawConfig,
        shouldRebuild: (DrawConfig p, DrawConfig n) => p.fingerCount != n.fingerCount,
        builder: (_, DrawConfig config, Widget? child) {
          // 是否能拖动画布
          final bool isPanEnabled = config.fingerCount > 1;
          final bool touchWrites = allowedKinds?.contains(PointerDeviceKind.touch) ?? false;

          return GestureDetector(
            onPanDown: touchWrites && !isPanEnabled ? _onPanDown : null,
            onPanUpdate: touchWrites && !isPanEnabled ? _onPanUpdate : null,
            onPanEnd: touchWrites && !isPanEnabled ? _onPanEnd : null,
            child: child,
          );
        },
        child: ClipRect(
          clipBehavior: clipBehavior,
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: _DeepPainter(controller: drawingController),
              child: RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  painter: _UpPainter(controller: drawingController),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表层画板
class _UpPainter extends CustomPainter {
  _UpPainter({required this.controller}) : super(repaint: controller.painter);

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasPaintingContent) {
      return;
    }

    if (controller.eraserContent is Eraser) {
      canvas.saveLayer(Offset.zero & size, Paint());
      if (controller.cachedImage != null) {
        canvas.drawImage(controller.cachedImage!, Offset.zero, Paint());
      }
      controller.eraserContent?.draw(canvas, size, false); // clear path
      canvas.restore();
      return;
    }

    // ObjectEraser：唔好畫 cachedImage（可選：畫提示線）
    if (controller.eraserContent is ObjectEraser) {
      // optional: controller.eraserContent?.draw(canvas, size, false);
      return;
    }

    // 正常畫筆
    controller.currentContent?.draw(canvas, size, false);
  }

  @override
  bool shouldRepaint(covariant _UpPainter oldDelegate) => false;
}

/// 底层画板
class _DeepPainter extends CustomPainter {
  _DeepPainter({required this.controller}) : super(repaint: controller.realPainter);
  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.eraserContent is Eraser) {
      return;
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas tempCanvas = Canvas(recorder, Rect.fromPoints(Offset.zero, size.bottomRight(Offset.zero)));

    final List<PaintContent> cmds = _buildCmds(controller);
    if (cmds.isEmpty) return;

    final List<bool> keep = _computeKeep(cmds);

    canvas.saveLayer(Offset.zero & size, Paint());

    for (int i = 0; i < cmds.length; i++) {
      final PaintContent cmd = cmds[i];

      if (!keep[i]) {
        continue;
      }
      if (cmd is ObjectEraser) {
        continue; // 物件擦除唔畫任何像素
      }

      cmd.draw(canvas, size, true);
      cmd.draw(tempCanvas, size, true);
    }

    canvas.restore();

    final ui.Picture picture = recorder.endRecording();
    picture.toImage(size.width.toInt(), size.height.toInt()).then((ui.Image value) {
      controller.cachedImage = value;
    });
  }

  bool _hit(PaintContent c, List<Offset> erPts, double r) {
    if (erPts.isEmpty) return false;

    if (c is StraightLine) {
      final ui.Offset? a = c.startPoint;
      final ui.Offset? b = c.endPoint;
      if (a == null || b == null) {
        return false;
      }

      final double rr = r + c.paint.strokeWidth / 2;
      for (final ui.Offset p in erPts) {
        if (_distToSeg(p, a, b) <= rr) {
          return true;
        }
      }
      return false;
    }
    if (c is SimpleLine) {
      return _hitPolyline(erPts, c.path.points, r + c.paint.strokeWidth / 2);
    }

    if (c is SmoothLine) {
      return _hitPolyline(erPts, c.points, r + c.paint.strokeWidth / 2);
    }

    if (c is Rectangle) {
      final ui.Offset? a = c.startPoint;
      final ui.Offset? b = c.endPoint;
      if (a == null || b == null) {
        return false;
      }

      final ui.Rect rect = Rect.fromPoints(a, b);
      final List<ui.Offset> corners = <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
        rect.topLeft,
      ];

      final double rr = r + c.paint.strokeWidth / 2;
      for (final ui.Offset p in erPts) {
        for (int i = 0; i < 4; i++) {
          if (_distToSeg(p, corners[i], corners[i + 1]) <= rr) {
            return true;
          }
        }
      }
      return false;
    }

    return false;
  }

  bool _hitPolyline(List<Offset> erPts, List<Offset> pts, double r) {
    if (pts.length < 2) return false;
    for (final p in erPts) {
      for (int i = 0; i < pts.length - 1; i++) {
        if (_distToSeg(p, pts[i], pts[i + 1]) <= r) return true;
      }
    }
    return false;
  }

  double _distToSeg(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final ab2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (ab2 == 0) return (p - a).distance;
    final t = ((ap.dx * ab.dx) + (ap.dy * ab.dy)) / ab2;
    final tt = t.clamp(0.0, 1.0);
    final c = Offset(a.dx + ab.dx * tt, a.dy + ab.dy * tt);
    return (p - c).distance;
  }

  List<PaintContent> _buildCmds(DrawingController c) {
    final List<PaintContent> cmds = <PaintContent>[];
    for (int i = 0; i < c.currentIndex; i++) {
      cmds.add(c.getHistory[i]);
    }
    if (c.eraserContent is ObjectEraser) {
      cmds.add(c.eraserContent!); // ✅ 讓拖緊時即時見到效果
    }
    return cmds;
  }

  List<bool> _computeKeep(List<PaintContent> cmds) {
    final keep = List<bool>.filled(cmds.length, true);

    for (int i = 0; i < cmds.length; i++) {
      final cmd = cmds[i];
      if (cmd is! ObjectEraser) continue;

      final erPts = cmd.drawPath.points; // ✅ 下面 E) 會講點加
      final r = (cmd.paint.strokeWidth <= 0 ? 10.0 : cmd.paint.strokeWidth / 2);

      for (int j = 0; j < i; j++) {
        if (!keep[j]) continue;

        final target = cmds[j];
        if (target is Eraser || target is ObjectEraser) continue; // 一般唔擦 eraser 指令
        if (_hit(target, erPts, r)) keep[j] = false;
      }
    }

    return keep;
  }

  @override
  bool shouldRepaint(covariant _DeepPainter oldDelegate) => false;
}
