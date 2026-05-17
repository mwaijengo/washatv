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
    this.streamUrl = '',
    this.drm = ChannelDrm.none,
  });

  final int id;
  final String name;
  final bool premium;
  final String imageUrl;
  final bool live;
  final String category;
  final String streamUrl;
  final ChannelDrm drm;

  bool get hasStream => streamUrl.trim().isNotEmpty;

  bool get needsProtectedPlayback =>
      drm == ChannelDrm.clearkey || drm == ChannelDrm.widevine;
}
