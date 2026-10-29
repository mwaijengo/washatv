/// DRM mode from admin catalog: `none`, `clearkey`, or `widevine`.
enum ChannelDrm { none, clearkey, widevine }

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.premium,
    required this.imageUrl,
    required this.live,
    required this.category,
    this.apiId = '',
    this.streamAvailable = false,
    this.streamUrl = '',
    this.drm = ChannelDrm.none,
    this.drmClearKey,
  });

  final int id;
  /// Server channel id (e.g. `CH-abc123`) used to request playback.
  final String apiId;
  final String name;
  final bool premium;
  final String imageUrl;
  final bool live;
  final String category;
  /// Catalog flag — the stream itself is only fetched at play time and never persisted.
  final bool streamAvailable;
  final String streamUrl;
  final ChannelDrm drm;
  final String? drmClearKey;

  bool get hasStream => streamAvailable || streamUrl.trim().isNotEmpty;

  bool get needsProtectedPlayback =>
      drm == ChannelDrm.clearkey || drm == ChannelDrm.widevine;

  Channel withResolvedStream({
    required String streamUrl,
    required ChannelDrm drm,
    String? drmClearKey,
  }) {
    return Channel(
      id: id,
      apiId: apiId,
      name: name,
      premium: premium,
      imageUrl: imageUrl,
      live: live,
      category: category,
      streamAvailable: true,
      streamUrl: streamUrl,
      drm: drm,
      drmClearKey: drmClearKey,
    );
  }
}

ChannelDrm parseChannelDrm(Object? raw) {
  switch (raw?.toString().trim().toLowerCase()) {
    case 'clearkey':
      return ChannelDrm.clearkey;
    case 'widevine':
      return ChannelDrm.widevine;
    default:
      return ChannelDrm.none;
  }
}
