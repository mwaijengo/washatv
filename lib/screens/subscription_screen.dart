import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/plan.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';

enum SonicpesaPaymentPhase { idle, initiating, waitingOnPhone, success, failed, cancelled }

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.plans,
    required this.premium,
    required this.selectedPlan,
    required this.onPlanChange,
    required this.onPay,
    this.paymentSucceeded = false,
  });

  final List<Plan> plans;
  final bool premium;
  final Plan selectedPlan;
  final ValueChanged<Plan> onPlanChange;
  final Future<void> Function(String phone, String name) onPay;
  /// Set by parent after SonicPesa confirms payment.
  final bool paymentSucceeded;

  /// Full-screen SonicPesa / M-Pesa wait overlay (USSD push on customer phone).
  static Widget buildSonicpesaPaymentOverlay({
    required SonicpesaPaymentPhase phase,
    required String planLabel,
    required String amountLabel,
    String? statusLine,
    String? errorMessage,
    required VoidCallback onCancel,
    VoidCallback? onRetry,
  }) {
    final isFailed = phase == SonicpesaPaymentPhase.failed || phase == SonicpesaPaymentPhase.cancelled;
    final isSuccess = phase == SonicpesaPaymentPhase.success;

    return Positioned.fill(
      child: Container(
        color: const Color(0xE8000000),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: GlassPanel(
              radius: 28,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSuccess)
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                      )
                    else if (isFailed)
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 52)
                    else
                      const SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF60A5FA)),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      isSuccess
                          ? 'Malipo Yamethibitishwa!'
                          : isFailed
                              ? 'Malipo Hayajakamilika'
                              : phase == SonicpesaPaymentPhase.initiating
                                  ? 'Inatuma ombi la malipo…'
                                  : 'Thibitisha kwenye simu yako',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, height: 1.2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFailed
                          ? (errorMessage ?? 'Jaribu tena au hakikisha una salio la M-Pesa.')
                          : isSuccess
                              ? 'Hongera! Sasa unaweza ku-stream channels zote.'
                              : '$planLabel · $amountLabel\n${statusLine ?? 'Angalia simu yako — thibitisha PIN ya M-Pesa.'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: isFailed ? const Color(0xFFFCA5A5) : const Color(0xFF9CA3AF),
                      ),
                    ),
                    if (!isSuccess) ...[
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _mpesaChip('M-Pesa'),
                          const SizedBox(width: 8),
                          _mpesaChip('SonicPesa'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (isFailed && onRetry != null)
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Jaribu tena'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          minimumSize: const Size(double.infinity, 46),
                        ),
                      ),
                    if (!isSuccess || onRetry != null) const SizedBox(height: 8),
                    if (!isSuccess)
                      TextButton(
                        onPressed: onCancel,
                        child: Text(isFailed ? 'Funga' : 'Ghairi', style: const TextStyle(color: Color(0xFF94A3B8))),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _mpesaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x221E3A8A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x3393C5FD)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBFDBFE))),
    );
  }

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool get success => widget.paymentSucceeded || _localSuccess;
  bool _localSuccess = false;
  bool hasSelectedPlan = false;
  final phone = TextEditingController();
  final name = TextEditingController();

  @override
  void dispose() {
    phone.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SubscriptionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paymentSucceeded && !_localSuccess) {
      _localSuccess = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (success) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                    blurRadius: 34,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.check, size: 46, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text('Malipo Tayari!', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
            const SizedBox(height: 6),
            const Text('Hongera, sasa unaweza ku-stream channels zote', style: TextStyle(color: Color(0xFF9CA3AF))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _plansSection(context),
        ),
      ),
    );
  }

  bool get _isFormValid {
    final p = phone.text.trim();
    final n = name.text.trim();
    return RegExp(r'^0\d{9,10}$').hasMatch(p) && n.isNotEmpty;
  }

  List<Widget> _plansSection(BuildContext context) {
    return [
      if (!widget.premium) ...[
        const _FunguaZoteAudioGuidePanel(),
        const SizedBox(height: 14),
      ],
      Center(
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.9,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0x221E3A8A), Color(0x223B82F6)],
            ),
            border: Border.all(color: const Color(0x3393C5FD)),
          ),
          child: const Text(
            'Chagua kifurushi unachoweza kukimudu tafadhali',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE0ECFF),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      ...widget.plans.map(_planCard),
      const SizedBox(height: 8),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: !hasSelectedPlan
            ? const SizedBox.shrink()
            : Container(
                key: const ValueKey('payment-inline-form'),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.glass(
                  radius: BorderRadius.circular(20),
                  color: const Color(0x80111B2C),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Taarifa za Malipo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    _input(
                      title: 'NAMBA YA SIMU',
                      hint: '07XXXXXXXXXX',
                      controller: phone,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    _input(
                      title: 'JINA KAMILI',
                      hint: 'Mfano: John Joel',
                      controller: name,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      scale: _isFormValid ? 1 : 0.98,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _isFormValid
                                ? const [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF60A5FA)]
                                : const [Color(0xFF334155), Color(0xFF475569)],
                          ),
                          border: Border.all(
                            color: _isFormValid ? const Color(0x66BFDBFE) : const Color(0x338B9AB0),
                          ),
                          boxShadow: _isFormValid
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF3B82F6).withValues(alpha: 0.42),
                                    blurRadius: 22,
                                    offset: const Offset(0, 9),
                                  ),
                                ]
                              : [
                                  const BoxShadow(
                                    color: Color(0x22000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: !_isFormValid
                                ? null
                                : () async {
                                    try {
                                      await widget.onPay(phone.text.trim(), name.text.trim());
                                    } catch (_) {
                                      return;
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: const Color(0x33FFFFFF),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'LIPIA SASA',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                        color: Colors.white,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                                ],
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
    ];
  }

  Widget _planCard(Plan p) {
    return GestureDetector(
      onTap: () {
        setState(() => hasSelectedPlan = true);
        widget.onPlanChange(p);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: AppTheme.glass(
          radius: BorderRadius.circular(20),
          border: Border.all(width: 2, color: widget.selectedPlan.id == p.id ? const Color(0xFF3B82F6) : Colors.transparent),
          color: widget.selectedPlan.id == p.id ? const Color(0x143B82F6) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: p.id == 'gold'
                        ? const [Color(0xFFFBBF24), Color(0xFFF97316)]
                        : p.id == 'platinum'
                            ? const [Color(0xFFA855F7), Color(0xFF6366F1)]
                            : const [Color(0xFF38BDF8), Color(0xFF2563EB)],
                  ),
                ),
                child: Icon(
                  p.id == 'gold'
                      ? Icons.workspace_premium
                      : p.id == 'platinum'
                          ? Icons.diamond
                          : Icons.calendar_view_week,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.2,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Text(p.price, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input({
    required String title,
    String? value,
    String? hint,
    bool readOnly = false,
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          if (readOnly)
            Text(value ?? '', style: const TextStyle(fontWeight: FontWeight.w700))
          else
            TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(hintText: hint, border: InputBorder.none, isDense: true),
            ),
        ],
      ),
    );
  }
}

/// Full spoken guide (`assets/audio/fungua_zote_guide.mp3`) on the subscription screen.
class _FunguaZoteAudioGuidePanel extends StatefulWidget {
  const _FunguaZoteAudioGuidePanel();

  @override
  State<_FunguaZoteAudioGuidePanel> createState() => _FunguaZoteAudioGuidePanelState();
}

class _FunguaZoteAudioGuidePanelState extends State<_FunguaZoteAudioGuidePanel> {
  static const String _kAsset = 'assets/audio/fungua_zote_guide.mp3';
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  bool _ready = false;
  String? _loadErr;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _stateSub = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // On web, `setAsset` loads via the same URL as `assets/` + manifest key
      // (e.g. …/assets/assets/audio/…). Using `setUrl` avoids reading the whole
      // file into memory as a data URL and matches how the dev server serves assets.
      if (kIsWeb) {
        await _player.setUrl(Uri.base.resolve('assets/$_kAsset').toString());
      } else {
        await _player.setAsset(_kAsset);
      }
      if (mounted) {
        setState(() {
          _ready = true;
          _loadErr = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _loadErr =
              'Haikuweza kupakia faili la sauti. Fanya flutter clean, uanze upya uendeshaji wa Chrome (assets mpya hazionekani kwa hot reload).',
        );
      }
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width * 0.92;
    final total = _player.duration ?? Duration.zero;
    final hasDuration = _ready && total.inMilliseconds > 0;

    return Center(
      child: SizedBox(
        width: w,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE6111827), Color(0xE61E1B4B)],
            ),
            border: Border.all(color: const Color(0x55FBBF24)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.28),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x33FBBF24),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFFFDE68A), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'JINSI YA KUFUNGUA CHANNEL ZOTE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          height: 1.2,
                          color: Color(0xFFF8FAFC),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _loadErr ??
                      'Skiza maelezo yote hapa. Unaweza kusogeza mstari wa muda chini — kisha endelea na hatua za malipo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: _loadErr != null ? const Color(0xFFF87171) : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _loadErr != null || !_ready ? null : _toggle,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFBBF24),
                        foregroundColor: const Color(0xFF111827),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: Icon(_player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 26),
                      label: Text(
                        _player.playing ? 'Sitisha' : 'Cheza',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (hasDuration)
                      Expanded(
                        child: StreamBuilder<Duration>(
                          stream: _player.positionStream,
                          builder: (context, snap) {
                            final pos = snap.data ?? Duration.zero;
                            return Text(
                              '${_fmt(pos)} / ${_fmt(total)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE2E8F0),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (hasDuration)
                  StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, snap) {
                      final pos = snap.data ?? Duration.zero;
                      final maxMs = total.inMilliseconds.toDouble();
                      final v = (pos.inMilliseconds / maxMs).clamp(0.0, 1.0);
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 7,
                              backgroundColor: const Color(0xFF334155),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF818CF8)),
                            ),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              activeTrackColor: const Color(0xFFA5B4FC),
                              inactiveTrackColor: const Color(0xFF334155),
                              thumbColor: const Color(0xFFF8FAFC),
                            ),
                            child: Slider(
                              value: pos.inMilliseconds.toDouble().clamp(0, maxMs),
                              max: maxMs,
                              onChanged: (x) => _player.seek(Duration(milliseconds: x.round())),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                else
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(99)),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      backgroundColor: Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF64748B)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
