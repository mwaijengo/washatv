import 'package:flutter_test/flutter_test.dart';
import 'package:washa/player/stream_url_classifier.dart';
import 'package:washa/player/stream_url_resolver.dart';

void main() {
  group('StreamUrlResolver', () {
    test('returns direct hls urls unchanged', () async {
      const url = 'https://cdn.example.com/live/playlist.m3u8';
      final resolved = await StreamUrlResolver.resolve(url);
      expect(resolved.playbackUrl, url);
      expect(resolved.isGatewayEmbed, isFalse);
    });

    test('marks unresolved php as gateway embed', () async {
      const url = 'https://gate.example.com/live.php?ch=1';
      final resolved = await StreamUrlResolver.resolve(url);
      expect(resolved.gatewayUrl, url);
      expect(resolved.isGatewayEmbed, isTrue);
    });
  });

  group('StreamUrlClassifier direct urls', () {
    test('php is not direct', () {
      expect(
        StreamUrlClassifier.isDirectStreamUrl('https://gate.example.com/live.php?ch=1'),
        isFalse,
      );
    });

    test('m3u8 is direct', () {
      expect(
        StreamUrlClassifier.isDirectStreamUrl('https://cdn.example.com/live.m3u8'),
        isTrue,
      );
    });
  });
}
