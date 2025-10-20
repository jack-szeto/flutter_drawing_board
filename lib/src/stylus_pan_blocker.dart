import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class StylusPanBlocker extends StatelessWidget {
  const StylusPanBlocker();

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent, // 讓底下的子節點仍可收到指標事件（Listener 照常）
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (EagerGestureRecognizer r) {
            // 只攔 stylus（建議同時包含 invertedStylus 以防橡皮端）
            r.supportedDevices = const {
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            };
          },
        ),
      },
      child: const SizedBox.expand(),
    );
  }
}
