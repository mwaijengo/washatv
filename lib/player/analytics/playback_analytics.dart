/// No-op analytics stub for Washa playback events.
class PlaybackAnalytics {
  PlaybackAnalytics._();

  static Future<void> track({
    required String eventType,
    int? channelId,
    Map<String, dynamic>? payload,
  }) async {}

  static Future<void> trackChannelOpen({
    required int channelId,
    required String channelName,
    required String engine,
  }) async {}

  static Future<void> trackStreamFailure({
    required int channelId,
    required String reason,
    int? failoverStep,
  }) async {}

  static Future<void> trackBufferEvent({
    required int channelId,
    required bool isBuffering,
  }) async {}

  static Future<void> trackWatchDuration({
    required int channelId,
    required int seconds,
  }) async {}

  static Future<void> trackAutoHeal({
    required int channelId,
    required String symptom,
    required String action,
  }) async {}

  static Future<void> trackFailoverStep({
    required int channelId,
    required int step,
    required String streamUrl,
  }) async {}
}
