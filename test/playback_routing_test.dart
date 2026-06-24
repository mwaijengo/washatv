import 'package:flutter_test/flutter_test.dart';
import 'package:washa/models/channel.dart';
import 'package:washa/player/channel_playback_engine.dart';
import 'package:washa/player/playback_quality.dart';
import 'package:washa/player/stream_url_classifier.dart';

void main() {
  group('StreamUrlClassifier', () {
    test('detects php gateways', () {
      expect(StreamUrlClassifier.isPhpLikeUrl('https://cdn.example.com/play.php?id=1'), isTrue);
      expect(StreamUrlClassifier.isPhpLikeUrl('https://cdn.example.com/play.php'), isTrue);
      expect(StreamUrlClassifier.isPhpLikeUrl('https://cdn.example.com/stream.m3u8'), isFalse);
    });

    test('detects hls and dash urls', () {
      expect(StreamUrlClassifier.isLikelyHls('https://cdn.example.com/live/playlist.m3u8'), isTrue);
      expect(StreamUrlClassifier.isLikelyHls('https://cdn.example.com/hls/stream?fmt=m3u8'), isTrue);
      expect(StreamUrlClassifier.isLikelyDash('https://cdn.example.com/manifest.mpd'), isTrue);
      expect(StreamUrlClassifier.isLikelyDash('https://cdn.example.com/dash/live'), isTrue);
    });

    test('detects mp4 urls', () {
      expect(StreamUrlClassifier.hasObviousMp4('https://cdn.example.com/movie.mp4'), isTrue);
      expect(StreamUrlClassifier.hasObviousMp4('https://cdn.example.com/movie.m3u8'), isFalse);
    });
  });

  group('ChannelPlaybackSession.playbackRoutePlan', () {
    test('php gateway embed uses direct webview only', () {
      final routes = ChannelPlaybackSession.playbackRoutePlan(
        url: 'https://gate.example.com/live.php?ch=1',
      );
      expect(routes, [PlaybackRoute.directWebView]);
    });

    test('mpd tries native exo before shaka', () {
      final routes = ChannelPlaybackSession.playbackRoutePlan(
        url: 'https://cdn.example.com/live.mpd',
      );
      expect(routes.first, PlaybackRoute.nativeExo);
      expect(routes, contains(PlaybackRoute.shakaWebView));
    });

    test('drm uses shaka first', () {
      final routes = ChannelPlaybackSession.playbackRoutePlan(
        url: 'https://cdn.example.com/live.m3u8',
        drm: ChannelDrm.widevine,
      );
      expect(routes.first, PlaybackRoute.shakaWebView);
    });

    test('okoa bando hls still prefers native exo for fast start', () {
      final routes = ChannelPlaybackSession.playbackRoutePlan(
        url: 'https://cdn.example.com/live.m3u8',
        quality: PlaybackQuality.okoaBando,
      );
      expect(routes.first, PlaybackRoute.nativeExo);
      expect(routes, contains(PlaybackRoute.shakaWebView));
    });

    test('full quality hls prefers native exo', () {
      final routes = ChannelPlaybackSession.playbackRoutePlan(
        url: 'https://cdn.example.com/live.m3u8',
        quality: PlaybackQuality.full,
      );
      expect(routes.first, PlaybackRoute.nativeExo);
    });

    test('mp4 prefers native exo when data saver off', () {
      final routes = ChannelPlaybackSession.playbackRoutePlan(
        url: 'https://cdn.example.com/vod.mp4',
        quality: PlaybackQuality.full,
      );
      expect(routes.first, PlaybackRoute.nativeExo);
    });
  });
}
