import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_status.dart';

/// Non-dismissible gate — user must update from Play Store before using the app.
class ForceUpdateScreen extends StatefulWidget {
  const ForceUpdateScreen({
    super.key,
    required this.status,
    required this.onRecheck,
  });

  final AppUpdateStatus status;
  final Future<void> Function() onRecheck;

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  bool _checking = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _openStore() async {
    final uri = Uri.tryParse(widget.status.playStoreUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await widget.onRecheck();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String get _requiredLabel {
    final latest = widget.status.latestVersion;
    if (latest.isNotEmpty) {
      final buildSuffix = widget.status.latestBuild > 0 ? ' (build ${widget.status.latestBuild})' : '';
      return 'Toleo $latest$buildSuffix';
    }
    if (widget.status.minBuild > 0) {
      final v = widget.status.minVersion;
      return v.isNotEmpty ? 'Toleo $v (build ${widget.status.minBuild})' : 'Build ${widget.status.minBuild}';
    }
    if (widget.status.minVersion.isNotEmpty) return 'Toleo ${widget.status.minVersion}';
    return 'Toleo jipya';
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.status.currentVersion.isNotEmpty
        ? '${widget.status.currentVersion}${widget.status.currentBuild > 0 ? '+${widget.status.currentBuild}' : ''}'
        : '—';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.15,
                  colors: [
                    const Color(0xFF6366F1).withValues(alpha: 0.22),
                    const Color(0xFF0B1220),
                    const Color(0xFF0B1220),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1.04).animate(
                        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                      ),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.system_update_alt_rounded, size: 40, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      widget.status.updateTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.status.updateMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFFCBD5E1)),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x22FFFFFF)),
                      ),
                      child: Column(
                        children: [
                          _metaRow('Toleo lako', current),
                          const SizedBox(height: 8),
                          _metaRow('Inahitajika', _requiredLabel),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _openStore,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.shop_rounded),
                        label: const Text(
                          'Fungua Play Store',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _checking ? null : _recheck,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE2E8F0),
                          side: const BorderSide(color: Color(0x33FFFFFF)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _checking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                              )
                            : const Icon(Icons.refresh_rounded),
                        label: Text(_checking ? 'Inakagua…' : 'Nimesasisha — kagua tena'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8))),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF8FAFC)),
          ),
        ),
      ],
    );
  }
}
