class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.premium,
    required this.imageUrl,
    required this.live,
    required this.category,
    this.streamUrl = '',
  });

  final int id;
  final String name;
  final bool premium;
  final String imageUrl;
  final bool live;
  final String category;
  final String streamUrl;

  bool get hasStream => streamUrl.trim().isNotEmpty;
}
