import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_status.dart';
import '../theme/app_theme.dart';
import '../widgets/cinematic_background.dart';
import '../widgets/gradient_button.dart';

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
        backgroundColor: AppTheme.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const CinematicBackground(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1.04).animate(
                        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                      ),
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: AppTheme.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.cyan.withValues(alpha: 0.35),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.system_update_alt_rounded, size: 42, color: AppTheme.background),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      widget.status.updateTitle,
                      textAlign: TextAlign.center,
                      style: AppTheme.displayMedium,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.status.updateMessage,
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppTheme.white10),
                      ),
                      child: Column(
                        children: [
                          _metaRow('Toleo lako', current),
                          const SizedBox(height: 10),
                          _metaRow('Inahitajika', _requiredLabel),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                    GradientButton(
                      label: 'Fungua Play Store',
                      icon: Icons.shop_rounded,
                      expanded: true,
                      onPressed: _openStore,
                      height: 52,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _checking ? null : _recheck,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textPrimary,
                          side: const BorderSide(color: AppTheme.white14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _checking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
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
        Expanded(child: Text(label, style: AppTheme.bodyMedium.copyWith(fontSize: 13))),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTheme.titleMedium.copyWith(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
