import 'package:flutter/material.dart';

import '../constants/app_channel_categories.dart';
import '../models/channel.dart';
import '../widgets/channel_card.dart';
import '../widgets/glass_panel.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.premium,
    required this.onOpenPlayer,
    required this.onOpenSubscription,
    required this.channels,
  });

  final bool premium;
  final ValueChanged<Channel> onOpenPlayer;
  final VoidCallback onOpenSubscription;
  final List<Channel> channels;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String? selected;
  String query = '';
  String selectedCategory = 'All';

  static List<String> get categories => List<String>.from(kAppChannelCategories);
  static const icons = {
    'Sports': Icons.sports_soccer,
    'Movies': Icons.movie,
    'News': Icons.newspaper,
    'Trending': Icons.local_fire_department,
    'Kids': Icons.child_friendly,
    'Wildlife': Icons.pets,
  };

  @override
  Widget build(BuildContext context) {
    bool matchesQuery(String value) => query.trim().isEmpty || value.toLowerCase().contains(query.trim().toLowerCase());

    if (selected == null) {
      final visibleCategories = categories.where((c) {
        final byQuery = matchesQuery(c);
        final byFilter = selectedCategory == 'All' || selectedCategory == c;
        return byQuery && byFilter;
      }).toList();

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: _searchAndFilter(),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              itemCount: visibleCategories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12),
              itemBuilder: (_, i) {
                final c = visibleCategories[i];
                final count = widget.channels.where((e) => e.category == c).length;
                return GestureDetector(
                  onTap: () => setState(() {
                    selected = c;
                    selectedCategory = c;
                  }),
                  child: GlassPanel(
                    radius: 20,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icons[c], size: 34),
                          const SizedBox(height: 8),
                          Text(c, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('$count', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
                          const Text('channels', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    final effectiveCategory = selectedCategory == 'All' ? selected : selectedCategory;
    final list = widget.channels.where((e) {
      final byCategory = e.category == effectiveCategory;
      final byQuery = matchesQuery(e.name) || matchesQuery(e.category);
      return byCategory && byQuery;
    }).toList();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              selected = null;
              selectedCategory = 'All';
              query = '';
            }),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Rudi'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _searchAndFilter(),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
            itemBuilder: (_, i) {
              final c = list[i];
              return ChannelCard(
                channel: c,
                locked: c.premium && !widget.premium,
                onTap: () => c.premium && !widget.premium ? widget.onOpenSubscription() : widget.onOpenPlayer(c),
              );
            },
          ),
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
              items: <String>['All', ...categories]
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
}
