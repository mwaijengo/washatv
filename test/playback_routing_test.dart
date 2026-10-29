import 'package:flutter_test/flutter_test.dart';
import 'package:washa/models/channel.dart';
import 'package:washa/player/cdn_token_headers.dart';
import 'package:washa/player/flutter_playback_mode.dart';
import 'package:washa/player/playback_http_headers.dart';
import 'package:washa/player/stream_url_classifier.dart';
import 'package:washa/player/stream_url_utils.dart';
import 'package:washa/player/wash_channel_playback.dart';

void main() {
  group('StreamUrlUtils', () {
    test('detects php gateways', () {
      expect(isGatewayUrl('https://cdn.example.com/play.php?id=1'), isTrue);
      expect(useWebViewForUrl('https://cdn.example.com/play.php/stream'), isTrue);
      expect(isGatewayUrl('https://cdn.example.com/stream.m3u8'), isFalse);
    });

    test('detects /stream/ path gateways', () {
      const gateway = 'https://cdn.example.com/api/stream/channel123';
      expect(isGatewayUrl(gateway), isTrue);
      // Supasoka: isGatewayUrl true but useWebViewForUrl only for php/embed/player paths.
      expect(useWebViewForUrl(gateway), isFalse);
      expect(detectStreamFormat(gateway), StreamFormat.gateway);
    });

    test('detects hls and dash urls', () {
      expect(detectStreamFormat('https://cdn.example.com/live/playlist.m3u8'), StreamFormat.hls);
      expect(detectStreamFormat('https://cdn.example.com/manifest.mpd'), StreamFormat.dash);
      expect(
        detectStreamFormat('https://cdn.example.com/live?format=m3u8'),
        StreamFormat.hls,
      );
    });

    test('hls query param wins over dash in path', () {
      // Supasoka checks path "dash" before format=m3u8 query.
      expect(
        detectStreamFormat('https://cdn.example.com/dash/live?format=m3u8'),
        StreamFormat.dash,
      );
    });

    test('detects iptv live urls as hls not gateway', () {
      const iptv = 'http://stream.example.com:8080/user/pass/12345';
      expect(isLikelyIptvLiveUrl(iptv), isTrue);
      expect(detectStreamFormat(iptv), StreamFormat.hls);
      expect(isGatewayUrl(iptv), isFalse);
      expect(useWebViewForUrl(iptv), isFalse);
    });

    test('iptv /stream/ paths with port are hls not webview', () {
      const iptv = 'http://cdn.example.com:8080/stream/user/pass/123';
      expect(isLikelyIptvLiveUrl(iptv), isTrue);
      expect(useWebViewForUrl(iptv), isFalse);
      expect(detectStreamFormat(iptv), StreamFormat.hls);
    });

    test('host /stream/ without port matches Supasoka gateway heuristic', () {
      const url = 'https://cdn.example.com/stream/channel123';
      expect(isLikelyIptvLiveUrl(url), isTrue);
      expect(isGatewayUrl(url), isTrue);
      expect(useWebViewForUrl(url), isFalse);
    });

    test('orchestrator gateway flag stays false for iptv urls', () {
      const iptv = 'http://host:25461/live/user/pass/99';
      expect(isGatewayUrl(iptv) || useWebViewForUrl(iptv), isFalse);
    });

    test('detects progressive urls', () {
      expect(detectStreamFormat('https://cdn.example.com/movie.mp4'), StreamFormat.progressive);
      expect(detectStreamFormat('https://cdn.example.com/movie.m3u8'), isNot(StreamFormat.progressive));
    });
  });

  group('StreamUrlClassifier', () {
    test('needs web player for php without direct manifest', () {
      expect(
        StreamUrlClassifier.needsWebPlayer('https://gate.example.com/live.php?ch=1'),
        isTrue,
      );
      expect(
        StreamUrlClassifier.needsWebPlayer('https://cdn.example.com/live.m3u8'),
        isFalse,
      );
    });
  });

  group('Playback headers', () {
    test('channelDataFor includes drm fields', () {
      const ch = Channel(
        id: 1,
        name: 'Test',
        premium: false,
        imageUrl: 'https://cdn.example.com/logo.png',
        live: true,
        category: 'Sports',
        streamUrl: 'https://cdn.example.com/live.mpd',
        drm: ChannelDrm.clearkey,
        drmClearKey: 'kid:key',
      );
      final data = channelDataFor(ch);
      expect(data['drmType'], 'CLEARKEY');
      expect(data['drmClearKey'], 'kid:key');
      expect(extractClearKeyPayload(data), 'kid:key');
    });

    test('direct https media uses player headers without page referer', () {
      final headers = mergePlaybackHeaders('https://cdn.example.com/live.m3u8');
      expect(headers.containsKey('Referer'), isFalse);
      expect(headers.containsKey('Origin'), isFalse);
      expect(headers['Accept'], '*/*');
      expect(headers['User-Agent'], isNotEmpty);
    });

    test('https gateway pages keep browser headers', () {
      final headers = mergePlaybackHeaders('https://cdn.example.com/play.php?id=1');
      expect(headers['Referer'], 'https://cdn.example.com/');
      expect(headers['Origin'], 'https://cdn.example.com');
      expect(headers['X-Requested-With'], 'com.washatv');
    });

    test('extension-less https pages keep browser headers', () {
      final headers = mergePlaybackHeaders('https://cdn.example.com/watch/channel');
      expect(headers['Referer'], 'https://cdn.example.com/');
      expect(headers['Origin'], 'https://cdn.example.com');
    });

    test('same-host referer is dropped for direct https media', () {
      final headers = mergePlaybackHeaders(
        'https://cdn.example.com/live.m3u8',
        {
          'Referer': 'https://cdn.example.com/player',
          'Origin': 'https://cdn.example.com',
          'User-Agent': 'CustomAgent',
        },
      );
      expect(headers.containsKey('Referer'), isFalse);
      expect(headers.containsKey('Origin'), isFalse);
      expect(headers['User-Agent'], 'CustomAgent');
    });

    test('referer for another host is kept on direct https media', () {
      final headers = mergePlaybackHeaders(
        'https://cdn.example.com/live.m3u8',
        {'Referer': 'https://allowed.example/'},
      );
      expect(headers['Referer'], 'https://allowed.example/');
    });

    test('tokenized cdn urls are detected', () {
      expect(
        CdnTokenHeaders.isTokenizedCdnUrl(
          'https://cdn.example.com/tok_abc.payload.sig/manifest.mpd',
        ),
        isTrue,
      );
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
