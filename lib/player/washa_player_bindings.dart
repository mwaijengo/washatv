/// Optional control surface filled by [FullscreenVideoPage] when embedded.
class WashaPlayerBindings {
  Future<void> Function()? togglePlay;
  Future<void> Function(double fraction)? seek;
  bool Function()? isPlaying;
  Stream<bool>? playingStream;
  Stream<Duration>? positionStream;
  Stream<Duration>? durationStream;
  Future<void> Function()? pauseHandoff;
  Future<void> Function()? resumeHandoff;
}
