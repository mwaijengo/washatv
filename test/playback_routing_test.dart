import 'package:flutter_test/flutter_test.dart';
import 'package:washa/models/channel.dart';
import 'package:washa/player/flutter_playback_mode.dart';
import 'package:washa/player/stream_url_utils.dart';
import 'package:washa/player/wash_channel_playback.dart';

void main() {
  group('StreamUrlUtils', () {
    test('detects php gateways', () {
      expect(isGatewayUrl('https://cdn.example.com/play.php?id=1'), isTrue);
      expect(useWebViewForUrl('https://cdn.example.com/play.php/stream'), isTrue);
      expect(isGatewayUrl('https://cdn.example.com/stream.m3u8'), isFalse);
    });

    test('detects hls and dash urls', () {
      expect(detectStreamFormat('https://cdn.example.com/live/playlist.m3u8'), StreamFormat.hls);
      expect(detectStreamFormat('https://cdn.example.com/manifest.mpd'), StreamFormat.dash);
    });

    test('detects progressive urls', () {
      expect(detectStreamFormat('https://cdn.example.com/movie.mp4'), StreamFormat.progressive);
      expect(detectStreamFormat('https://cdn.example.com/movie.m3u8'), isNot(StreamFormat.progressive));
    });
  });

  group('resolveFlutterPlaybackMode', () {
    test('php gateway uses native webview path on mobile', () {
      final mode = resolveFlutterPlaybackMode('https://gate.example.com/live.php?ch=1');
      expect(mode, FlutterPlaybackMode.mediaKit);
    });

    test('mpd uses media_kit by default', () {
      final mode = resolveFlutterPlaybackMode('https://cdn.example.com/live.mpd');
      expect(mode, FlutterPlaybackMode.mediaKit);
    });

    test('drm uses shaka', () {
      final mode = resolveFlutterPlaybackMode(
        'https://cdn.example.com/live.m3u8',
        drm: ChannelDrm.widevine,
      );
      expect(mode, FlutterPlaybackMode.shaka);
    });

    test('hls without drm prefers media_kit', () {
      final mode = resolveFlutterPlaybackMode('https://cdn.example.com/live.m3u8');
      expect(mode, FlutterPlaybackMode.mediaKit);
    });
  });
}
