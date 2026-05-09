class HeroSlide {
  const HeroSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.premium,
    this.active = true,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final bool premium;
  final bool active;
  final int sortOrder;
}
