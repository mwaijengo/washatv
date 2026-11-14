import 'dart:math';

import 'package:flutter/material.dart';

import 'admin_colors.dart';

/// Shared card look: soft sheen from the top-left, hairline border and a gentle drop shadow.
BoxDecoration adminCardDecoration({
  double radius = 18,
  Color? glow,
  bool shadow = true,
}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(
          AdminColors.bgTertiary,
          glow ?? Colors.white,
          glow == null ? 0.035 : 0.10,
        )!,
        AdminColors.bgTertiary,
      ],
    ),
    border: Border.all(
      color: glow?.withValues(alpha: 0.22) ?? const Color(0x14FFFFFF),
    ),
    boxShadow: shadow
        ? const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ]
        : null,
  );
}

/// Brand gradient used for the primary actions and the hero card (existing indigo → violet).
const LinearGradient adminBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF9333EA)],
);

/// Lifts slightly on hover (desktop/web) and sinks a little while pressed — makes cards feel tactile.
class AdminPressable extends StatefulWidget {
  const AdminPressable({
    super.key,
    required this.child,
    this.onTap,
    this.lift = 3,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double lift;
  final double pressedScale;

  @override
  State<AdminPressable> createState() => _AdminPressableState();
}

class _AdminPressableState extends State<AdminPressable> {
  bool _hover = false;
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _hover ? -widget.lift : 0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: widget.child,
            builder: (context, dy, child) =>
                Transform.translate(offset: Offset(0, dy), child: child),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides its child in once when first shown; [index] staggers siblings.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 14,
  });

  final Widget child;
  final int index;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.08).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 50),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * offset),
          child: child,
        ),
      ),
    );
  }
}

/// Counts up to [value] on first show and glides to new values when the data refreshes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  final num value;
  final String Function(num v) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Two soft colour glows behind the whole admin — depth without changing the palette.
class AdminAmbientBackground extends StatelessWidget {
  const AdminAmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-1.1, -1.2),
                    radius: 1.1,
                    colors: [Color(0x1F6366F1), Color(0x006366F1)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(1.2, 1.1),
                    radius: 1.0,
                    colors: [Color(0x149333EA), Color(0x009333EA)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Page title with a small brand-gradient accent bar.
class AdminPageHeading extends StatelessWidget {
  const AdminPageHeading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 24,
          decoration: BoxDecoration(
            gradient: adminBrandGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small uppercase label that groups sidebar items.
class AdminNavSection extends StatelessWidget {
  const AdminNavSection(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 12, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }
}

/// One option in [AdminFilterChips].
class AdminFilterOption {
  const AdminFilterOption(this.label, {this.count, this.color});
  final String label;
  final int? count;
  final Color? color;
}

/// Horizontally scrolling pill filters with live counts; the selected pill fills with its colour.
class AdminFilterChips extends StatelessWidget {
  const AdminFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<AdminFilterOption> options;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = options[i];
          final active = i == selected;
          final color = o.color ?? AdminColors.accentPrimary;
          return GestureDetector(
            onTap: () => onSelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? color.withValues(alpha: 0.22)
                    : const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? color.withValues(alpha: 0.55)
                      : const Color(0x14FFFFFF),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active ? Colors.white : AdminColors.textSecondary,
                    ),
                  ),
                  if (o.count != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? color.withValues(alpha: 0.35)
                            : const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${o.count}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: active
                              ? Colors.white
                              : AdminColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Rounded search box used above lists.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.loading = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 19,
          color: Color(0xFF818CF8),
        ),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: Color(0xFF6B7280),
                ),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: const Color(0x0DFFFFFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AdminColors.accentPrimary),
        ),
      ),
    );
  }
}

/// Pulsing green dot + label, for data that refreshes on its own.
class AdminLiveBadge extends StatefulWidget {
  const AdminLiveBadge({super.key, this.label = 'LIVE'});

  final String label;

  @override
  State<AdminLiveBadge> createState() => _AdminLiveBadgeState();
}

class _AdminLiveBadgeState extends State<AdminLiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF34D399);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1F10B981),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x4010B981)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 4 + 6 * _c.value,
                    height: 4 + 6 * _c.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: green.withValues(alpha: 0.5 * (1 - _c.value)),
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: green,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: green,
            ),
          ),
        ],
      ),
    );
  }
}

/// Initials in a brand-gradient circle.
class AdminAvatar extends StatelessWidget {
  const AdminAvatar(this.name, {super.key, this.size = 38, this.colors});

  final String name;
  final double size;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first
              .substring(0, parts.first.length >= 2 ? 2 : 1)
              .toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? const [Color(0xFF6366F1), Color(0xFF9333EA)],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Compact relative time: "sasa hivi", "dak 5", "saa 3", "jana", "siku 4".
String adminTimeAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 45) return 'sasa hivi';
  if (d.inMinutes < 60) return 'dak ${max(1, d.inMinutes)}';
  if (d.inHours < 24) return 'saa ${d.inHours}';
  if (d.inDays == 1) return 'jana';
  return 'siku ${d.inDays}';
}

/// Swahili greeting for the time of day.
String adminGreeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 12) return 'Habari za asubuhi';
  if (h < 16) return 'Habari za mchana';
  if (h < 19) return 'Habari za jioni';
  return 'Habari za usiku';
}

const _swDays = [
  'Jumatatu',
  'Jumanne',
  'Jumatano',
  'Alhamisi',
  'Ijumaa',
  'Jumamosi',
  'Jumapili',
];
const _swMonths = [
  'Januari',
  'Februari',
  'Machi',
  'Aprili',
  'Mei',
  'Juni',
  'Julai',
  'Agosti',
  'Septemba',
  'Oktoba',
  'Novemba',
  'Desemba',
];

/// e.g. "Jumamosi, 14 Novemba 2026".
String adminSwahiliDate([DateTime? now]) {
  final d = now ?? DateTime.now();
  return '${_swDays[d.weekday - 1]}, ${d.day} ${_swMonths[d.month - 1]} ${d.year}';
}
