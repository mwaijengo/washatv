import 'package:flutter/material.dart';

import '../app.dart';
import '../constants/app_channel_categories.dart';
import '../models/channel.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/glass_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.carouselIndex,
    required this.onCarouselDot,
    required this.onOpenPlayer,
    required this.onOpenSubscription,
    required this.premium,
    this.displayName,
  });

  final int carouselIndex;
  final ValueChanged<int> onCarouselDot;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final bool premium;
  final String? displayName;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String query = '';
  String selectedCategory = 'All';
  List<String> get categories {
    return ['All', ...kAppChannelCategories];
  }

  @override
  Widget build(BuildContext context) {
    bool matches(Channel c) {
      final byCategory = selectedCategory == 'All' || c.category == selectedCategory;
      final q = query.trim().toLowerCase();
      final byQuery = q.isEmpty || c.name.toLowerCase().contains(q) || c.category.toLowerCase().contains(q);
      return byCategory && byQuery;
    }

    final free = allChannels.where((e) => !e.premium && matches(e)).toList();
    final premiumChannels = allChannels.where((e) => e.premium && matches(e)).toList();
    final slide = heroSlides[widget.carouselIndex];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: SizedBox(
              height: 420,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 700),
                    child: Image.network(
                      slide.imageUrl,
                      fit: BoxFit.cover,
                      key: ValueKey(slide.imageUrl),
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF0F172A),
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined, size: 40, color: Color(0xFF6B7280)),
                      ),
                    ),
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xDD000000), Color(0x66000000), Colors.transparent],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    right: 22,
                    bottom: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(slide.title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                        Text(slide.subtitle, style: const TextStyle(color: Color(0xFFE5E7EB))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(heroSlides.length, (i) {
              final active = i == widget.carouselIndex;
              return GestureDetector(
                onTap: () => widget.onCarouselDot(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 28 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white30,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          _searchAndFilter(),
          const SizedBox(height: 18),
          const Text('Free Channels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _grid(free),
          const SizedBox(height: 16),
          GlassPanel(
            radius: 30,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.amber.withValues(alpha: 0.08), AppTheme.orange.withValues(alpha: 0.08)],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.amber, AppTheme.orange]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.workspace_premium),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fungua Channel Zote', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                        Text('30+ premium channels · TSh 25,000', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                      ],
                    ),
                  ),
                  ElevatedButton(onPressed: widget.onOpenSubscription, child: const Text('Fungua Sasa')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Premium Channels', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _grid(premiumChannels),
        ],
      ),
    );
  }

  Widget _grid(List<Channel> list) {
    return GridView.builder(
      itemCount: list.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) {
        final c = list[i];
        return ChannelCard(
          channel: c,
          locked: c.premium && !widget.premium,
          onTap: () => c.premium && !widget.premium ? widget.onOpenSubscription() : widget.onOpenPlayer(c),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final initials = _initials(widget.displayName);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [AppTheme.indigo, AppTheme.purple]),
          ),
          child: const Icon(Icons.play_arrow),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'WASHA TV',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.premium ? const Color(0xFFFBBF24) : const Color(0xFF374151),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.premium ? 'PREMIUM' : 'FREE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: widget.premium ? const Color(0xFF111827) : const Color(0xFFD1D5DB),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFFA855F7), Color(0xFFEC4899)]),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF374151),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF3F4F6),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _searchAndFilter() {
    return Row(
      children: [
        Expanded(
          flex: 7,
          child: GlassPanel(
            radius: 16,
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              style: const TextStyle(fontSize: 14, color: Colors.white),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: InputBorder.none,
                hintText: 'Tafuta channel...',
                hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                prefixIcon: Icon(Icons.search, color: Color(0xFFA5B4FC), size: 20),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: GlassPanel(
            radius: 16,
            child: DropdownButtonFormField<String>(
              initialValue: selectedCategory,
              isExpanded: true,
              dropdownColor: const Color(0xFF111827),
              icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFA5B4FC)),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none,
              ),
              items: categories
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c,
                      child: Text(
                        c,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => selectedCategory = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  String _initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty || n.toLowerCase() == 'free user') {
      return 'FU';
    }
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final first = parts.first;
      return first.substring(0, first.length.clamp(1, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
