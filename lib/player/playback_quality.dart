/// Playback quality / data-saver settings ("Okoa bando").
class PlaybackQuality {
  const PlaybackQuality({
    required this.dataSaverEnabled,
    this.maxHeight = kDefaultDataSaverHeight,
  });

  /// Okoa bando ON — cap adaptive streams at 360p (default).
  static const PlaybackQuality okoaBando = PlaybackQuality(dataSaverEnabled: true);

  /// Full quality — no height cap.
  static const PlaybackQuality full = PlaybackQuality(
    dataSaverEnabled: false,
    maxHeight: 0,
  );

  final bool dataSaverEnabled;

  /// Max video height in pixels; `0` = unlimited.
  final int maxHeight;

  int get effectiveMaxHeight => dataSaverEnabled ? maxHeight : 0;
}

/// Default cap when Okoa bando is enabled.
const int kDefaultDataSaverHeight = 360;
