import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_flutter_web/webview_flutter_web.dart';

bool _ready = false;

/// True after [registerWebviewPlatform] on web builds.
bool get isWebViewPlatformReady => _ready;

/// Registers [WebViewPlatform] for `flutter run -d chrome` / web builds.
void registerWebviewPlatform() {
  WebViewPlatform.instance ??= WebWebViewPlatform();
  _ready = true;
}
