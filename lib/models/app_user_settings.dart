enum VideoQualityPreference {
  auto,
  q240,
  q360,
  q480,
  q720,
  q1080;

  String get label => switch (this) {
        VideoQualityPreference.auto => 'Otomatiki (HD)',
        VideoQualityPreference.q240 => '240p',
        VideoQualityPreference.q360 => '360p',
        VideoQualityPreference.q480 => '480p',
        VideoQualityPreference.q720 => '720p HD',
        VideoQualityPreference.q1080 => '1080p Full HD',
      };

  String get apiValue => switch (this) {
        VideoQualityPreference.auto => 'AUTO',
        VideoQualityPreference.q240 => '240p',
        VideoQualityPreference.q360 => '360p',
        VideoQualityPreference.q480 => '480p',
        VideoQualityPreference.q720 => '720p',
        VideoQualityPreference.q1080 => '1080p',
      };

  static VideoQualityPreference fromStored(String? raw) {
    return VideoQualityPreference.values.firstWhere(
      (e) => e.name == raw || e.apiValue == raw,
      orElse: () => VideoQualityPreference.auto,
    );
  }
}

enum PlayerTypePreference {
  auto,
  kotlin,
  exo,
  webview,
  webplayer,
  shaka;

  String get label => switch (this) {
        PlayerTypePreference.auto => 'Otomatiki (bora)',
        PlayerTypePreference.kotlin => 'Kotlin / Media3',
        PlayerTypePreference.exo => 'ExoPlayer',
        PlayerTypePreference.webview => 'WebView',
        PlayerTypePreference.webplayer => 'Web Player',
        PlayerTypePreference.shaka => 'Shaka Player',
      };

  String get engineValue => name;

  static PlayerTypePreference fromStored(String? raw) {
    if (raw == null || raw.isEmpty) return PlayerTypePreference.auto;
    return PlayerTypePreference.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => PlayerTypePreference.auto,
    );
  }
}

enum VideoZoomPreference {
  fit,
  fill,
  stretch;

  String get label => switch (this) {
        VideoZoomPreference.fit => 'Sawia (fit)',
        VideoZoomPreference.fill => 'Jaza skrini (fill)',
        VideoZoomPreference.stretch => 'Panua (stretch)',
      };

  /// Android ExoPlayer [AspectRatioFrameLayout] resize mode name.
  String get nativeMode => switch (this) {
        VideoZoomPreference.fit => 'fit',
        VideoZoomPreference.fill => 'zoom',
        VideoZoomPreference.stretch => 'fill',
      };

  static VideoZoomPreference fromStored(String? raw) {
    return VideoZoomPreference.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => VideoZoomPreference.fill,
    );
  }
}

enum ChannelDisplayStyle {
  scroll,
  grid;

  String get label => switch (this) {
        ChannelDisplayStyle.scroll => 'Mstari (scroll)',
        ChannelDisplayStyle.grid => 'Grid (safu 2)',
      };

  static ChannelDisplayStyle fromStored(String? raw) {
    return ChannelDisplayStyle.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ChannelDisplayStyle.scroll,
    );
  }
}

class AppUserSettings {
  const AppUserSettings({
    this.videoQuality = VideoQualityPreference.auto,
    this.playerType = PlayerTypePreference.auto,
    this.videoZoom = VideoZoomPreference.fill,
    this.channelDisplay = ChannelDisplayStyle.scroll,
    this.dataSaver = false,
  });

  final VideoQualityPreference videoQuality;
  final PlayerTypePreference playerType;
  final VideoZoomPreference videoZoom;
  final ChannelDisplayStyle channelDisplay;
  final bool dataSaver;

  AppUserSettings copyWith({
    VideoQualityPreference? videoQuality,
    PlayerTypePreference? playerType,
    VideoZoomPreference? videoZoom,
    ChannelDisplayStyle? channelDisplay,
    bool? dataSaver,
  }) {
    return AppUserSettings(
      videoQuality: videoQuality ?? this.videoQuality,
      playerType: playerType ?? this.playerType,
      videoZoom: videoZoom ?? this.videoZoom,
      channelDisplay: channelDisplay ?? this.channelDisplay,
      dataSaver: dataSaver ?? this.dataSaver,
    );
  }

  bool matches(AppUserSettings other) {
    return videoQuality == other.videoQuality &&
        playerType == other.playerType &&
        videoZoom == other.videoZoom &&
        channelDisplay == other.channelDisplay &&
        dataSaver == other.dataSaver;
  }

  static const defaults = AppUserSettings();
}
