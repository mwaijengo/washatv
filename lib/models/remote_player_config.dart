/// Server-driven player policy (defaults when remote config has no player block).
class RemotePlayerConfig {
  const RemotePlayerConfig({
    this.preferredEngine = 'auto',
    this.bufferMinMs = 800,
    this.bufferMaxMs = 12000,
    this.initialBufferMs = 1500,
    this.retryMax = 4,
    this.retryDelayMs = 1200,
    this.reconnectEnabled = true,
    this.autoPlay = true,
    this.defaultQuality = '360p',
    this.failoverToWebview = true,
    this.hardwareAcceleration = true,
    this.softwareDecodeFallback = true,
    this.backgroundPlayback = false,
    this.resumePlayback = true,
    this.networkTimeoutMs = 15000,
    this.reconnectionPolicy = 'balanced',
    this.qualitiesAllowed = const ['240p', '360p', '480p', '720p'],
    this.languagesAllowed = const ['sw', 'en', 'ar', 'fr'],
  });

  final String preferredEngine;
  final int bufferMinMs;
  final int bufferMaxMs;
  final int initialBufferMs;
  final int retryMax;
  final int retryDelayMs;
  final bool reconnectEnabled;
  final bool autoPlay;
  final String defaultQuality;
  final bool failoverToWebview;
  final bool hardwareAcceleration;
  final bool softwareDecodeFallback;
  final bool backgroundPlayback;
  final bool resumePlayback;
  final int networkTimeoutMs;
  final String reconnectionPolicy;
  final List<String> qualitiesAllowed;
  final List<String> languagesAllowed;

  static const defaults = RemotePlayerConfig();

  factory RemotePlayerConfig.fromJson(Map<String, dynamic> json) {
    final qualities = json['qualitiesAllowed'];
    final languages = json['languagesAllowed'];
    return RemotePlayerConfig(
      preferredEngine: json['preferredEngine']?.toString() ?? 'auto',
      bufferMinMs: int.tryParse('${json['bufferMinMs']}') ?? 800,
      bufferMaxMs: int.tryParse('${json['bufferMaxMs']}') ?? 12000,
      initialBufferMs: int.tryParse('${json['initialBufferMs']}') ?? 1500,
      retryMax: int.tryParse('${json['retryMax']}') ?? 4,
      retryDelayMs: int.tryParse('${json['retryDelayMs']}') ?? 1200,
      reconnectEnabled: json['reconnectEnabled'] != false,
      autoPlay: json['autoPlay'] != false,
      defaultQuality: json['defaultQuality']?.toString() ?? '360p',
      failoverToWebview: json['failoverToWebview'] != false,
      hardwareAcceleration: json['hardwareAcceleration'] != false,
      softwareDecodeFallback: json['softwareDecodeFallback'] != false,
      backgroundPlayback: json['backgroundPlayback'] == true,
      resumePlayback: json['resumePlayback'] != false,
      networkTimeoutMs: int.tryParse('${json['networkTimeoutMs']}') ?? 15000,
      reconnectionPolicy: json['reconnectionPolicy']?.toString() ?? 'balanced',
      qualitiesAllowed: qualities is List
          ? qualities.map((e) => e.toString()).toList()
          : const ['auto', '240p', '360p', '480p', '720p', '1080p'],
      languagesAllowed: languages is List
          ? languages.map((e) => e.toString()).toList()
          : const ['sw', 'en'],
    );
  }
}
