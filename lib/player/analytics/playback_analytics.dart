/// No-op analytics stub (EaMax batching not required for Washa).
class PlaybackAnalytics {
  PlaybackAnalytics._();

  static Future<void> trackChannelOpen({
    required int channelId,
    required String channelName,
    String? engine,
  }) async {}
}
