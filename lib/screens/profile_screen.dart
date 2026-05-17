import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';

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
  /// From Admin Settings (SharedPreferences). Empty until admin saves a number.
  final String supportWhatsapp;
  final VoidCallback onOpenSubscription;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = endDate?.difference(now) ?? Duration.zero;
    final initials = _initials(userName);
    final accent = const Color(0xFF8B5CF6);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 120),
      child: Column(
        children: [
          _topHeader(initials),
          const SizedBox(height: 10),
          GlassPanel(
            radius: 30,
            color: const Color(0x6A10182D),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x44243365), Color(0x2211182D)],
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFA855F7)]),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4B5563),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 30, color: Color(0xFFE5E7EB)),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF0B1220), width: 2),
                          ),
                          child: const Icon(Icons.person, size: 16, color: Color(0xFF9CA3AF)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 40 / 1.7)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B7280).withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: Text(
                          premium ? 'PREMIUM' : 'FREE',
                          style: TextStyle(
                            fontSize: 12,
                            color: premium ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: deviceId.trim().isEmpty ? null : () => _copyDeviceId(context),
                            borderRadius: BorderRadius.circular(12),
                            child: Tooltip(
                              message: deviceId.trim().isEmpty ? 'Hakuna Device ID' : 'Gusa kunakili Device ID',
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0x26FFFFFF)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.smartphone, size: 13, color: Color(0xFF6366F1)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        deviceId.trim().isEmpty ? '—' : deviceId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF9CA3AF),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.copy,
                                      size: 13,
                                      color: deviceId.trim().isEmpty ? const Color(0xFF475569) : const Color(0xFF818CF8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!premium)
            GlassPanel(
              radius: 22,
              color: const Color(0x66060D1E),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.workspace_premium, size: 30, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    const Text('Fungua Channel Zote', style: TextStyle(fontSize: 37 / 2, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Punguzo Kwa 60%', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width * 0.9,
                      height: 40,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: const Color(0xFF0B1220),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: onOpenSubscription,
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Fungua Sasa',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          GlassPanel(
            radius: 22,
            color: const Color(0x66060D1E),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.hourglass_bottom, size: 18, color: AppTheme.amber),
                      SizedBox(width: 6),
                      Text('Muda Uliosalia', style: TextStyle(fontSize: 34 / 2, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _count('Siku', premium ? diff.inDays : -1),
                      const SizedBox(width: 15),
                      _count('Masaa', premium ? diff.inHours % 24 : -1),
                      const SizedBox(width: 15),
                      _count('Dakika', premium ? diff.inMinutes % 60 : -1),
                      const SizedBox(width: 15),
                      _count('Sekunde', premium ? diff.inSeconds % 60 : -1),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      premium ? _expiryText(endDate) : 'Huna usajili',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            radius: 22,
            color: const Color(0x66060D1E),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: const CircleAvatar(backgroundColor: Color(0xFF22C55E), child: Icon(Icons.chat, color: Colors.white, size: 20)),
              title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                supportWhatsapp.trim().isEmpty ? 'Hakuna namba bado (weka Admin)' : supportWhatsapp.trim(),
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
              trailing: SizedBox(
                height: 34,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    disabledBackgroundColor: const Color(0xFF374151),
                  ),
                  onPressed: _whatsappDigits(supportWhatsapp).isEmpty
                      ? null
                      : () => launchProfileWhatsapp(supportWhatsapp),
                  child: const Text('Chat'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            radius: 22,
            color: const Color(0x66060D1E),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Usajili', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 34 / 2)),
                  const SizedBox(height: 10),
                  if (premium) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0x1AFBBF24),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x55FBBF24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.verified_rounded, color: Color(0xFFFBBF24), size: 20),
                              const SizedBox(width: 8),
                              const Text('PREMIUM IMETHIBITISHWA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            planLabel.isNotEmpty ? 'Mpango: $planLabel' : 'Mpango: Premium',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _accessSourceLabel(accessSource),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _expiryText(endDate),
                            style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2438),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('Akaunti ya Bure', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 32 / 2)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topHeader(String initials) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [AppTheme.indigo, AppTheme.purple]),
          ),
          child: const Icon(Icons.play_arrow, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Text('WASHA TV', style: TextStyle(fontSize: 38 / 2, fontWeight: FontWeight.w800)),
        const Spacer(),
        Stack(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFA855F7), Color(0xFFEC4899)]),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF374151)),
                child: Center(
                  child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF34D399),
                  border: Border.all(color: const Color(0xFF0B1220), width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _count(String label, int v) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x66111B2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        children: [
          Text(v < 0 ? '--' : v.toString().padLeft(2, '0'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28 / 2)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
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
    if (p.isEmpty) return 'FU';
    if (p.length == 1) return p.first.substring(0, p.first.length.clamp(1, 2)).toUpperCase();
    return '${p.first[0]}${p.last[0]}'.toUpperCase();
  }

  void _copyDeviceId(BuildContext context) {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Device ID imenakiliwa: $id'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
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
