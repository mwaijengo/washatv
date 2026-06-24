import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// Hybrid composition avoids SurfaceTexture glitches on Huawei/HiSilicon WebView video.
Widget buildStableWebViewWidget(WebViewController controller) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return WebViewWidget.fromPlatformCreationParams(
      params: AndroidWebViewWidgetCreationParams(
        controller: controller.platform,
        displayWithHybridComposition: true,
      ),
    );
  }
  return WebViewWidget(controller: controller);
}

/// Keeps a single [WebViewWidget] instance so Huawei/HiSilicon decoders are not
/// flushed on every parent rebuild.
class PinnedWebView extends StatefulWidget {
  const PinnedWebView({super.key, required this.controller});

  final WebViewController controller;

  @override
  State<PinnedWebView> createState() => _PinnedWebViewState();
}

class _PinnedWebViewState extends State<PinnedWebView> {
  late WebViewController _controller;
  Widget? _view;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _view = buildStableWebViewWidget(_controller);
  }

  @override
  void didUpdateWidget(PinnedWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller = widget.controller;
      _view = buildStableWebViewWidget(_controller);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(child: _view ?? const SizedBox.shrink());
}

/// Keeps a single [VideoPlayer] instance bound to one controller.
class PinnedVideoPlayer extends StatefulWidget {
  const PinnedVideoPlayer({
    super.key,
    required this.controller,
  });

  final VideoPlayerController controller;

  @override
  State<PinnedVideoPlayer> createState() => _PinnedVideoPlayerState();
}

class _PinnedVideoPlayerState extends State<PinnedVideoPlayer> {
  late VideoPlayerController _controller;
  Widget? _player;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _player = _buildPlayer();
  }

  @override
  void didUpdateWidget(PinnedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller = widget.controller;
      _player = _buildPlayer();
    }
  }

  Widget _buildPlayer() {
    final video = VideoPlayer(_controller);
    final size = _controller.value.size;
    final width = size.width > 0 ? size.width : 16.0;
    final height = size.height > 0 ? size.height : 9.0;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: width, height: height, child: video),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: _player ?? const SizedBox.shrink(),
    );
  }
}
