// mouse_pan_blocker.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MousePanBlocker extends StatelessWidget {
  const MousePanBlocker({super.key});

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (EagerGestureRecognizer r) {
            // 只攔滑鼠；不要包含 trackpad，這樣觸控板雙指縮放仍然可用
            r.supportedDevices = const {PointerDeviceKind.mouse};
          },
        ),
      },
      child: const SizedBox.expand(),
    );
  }
}
