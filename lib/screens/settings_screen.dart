import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_user_settings.dart';
import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';
import '../widgets/gradient_button.dart';
import '../widgets/section_header.dart';
import '../widgets/washa_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.premium,
    required this.onSaveAndRefresh,
    required this.onUpdateData,
    required this.onClearCaches,
    required this.onCheckPayment,
    this.busy = false,
    this.statusMessage,
  });

  final bool premium;
  final Future<void> Function(AppUserSettings settings) onSaveAndRefresh;
  final Future<void> Function(AppUserSettings settings) onUpdateData;
  final Future<void> Function() onClearCaches;
  final Future<String> Function() onCheckPayment;
  final bool busy;
  final String? statusMessage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettingsService.instance;
  late AppUserSettings _local;
  bool _checkingPayment = false;
  bool _refreshing = false;
  bool _clearingCaches = false;
  bool _saving = false;
  String? _actionMessage;

  bool get _dirty => !_local.matches(_settings.settings);

  @override
  void initState() {
    super.initState();
    _local = _settings.settings;
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() => _local = _settings.settings);
  }

  void _updateLocal(AppUserSettings next) {
    setState(() => _local = next);
  }

  Future<void> _saveAndRefresh() async {
    if (_saving || _refreshing) return;
    setState(() {
      _saving = true;
      _actionMessage = null;
    });
    try {
      await _settings.save(_local);
      await widget.onSaveAndRefresh(_local);
      if (mounted) {
        setState(() => _actionMessage = 'Mipangilio imehifadhiwa. Fungua channel ili kuona mabadiliko.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _actionMessage = 'Imeshindikana kuhifadhi. Jaribu tena.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: WashaAppBar(showAvatar: false, premium: widget.premium),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Mipangilio',
                  subtitle: 'Player, mwonekano na programu',
                  icon: Icons.tune_rounded,
                  accentColor: AppTheme.violet,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(child: _playerSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(child: _displaySection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(child: _saveSection()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(child: _appSection()),
            ),
            if (_actionMessage != null || widget.statusMessage != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(child: _statusBanner()),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 130),
              sliver: SliverToBoxAdapter(child: _exitButton()),
            ),
          ],
        );
      },
    );
  }

  Widget _playerSection() {
    return GlassPanel(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Player', style: AppTheme.titleLarge.copyWith(fontSize: 16)),
            Text(
              'Mipangilio ya player itatumika unapofungua channel baada ya kuhifadhi.',
              style: AppTheme.bodyMedium.copyWith(fontSize: 11, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            _dropdown<VideoQualityPreference>(
              label: 'Ubora wa video',
              value: _local.videoQuality,
              items: VideoQualityPreference.values,
              itemLabel: (v) => v.label,
              onChanged: (v) => _updateLocal(_local.copyWith(videoQuality: v)),
            ),
            const SizedBox(height: 12),
            _segmented<VideoZoomPreference>(
              label: 'Ukubwa wa video (zoom)',
              value: _local.videoZoom,
              options: VideoZoomPreference.values,
              labelFor: (v) => v.label,
              onChanged: (v) => _updateLocal(_local.copyWith(videoZoom: v)),
            ),
            const SizedBox(height: 12),
            _switchTile(
              label: 'Okoa bando (360p)',
              subtitle: 'Punguza matumizi ya data',
              value: _local.dataSaver,
              onChanged: (v) => _updateLocal(_local.copyWith(dataSaver: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _displaySection() {
    return GlassPanel(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mwonekano', style: AppTheme.titleLarge.copyWith(fontSize: 16)),
            const SizedBox(height: 14),
            _segmented<ChannelDisplayStyle>(
              label: 'Mtindo wa channeli',
              value: _local.channelDisplay,
              options: ChannelDisplayStyle.values,
              labelFor: (v) => v.label,
              onChanged: (v) => _updateLocal(_local.copyWith(channelDisplay: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveSection() {
    return GlassPanel(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hifadhi mipangilio',
                    style: AppTheme.titleLarge.copyWith(fontSize: 16),
                  ),
                ),
                if (_dirty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      'Haijahifadhiwa',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.gold,
                        fontSize: 9,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Hifadhi mabadiliko yako na yataanza kutumika unapofungua channel.',
              style: AppTheme.bodyMedium.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Hifadhi mabadiliko',
              icon: Icons.save_rounded,
              expanded: true,
              loading: _saving,
              onPressed: (_saving || _refreshing || widget.busy) ? null : _saveAndRefresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _appSection() {
    return GlassPanel(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Programu', style: AppTheme.titleLarge.copyWith(fontSize: 16)),
            const SizedBox(height: 14),
            _actionButton(
              icon: Icons.cloud_download_rounded,
              label: 'Update data',
              subtitle: 'Pakia channels, slides na mipangilio kutoka seva',
              loading: _refreshing || widget.busy,
              onTap: () async {
                if (_refreshing) return;
                setState(() {
                  _refreshing = true;
                  _actionMessage = null;
                });
                try {
                  if (_dirty) await _settings.save(_local);
                  await widget.onUpdateData(_local);
                  if (mounted) {
                    setState(() => _actionMessage = 'Data imesasishwa kutoka seva.');
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() => _actionMessage = 'Imeshindikana kusasisha data. Jaribu tena.');
                  }
                } finally {
                  if (mounted) setState(() => _refreshing = false);
                }
              },
            ),
            const SizedBox(height: 10),
            _actionButton(
              icon: Icons.cleaning_services_rounded,
              label: 'Clear caches',
              subtitle: 'Futa cache ya picha na data iliyohifadhiwa',
              loading: _clearingCaches,
              accent: AppTheme.violet,
              onTap: () async {
                if (_clearingCaches) return;
                setState(() {
                  _clearingCaches = true;
                  _actionMessage = null;
                });
                try {
                  await widget.onClearCaches();
                  if (mounted) {
                    setState(() => _actionMessage = 'Cache imefutwa kwa mafanikio.');
                  }
                } catch (_) {
                  if (mounted) {
                    setState(() => _actionMessage = 'Imeshindikana kufuta cache. Jaribu tena.');
                  }
                } finally {
                  if (mounted) setState(() => _clearingCaches = false);
                }
              },
            ),
            const SizedBox(height: 10),
            _actionButton(
              icon: Icons.payment_rounded,
              label: 'Angalia hali ya malipo',
              subtitle: 'Kwa waliolipa lakini channels bado zimefungwa',
              loading: _checkingPayment,
              accent: AppTheme.gold,
              onTap: () async {
                if (_checkingPayment) return;
                setState(() {
                  _checkingPayment = true;
                  _actionMessage = null;
                });
                try {
                  final msg = await widget.onCheckPayment();
                  if (mounted) setState(() => _actionMessage = msg);
                } finally {
                  if (mounted) setState(() => _checkingPayment = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner() {
    final text = _actionMessage ?? widget.statusMessage;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: AppTheme.bodyMedium.copyWith(fontSize: 13)),
    );
  }

  Widget _exitButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _confirmExitApp,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.danger,
          side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.power_settings_new_rounded),
        label: const Text('Funga programu', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _confirmExitApp() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Funga programu', style: AppTheme.titleLarge.copyWith(fontSize: 18)),
        content: Text(
          'Je unataka kutoka katika app?',
          style: AppTheme.bodyMedium.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Hapana', style: AppTheme.titleMedium.copyWith(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Ndiyo', style: AppTheme.titleMedium.copyWith(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (exit == true) {
      await SystemNavigator.pop();
    }
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceElevated,
              items: items
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(itemLabel(e), style: AppTheme.titleMedium.copyWith(fontSize: 13)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _segmented<T>({
    required String label,
    required T value,
    required List<T> options,
    required String Function(T) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final active = opt == value;
            return GestureDetector(
              onTap: () => onChanged(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: active ? AppTheme.primaryGradient : null,
                  color: active ? null : AppTheme.surfaceElevated,
                  border: Border.all(
                    color: active ? AppTheme.cyan.withValues(alpha: 0.5) : AppTheme.white10,
                  ),
                ),
                child: Text(
                  labelFor(opt),
                  style: AppTheme.labelSmall.copyWith(
                    fontSize: 10,
                    color: active ? AppTheme.background : AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _switchTile({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTheme.titleMedium.copyWith(fontSize: 14)),
              Text(subtitle, style: AppTheme.bodyMedium.copyWith(fontSize: 11)),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeThumbColor: AppTheme.cyan,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool loading = false,
    Color accent = AppTheme.cyan,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                      )
                    : Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTheme.titleMedium.copyWith(fontSize: 14)),
                    Text(subtitle, style: AppTheme.bodyMedium.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
