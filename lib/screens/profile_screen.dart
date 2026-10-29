import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';
import '../widgets/gradient_button.dart';
import '../widgets/section_header.dart';
import '../widgets/washa_app_bar.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.premium,
    required this.userName,
    required this.deviceId,
    required this.endDate,
    required this.planLabel,
    required this.accessSource,
    required this.supportWhatsapp,
    required this.onOpenSubscription,
  });

  final bool premium;
  final String userName;
  final String deviceId;
  final DateTime? endDate;
  final String planLabel;
  final String accessSource;
  final String supportWhatsapp;
  final VoidCallback onOpenSubscription;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = endDate?.difference(now) ?? Duration.zero;
    final initials = _initials(userName);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: WashaAppBar(
              displayName: userName,
              premium: premium,
              showAvatar: false,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(child: _profileHero(initials)),
        ),
        if (!premium)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(child: _premiumUpsell(context)),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: _countdownCard(diff)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: _whatsappCard(context)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: _subscriptionCard()),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 130)),
      ],
    );
  }

  Widget _profileHero(String initials) {
    return GlassPanel(
      radius: 28,
      glow: true,
      glowColor: premium ? AppTheme.gold : AppTheme.violet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.violet.withValues(alpha: 0.12),
              AppTheme.cyan.withValues(alpha: 0.06),
            ],
          ),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: premium ? AppTheme.premiumGradient : AppTheme.accentGradient,
                    boxShadow: [
                      BoxShadow(
                        color: (premium ? AppTheme.gold : AppTheme.violet).withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surfaceElevated,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: AppTheme.displayMedium.copyWith(fontSize: 32),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.background, width: 2),
                    ),
                    child: Icon(
                      premium ? Icons.verified_rounded : Icons.person_rounded,
                      size: 16,
                      color: premium ? AppTheme.gold : AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(userName, style: AppTheme.displayMedium.copyWith(fontSize: 24)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statusChip(premium ? 'PREMIUM' : 'FREE', premium),
                const SizedBox(width: 8),
                _deviceIdChip(),
              ],
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .scale(begin: const Offset(0.96, 0.96), duration: 500.ms, curve: Curves.easeOutBack);
  }

  Widget _statusChip(String label, bool isPremium) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: isPremium ? AppTheme.premiumGradient : null,
        color: isPremium ? null : AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPremium ? AppTheme.gold.withValues(alpha: 0.4) : AppTheme.white10,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.labelSmall.copyWith(
          color: isPremium ? AppTheme.background : AppTheme.textSecondary,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _deviceIdChip() {
    return Builder(
      builder: (context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: deviceId.trim().isEmpty ? null : () => _copyDeviceId(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smartphone_rounded, size: 13, color: AppTheme.cyan),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    deviceId.trim().isEmpty ? '—' : deviceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelSmall.copyWith(fontSize: 10),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.copy_rounded, size: 12, color: AppTheme.cyan.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _premiumUpsell(BuildContext context) {
    return GlassPanel(
      radius: 24,
      glow: true,
      glowColor: AppTheme.gold,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppTheme.premiumGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: AppTheme.gold.withValues(alpha: 0.3), blurRadius: 20),
                ],
              ),
              child: const Icon(Icons.diamond_rounded, color: AppTheme.background, size: 30),
            ),
            const SizedBox(height: 14),
            Text('Fungua Channel Zote', style: AppTheme.titleLarge.copyWith(fontSize: 20)),
            const SizedBox(height: 6),
            Text('Punguzo Kwa 60%', style: AppTheme.bodyMedium),
            const SizedBox(height: 16),
            GradientButton(
              label: 'Fungua Sasa',
              style: GradientButtonStyle.premium,
              expanded: true,
              onPressed: onOpenSubscription,
            ),
          ],
        ),
      ),
    )
        .animate(delay: 100.ms)
        .fadeIn(duration: 450.ms)
        .slideY(begin: 0.05, end: 0);
  }

  Widget _countdownCard(Duration diff) {
    return GlassPanel(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Muda Uliosalia',
              icon: Icons.hourglass_top_rounded,
              accentColor: AppTheme.amber,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _count('Siku', premium ? diff.inDays : -1),
                _count('Masaa', premium ? diff.inHours % 24 : -1),
                _count('Dakika', premium ? diff.inMinutes % 60 : -1),
                _count('Sek', premium ? diff.inSeconds % 60 : -1),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                premium ? _expiryText(endDate) : 'Huna usajili',
                style: AppTheme.bodyMedium.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: 150.ms)
        .fadeIn(duration: 450.ms);
  }

  Widget _whatsappCard(BuildContext context) {
    return GlassPanel(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WhatsApp', style: AppTheme.titleMedium),
                  Text(
                    supportWhatsapp.trim().isEmpty ? 'Hakuna namba bado' : supportWhatsapp.trim(),
                    style: AppTheme.bodyMedium.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            GradientButton(
              label: 'Chat',
              onPressed: _whatsappDigits(supportWhatsapp).isEmpty
                  ? null
                  : () => launchProfileWhatsapp(supportWhatsapp),
              height: 38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionCard() {
    return GlassPanel(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usajili', style: AppTheme.titleLarge),
            const SizedBox(height: 14),
            if (premium)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.gold.withValues(alpha: 0.12),
                      AppTheme.orange.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: AppTheme.gold, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'PREMIUM IMETHIBITISHWA',
                          style: AppTheme.labelSmall.copyWith(color: AppTheme.gold, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      planLabel.isNotEmpty ? 'Mpango: $planLabel' : 'Mpango: Premium',
                      style: AppTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(_accessSourceLabel(accessSource), style: AppTheme.bodyMedium.copyWith(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(_expiryText(endDate), style: AppTheme.bodyMedium.copyWith(fontSize: 12)),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.white07),
                ),
                child: Center(
                  child: Text('Akaunti ya Bure', style: AppTheme.titleMedium),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _count(String label, int v) {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.white07),
      ),
      child: Column(
        children: [
          Text(
            v < 0 ? '--' : v.toString().padLeft(2, '0'),
            style: AppTheme.displayMedium.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTheme.labelSmall.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  String _expiryText(DateTime? e) {
    if (e == null) return 'Muda uliosalia unaonyeshwa hapo juu';
    return 'Inaisha: ${e.day}/${e.month}/${e.year} ${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}';
  }

  String _accessSourceLabel(String source) {
    return switch (source) {
      'admin' => 'Ufikiaji uliotolewa na msimamizi',
      'payment' => 'Malipo yaliyothibitishwa',
      'legacy' => 'Usajili wa premium',
      _ => 'Akaunti ya premium',
    };
  }

  String _initials(String n) {
    final p = n.trim().split(RegExp(r'\s+'));
    if (p.isEmpty) return 'MT';
    if (p.length == 1) return p.first.substring(0, p.first.length.clamp(1, 2)).toUpperCase();
    return '${p.first[0]}${p.last[0]}'.toUpperCase();
  }

  void _copyDeviceId(BuildContext context) {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Device ID imenakiliwa: $id')),
    );
  }
}

String _whatsappDigits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

Future<void> launchProfileWhatsapp(String raw) async {
  final d = _whatsappDigits(raw);
  if (d.isEmpty) return;
  final uri = Uri.parse('https://wa.me/$d');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
