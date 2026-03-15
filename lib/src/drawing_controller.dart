import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../paint_contents.dart';
import 'helper/safe_value_notifier.dart';
import 'paint_extension/ex_paint.dart';

/// 绘制参数
class DrawConfig {
  DrawConfig({
    required this.contentType,
    this.angle = 0,
    this.fingerCount = 0,
    this.size,
    this.blendMode = BlendMode.srcOver,
    this.color = Colors.red,
    this.colorFilter,
    this.filterQuality = FilterQuality.high,
    this.imageFilter,
    this.invertColors = false,
    this.isAntiAlias = false,
    this.maskFilter,
    this.shader,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.strokeWidth = 4,
    this.style = PaintingStyle.stroke,
  });

  DrawConfig.def({
    required this.contentType,
    this.angle = 0,
    this.fingerCount = 0,
    this.size,
    this.blendMode = BlendMode.srcOver,
    this.color = Colors.red,
    this.colorFilter,
    this.filterQuality = FilterQuality.high,
    this.imageFilter,
    this.invertColors = false,
    this.isAntiAlias = false,
    this.maskFilter,
    this.shader,
    this.strokeCap = StrokeCap.round,
    this.strokeJoin = StrokeJoin.round,
    this.strokeWidth = 4,
    this.style = PaintingStyle.stroke,
  });

  /// 旋转的角度（0:0,1:90,2:180,3:270）
  final int angle;

  final Type contentType;

  final int fingerCount;

  final Size? size;

  /// Paint相关
  final BlendMode blendMode;
  final Color color;
  final ColorFilter? colorFilter;
  final FilterQuality filterQuality;
  final ui.ImageFilter? imageFilter;
  final bool invertColors;
  final bool isAntiAlias;
  final MaskFilter? maskFilter;
  final Shader? shader;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final double strokeWidth;
  final PaintingStyle style;

  /// 生成paint
  Paint get paint => Paint()
    ..blendMode = blendMode
    ..color = color
    ..colorFilter = colorFilter
    ..filterQuality = filterQuality
    ..imageFilter = imageFilter
    ..invertColors = invertColors
    ..isAntiAlias = isAntiAlias
    ..maskFilter = maskFilter
    ..shader = shader
    ..strokeCap = strokeCap
    ..strokeJoin = strokeJoin
    ..strokeWidth = strokeWidth
    ..style = style;

  DrawConfig copyWith({
    Type? contentType,
    BlendMode? blendMode,
    Color? color,
    ColorFilter? colorFilter,
    FilterQuality? filterQuality,
    ui.ImageFilter? imageFilter,
    bool? invertColors,
    bool? isAntiAlias,
    MaskFilter? maskFilter,
    Shader? shader,
    StrokeCap? strokeCap,
    StrokeJoin? strokeJoin,
    double? strokeWidth,
    PaintingStyle? style,
    int? angle,
    int? fingerCount,
    Size? size,
  }) {
    return DrawConfig(
      contentType: contentType ?? this.contentType,
      angle: angle ?? this.angle,
      blendMode: blendMode ?? this.blendMode,
      color: color ?? this.color,
      colorFilter: colorFilter ?? this.colorFilter,
      filterQuality: filterQuality ?? this.filterQuality,
      imageFilter: imageFilter ?? this.imageFilter,
      invertColors: invertColors ?? this.invertColors,
      isAntiAlias: isAntiAlias ?? this.isAntiAlias,
      maskFilter: maskFilter ?? this.maskFilter,
      shader: shader ?? this.shader,
      strokeCap: strokeCap ?? this.strokeCap,
      strokeJoin: strokeJoin ?? this.strokeJoin,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      style: style ?? this.style,
      fingerCount: fingerCount ?? this.fingerCount,
      size: size ?? this.size,
    );
  }
}

/// 绘制控制器
class DrawingController extends ChangeNotifier {
  DrawingController({
    DrawConfig? config,
    PaintContent? content,
    this.onStrokeAdded,
    this.kMinStrokeDistance,
    this.allowEraserOnEmptyHistory = false,
  }) {
    _history = <PaintContent>[];
    _currentIndex = 0;
    realPainter = RePaintNotifier();
    painter = RePaintNotifier();
    drawConfig = SafeValueNotifier<DrawConfig>(config ?? DrawConfig.def(contentType: SimpleLine));
    setPaintContent(content ?? SimpleLine());
  }

  double? kMinStrokeDistance;

  /// classroom mode input-buffer 專用：
  /// 即使 controller 自己 history 為空，都允許 Eraser / ObjectEraser 開始畫
  bool allowEraserOnEmptyHistory;

  // callbacks
  final void Function(PaintContent content)? onStrokeAdded;

  /// 绘制开始点
  Offset? _startPoint;

  /// 画板数据Key
  late GlobalKey painterKey = GlobalKey();

  /// 控制器
  late SafeValueNotifier<DrawConfig> drawConfig;

  /// 最后一次绘制的内容
  late PaintContent _paintContent;

  /// 当前绘制内容
  PaintContent? currentContent;

  /// 橡皮擦内容
  PaintContent? eraserContent;

  ui.Picture? cachedPicture;

  /// 底层绘制内容(绘制记录)
  late List<PaintContent> _history;

  /// 当前controller是否存在
  bool _mounted = true;

  bool _surfaceRefreshQueued = false;
  bool _deepRefreshQueued = false;

  /// 获取绘制图层/历史
  List<PaintContent> get getHistory => _history;

  /// 步骤指针
  late int _currentIndex;

  /// 表层画布刷新控制
  RePaintNotifier? painter;

  /// 底层画布刷新控制
  RePaintNotifier? realPainter;

  /// 是否绘制了有效内容
  bool _isDrawingValidContent = false;

  /// 获取当前步骤索引
  int get currentIndex => _currentIndex;

  /// 获取当前颜色
  Color get getColor => drawConfig.value.color;

  /// 能否开始绘制
  bool get couldStartDraw => drawConfig.value.fingerCount == 0;

  /// 能否进行绘制
  bool get couldDrawing => drawConfig.value.fingerCount == 1;

  /// 是否有正在绘制的内容
  bool get hasPaintingContent => currentContent != null || eraserContent != null;

  /// 开始绘制点
  Offset? get startPoint => _startPoint;

  /// 设置画板大小
  void setBoardSize(Size? size) {
    drawConfig.value = drawConfig.value.copyWith(size: size);
  }

  /// 手指落下
  void addFingerCount(Offset offset) {
    drawConfig.value = drawConfig.value.copyWith(fingerCount: drawConfig.value.fingerCount + 1);
  }

  /// 手指抬起
  void reduceFingerCount(Offset offset) {
    if (drawConfig.value.fingerCount <= 0) return;
    drawConfig.value = drawConfig.value.copyWith(fingerCount: drawConfig.value.fingerCount - 1);
  }

  /// Create a new PaintContent by Type
  PaintContent _newContentFor(Type t) {
    if (t == Pointer) return Pointer();
    if (t == SimpleLine) return SimpleLine();
    if (t == SmoothLine) return SmoothLine();
    if (t == StraightLine) return StraightLine();
    if (t == Rectangle) return Rectangle();
    if (t == Circle) return Circle();
    if (t == Eraser) return Eraser();
    if (t == ObjectEraser) return ObjectEraser();
    if (t == PencilKitLine) return PencilKitLine();
    return SimpleLine();
  }

  /// Apply a full DrawConfig and sync _paintContent accordingly.
  void applyDrawConfig(DrawConfig cfg) {
    drawConfig.value = cfg;
    final PaintContent content = _newContentFor(cfg.contentType);
    setPaintContent(content);
  }

  /// 设置绘制样式
  void setStyle({
    BlendMode? blendMode,
    Color? color,
    ColorFilter? colorFilter,
    FilterQuality? filterQuality,
    ui.ImageFilter? imageFilter,
    bool? invertColors,
    bool? isAntiAlias,
    MaskFilter? maskFilter,
    Shader? shader,
    StrokeCap? strokeCap,
    StrokeJoin? strokeJoin,
    double? strokeMiterLimit,
    double? strokeWidth,
    PaintingStyle? style,
  }) {
    drawConfig.value = drawConfig.value.copyWith(
      blendMode: blendMode,
      color: color,
      colorFilter: colorFilter,
      filterQuality: filterQuality,
      imageFilter: imageFilter,
      invertColors: invertColors,
      isAntiAlias: isAntiAlias,
      maskFilter: maskFilter,
      shader: shader,
      strokeCap: strokeCap,
      strokeJoin: strokeJoin,
      strokeWidth: strokeWidth,
      style: style,
    );
  }

  /// 设置绘制内容
  void setPaintContent(PaintContent content) {
    content.paint = drawConfig.value.paint;
    _paintContent = content;
    drawConfig.value = drawConfig.value.copyWith(contentType: content.runtimeType);
  }

  void replaceCachedPicture(ui.Picture? picture) {
    if (identical(cachedPicture, picture)) {
      return;
    }
    cachedPicture?.dispose();
    cachedPicture = picture;
  }

  void clearCachedPicture() {
    replaceCachedPicture(null);
  }

  /// 完整替换历史 + 可视索引（用于精确还原）
  void setHistoryAndIndex(List<PaintContent> history, int index) {
    clearCachedPicture();
    _history
      ..clear()
      ..addAll(history);
    _currentIndex = index.clamp(0, _history.length);
    _refreshDeep();
    notifyListeners();
  }

  /// Replace drawing contents from a list at once（保持全部可见）
  void replaceAllContents(List<PaintContent> contents) {
    clearCachedPicture();
    _history
      ..clear()
      ..addAll(contents);
    _currentIndex = _history.length;
    _refreshDeep();
  }

  /// 添加一条绘制数据
  void addContent(PaintContent content) {
    final int hisLen = _history.length;
    if (hisLen > _currentIndex) {
      _history.removeRange(_currentIndex, hisLen);
    }

    _history.add(content);
    _currentIndex = _history.length;
    clearCachedPicture();
    _refreshDeep();
  }

  /// 添加多条数据
  void addContents(List<PaintContent> contents) {
    final int hisLen = _history.length;
    if (hisLen > _currentIndex) {
      _history.removeRange(_currentIndex, hisLen);
    }

    _history.addAll(contents);
    _currentIndex = _history.length;
    clearCachedPicture();
    _refreshDeep();
  }

  /// * 旋转画布
  void turn() {
    drawConfig.value = drawConfig.value.copyWith(angle: (drawConfig.value.angle + 1) % 4);
  }

  bool get _isAnyEraser => _paintContent is Eraser || _paintContent is ObjectEraser;

  /// 开始绘制
  void startDraw(Offset startPoint) {
    if (_currentIndex == 0 && _isAnyEraser && !allowEraserOnEmptyHistory) return;

    _isDrawingValidContent = false;
    _startPoint = startPoint;

    if (_isAnyEraser) {
      eraserContent = _paintContent.copy();
      eraserContent?.paint = drawConfig.value.paint.copyWith();
      eraserContent?.startDraw(startPoint);
    } else {
      currentContent = _paintContent.copy();
      currentContent?.paint = drawConfig.value.paint;
      currentContent?.startDraw(startPoint);
    }
  }

  void startDrawEvent(PointerDownEvent e) {
    if (_currentIndex == 0 && _isAnyEraser && !allowEraserOnEmptyHistory) return;

    _isDrawingValidContent = false;
    _startPoint = e.localPosition;

    if (_isAnyEraser) {
      eraserContent = _paintContent.copy();
      eraserContent?.paint = drawConfig.value.paint.copyWith();
      eraserContent?.onPointerDown(e);
    } else {
      currentContent = _paintContent.copy();
      currentContent?.paint = drawConfig.value.paint;
      currentContent?.onPointerDown(e);
    }
  }

  /// 取消绘制
  void cancelDraw() {
    _startPoint = null;
    currentContent = null;
    eraserContent = null;
  }

  /// 正在绘制（旧 Offset API）
  void drawing(Offset nowPaint) {
    if (!hasPaintingContent) return;

    if (!_isDrawingValidContent && _startPoint != null) {
      final double dist = (nowPaint - _startPoint!).distance;
      if (dist >= (kMinStrokeDistance ?? 0)) {
        _isDrawingValidContent = true;
      }
    }

    if (_paintContent is ObjectEraser) {
      eraserContent?.drawing(nowPaint);
      _refreshSurfacePerFrame();
      _refreshDeepPerFrame();
      return;
    }

    if (_paintContent is Eraser) {
      eraserContent?.drawing(nowPaint);
      _refreshSurfacePerFrame();
      return;
    }

    currentContent?.drawing(nowPaint);
    _refreshSurfacePerFrame();
  }

  void drawingEvent(PointerMoveEvent e) {
    if (!hasPaintingContent) return;

    final Offset nowPaint = e.localPosition;

    if (!_isDrawingValidContent && _startPoint != null) {
      final double dist = (nowPaint - _startPoint!).distance;
      if (dist >= (kMinStrokeDistance ?? 0)) {
        _isDrawingValidContent = true;
      }
    }

    if (_paintContent is ObjectEraser) {
      eraserContent?.onPointerMove(e);
      _refreshSurfacePerFrame();
      _refreshDeepPerFrame();
      return;
    }

    if (_paintContent is Eraser) {
      eraserContent?.onPointerMove(e);
      _refreshSurfacePerFrame();
      return;
    }

    currentContent?.onPointerMove(e);
    _refreshSurfacePerFrame();
  }

  /// 结束绘制
  void endDraw() {
    if (!hasPaintingContent) return;

    if (!_isDrawingValidContent) {
      _startPoint = null;
      currentContent = null;
      eraserContent = null;
      return;
    }

    _isDrawingValidContent = false;

    _startPoint = null;
    final int hisLen = _history.length;

    if (hisLen > _currentIndex) {
      _history.removeRange(_currentIndex, hisLen);
    }

    if (eraserContent != null) {
      _history.add(eraserContent!);
      _currentIndex = _history.length;
      if (_paintContent is Eraser || _paintContent is ObjectEraser) {
        onStrokeAdded?.call(_history.last);
      }
      eraserContent = null;
    }

    if (currentContent != null) {
      _history.add(currentContent!);
      _currentIndex = _history.length;
      onStrokeAdded?.call(_history.last);
      currentContent = null;
    }

    _refresh();
    _refreshDeep();
    notifyListeners();
  }

  void endDrawEvent(PointerUpEvent e) {
    if (!hasPaintingContent) return;

    if (_startPoint == e.localPosition) {
      drawing(e.localPosition);
    }

    if (_isAnyEraser) {
      eraserContent?.onPointerUp(e);
    } else {
      currentContent?.onPointerUp(e);
    }

    endDraw();
  }

  /// 撤销
  void undo() {
    clearCachedPicture();
    if (_currentIndex > 0) {
      _currentIndex = _currentIndex - 1;
      _refreshDeep();
      notifyListeners();
    }
  }

  bool canUndo() => _currentIndex > 0;

  /// 重做
  void redo() {
    clearCachedPicture();
    if (_currentIndex < _history.length) {
      _currentIndex = _currentIndex + 1;
      _refreshDeep();
      notifyListeners();
    }
  }

  bool canRedo() => _currentIndex < _history.length;

  /// 清理画布
  void clear() {
    clearCachedPicture();
    _history.clear();
    _currentIndex = 0;
    _refreshDeep();
  }

  /// 获取图片数据
  Future<ByteData?> getImageData() async {
    try {
      final RenderRepaintBoundary boundary =
          painterKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image =
          await boundary.toImage(pixelRatio: View.of(painterKey.currentContext!).devicePixelRatio);
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data;
    } catch (e) {
      debugPrint('获取图片数据出错:$e');
      return null;
    }
  }

  /// 获取表层图片数据
  Future<ByteData?> getSurfaceImageData() async {
    try {
      final ui.Picture? picture = cachedPicture;
      final Size? size = drawConfig.value.size;

      if (picture == null || size == null || size.isEmpty) {
        return null;
      }

      final ui.Image image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data;
    } catch (e) {
      debugPrint('获取表层图片数据出错:$e');
      return null;
    }
  }

  /// 获取画板内容Json（对象列表）
  List<Map<String, dynamic>> getJsonList() {
    return _history.map((PaintContent e) => e.toJson()).toList();
  }

  void _refreshSurfacePerFrame() {
    if (_surfaceRefreshQueued || !_mounted) {
      return;
    }
    _surfaceRefreshQueued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _surfaceRefreshQueued = false;
      if (!_mounted) return;
      _refresh();
    });
  }

  void _refreshDeepPerFrame() {
    if (_deepRefreshQueued || !_mounted) {
      return;
    }
    _deepRefreshQueued = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _deepRefreshQueued = false;
      if (!_mounted) return;
      _refreshDeep();
    });
  }

  /// 刷新表层画板
  void _refresh() {
    painter?._refresh();
  }

  /// 刷新底层画板
  void _refreshDeep() {
    realPainter?._refresh();
  }

  /// 销毁控制器
  @override
  void dispose() {
    if (!_mounted) return;

    clearCachedPicture();
    drawConfig.dispose();
    realPainter?.dispose();
    painter?.dispose();

    _mounted = false;
    super.dispose();
  }
}

/// 画布刷新控制器
class RePaintNotifier extends ChangeNotifier {
  void _refresh() {
    notifyListeners();
  }
}
