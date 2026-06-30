import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/plan.dart';
import '../services/payment_config.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';

enum SonicpesaPaymentPhase { idle, initiating, waitingOnPhone, success, failed, cancelled }

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.plans,
    required this.premium,
    required this.selectedPlan,
    required this.endDate,
    required this.planLabel,
    required this.accessSource,
    required this.userName,
    required this.onPlanChange,
    required this.onPay,
    this.paymentSucceeded = false,
    this.localPaymentsOnly = false,
  });

  final List<Plan> plans;
  final bool premium;
  final Plan selectedPlan;
  final DateTime? endDate;
  final String planLabel;
  final String accessSource;
  final String userName;
  final ValueChanged<Plan> onPlanChange;
  final Future<void> Function(String phone, String name) onPay;
  /// Set by parent after SonicPesa confirms payment.
  final bool paymentSucceeded;
  /// Dev mode: API is localhost — simulated checkout without SonicPesa.
  final bool localPaymentsOnly;

  /// Full-screen SonicPesa / M-Pesa wait overlay (USSD push on customer phone).
  static Widget buildSonicpesaPaymentOverlay({
    required SonicpesaPaymentPhase phase,
    required String planLabel,
    required String amountLabel,
    String? statusLine,
    String? errorMessage,
    required VoidCallback onCancel,
    VoidCallback? onRetry,
    VoidCallback? onContinue,
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
                          ? (errorMessage ?? 'Jaribu tena au hakikisha una salio kwenye M-Pesa, Mixx, Airtel Money au Halotel.')
                          : isSuccess
                              ? 'Hongera! Channels zote zimefunguliwa.'
                              : '$planLabel · $amountLabel\n${statusLine ?? PaymentConfig.paymentPromptSw}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: isFailed ? const Color(0xFFFCA5A5) : const Color(0xFF9CA3AF),
                      ),
                    ),
                    if (!isSuccess) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 6,
                        runSpacing: 6,
                        children: PaymentConfig.mobileMoneyNetworks.map(_mpesaChip).toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (isSuccess && onContinue != null)
                      FilledButton(
                        onPressed: onContinue,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 46),
                        ),
                        child: const Text('Angalia hali ya akaunti', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
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
                    if (!isSuccess || onRetry != null || onContinue != null) const SizedBox(height: 8),
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
  bool hasSelectedPlan = false;
  final phone = TextEditingController();
  final name = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    phone.dispose();
    name.dispose();
    super.dispose();
  }

  bool get _showPremiumStatus {
    if (widget.premium) return true;
    final end = widget.endDate;
    return widget.paymentSucceeded && end != null && end.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    if (_showPremiumStatus) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.paymentSucceeded) const _PaymentSuccessBanner(),
              _PremiumAccountStatusPanel(
                userName: widget.userName,
                endDate: widget.endDate,
                planLabel: widget.planLabel,
                accessSource: widget.accessSource,
              ),
            ],
          ),
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

  bool get _nameOk => PaymentConfig.isValidFullName(name.text);
  bool get _phoneOk => PaymentConfig.isValidTzLocalPhone(phone.text);
  bool get _canPay => _nameOk && _phoneOk && hasSelectedPlan;

  List<Widget> _plansSection(BuildContext context) {
    return [
      if (!widget.premium) ...[
        const _FunguaZoteAudioGuidePanel(),
        const SizedBox(height: 14),
      ],
      if (widget.localPaymentsOnly)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x2210B981),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x4410B981)),
          ),
          child: const Text(
            'Hali ya majaribio: malipo ya ndani ya kompyuta pekee (seva ya localhost).',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: Color(0xFF6EE7B7), fontWeight: FontWeight.w600),
          ),
        ),
      _checkoutCard(
        step: 1,
        title: 'Andika majina yako kamili',
        child: _input(
          title: 'JINA KAMILI',
          hint: 'Majina ya mtumiaji',
          controller: name,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (_nameOk) ...[
        const SizedBox(height: 10),
        _checkoutCard(
          step: 2,
          title: 'Namba ya simu (M-Pesa, Mixx, Airtel, Halotel)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _input(
                title: 'NAMBA YA SIMU',
                hint: '0712345678 au 0612345678',
                controller: phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d+\s-]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                onChanged: (v) {
                  final normalized = PaymentConfig.normalizeTzLocalPhone(v);
                  if (normalized != null && normalized != v) {
                    phone.value = TextEditingValue(
                      text: normalized,
                      selection: TextSelection.collapsed(offset: normalized.length),
                    );
                  }
                  setState(() {});
                },
              ),
              if (phone.text.isNotEmpty && !_phoneOk)
                const Padding(
                  padding: EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Weka namba sahihi: 07…, 06… (Halotel 061/062/063/069), au tarakimu 9 bila 0',
                    style: TextStyle(fontSize: 11, color: Color(0xFFF87171)),
                  ),
                ),
              if (_phoneOk) ...[
                const SizedBox(height: 8),
                _networkBadge(phone.text),
              ],
            ],
          ),
        ),
      ],
      if (_nameOk && _phoneOk) ...[
        const SizedBox(height: 12),
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
              'Chagua kifurushi unachoweza kukimudu',
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            PaymentConfig.paymentPromptSw,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.35, color: Colors.white.withValues(alpha: 0.55)),
          ),
        ),
      ],
      if (_canPay) ...[
        const SizedBox(height: 14),
        _payNowButton(),
      ],
    ];
  }

  Widget _checkoutCard({required int step, required String title, required Widget child}) {
    return Container(
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
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: const Color(0xFF2563EB),
                child: Text('$step', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _networkBadge(String rawPhone) {
    final network = PaymentConfig.detectNetwork(rawPhone);
    final label = PaymentConfig.networkLabel(network);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x221E3A8A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x3393C5FD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_android_rounded, size: 14, color: Color(0xFF93C5FD)),
          const SizedBox(width: 6),
          Text(
            'Mtandao: $label',
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFBFDBFE)),
          ),
        ],
      ),
    );
  }

  Widget _payNowButton() {
    return AnimatedScale(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      scale: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D4ED8), Color(0xFF2563EB), Color(0xFF60A5FA)],
          ),
          border: Border.all(color: const Color(0x66BFDBFE)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.42),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              final normalizedPhone = PaymentConfig.normalizeTzLocalPhone(phone.text) ?? phone.text.trim();
              unawaited(widget.onPay(normalizedPhone, name.text.trim()));
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 26),
                  SizedBox(width: 12),
                  Expanded(
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
                  Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
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
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              textCapitalization: textCapitalization,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                border: InputBorder.none,
                isDense: true,
              ),
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
    final total = _player.duration ?? Duration.zero;
    final hasDuration = _ready && total.inMilliseconds > 0;
    final playing = _player.playing;
    final hasError = _loadErr != null;

    return GlassPanel(
      radius: 24,
      color: const Color(0x99101828),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x446366F1)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.headphones_rounded, size: 14, color: Color(0xFFC7D2FE)),
                    SizedBox(width: 6),
                    Text(
                      'Mwongozo wa sauti',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: Color(0xFFE0E7FF),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (playing) _AudioWaveBars(active: true),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Jinsi ya kufungua channel zote',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.3,
              color: Color(0xFFF8FAFC),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasError
                ? _loadErr!
                : 'Sikiliza maelezo kamili hapa, kisha endelea na hatua za malipo hapa chini.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: hasError ? const Color(0xFFF87171) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PlayOrb(
                playing: playing,
                enabled: !hasError && _ready,
                onTap: _toggle,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: hasError || !_ready ? null : _toggle,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: hasError || !_ready
                                  ? const [Color(0xFF334155), Color(0xFF475569)]
                                  : playing
                                      ? const [Color(0xFF4F46E5), Color(0xFF7C3AED)]
                                      : const [Color(0xFF2563EB), Color(0xFF6366F1)],
                            ),
                            boxShadow: hasError || !_ready
                                ? null
                                : [
                                    BoxShadow(
                                      color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                playing ? 'Sitisha' : 'Sikiliza',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hasDuration) ...[
                      const SizedBox(height: 12),
                      StreamBuilder<Duration>(
                        stream: _player.positionStream,
                        builder: (context, snap) {
                          final pos = snap.data ?? Duration.zero;
                          final double maxSlider =
                              total.inMilliseconds < 1 ? 1.0 : total.inMilliseconds.toDouble();
                          final double positionMs = pos.inMilliseconds
                              .toDouble()
                              .clamp(0.0, maxSlider)
                              .toDouble();
                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: SliderComponentShape.noOverlay,
                                  activeTrackColor: const Color(0xFF818CF8),
                                  inactiveTrackColor: const Color(0xFF334155),
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: positionMs,
                                  max: maxSlider,
                                  onChanged: (x) => _player.seek(Duration(milliseconds: x.round())),
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _fmt(pos),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    _fmt(total),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ] else if (!hasError) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: const Color(0xFF1E293B),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayOrb extends StatelessWidget {
  const _PlayOrb({required this.playing, required this.enabled, required this.onTap});

  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: enabled
                  ? const [Color(0xFF312E81), Color(0xFF1E1B4B)]
                  : const [Color(0xFF334155), Color(0xFF1E293B)],
            ),
            border: Border.all(
              color: enabled ? const Color(0xFF6366F1).withValues(alpha: 0.55) : const Color(0xFF475569),
              width: 1.5,
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: enabled ? Colors.white : const Color(0xFF64748B),
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _AudioWaveBars extends StatelessWidget {
  const _AudioWaveBars({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    const heights = [10.0, 16.0, 12.0, 18.0, 11.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < heights.length; i++)
          Container(
            width: 3,
            height: active ? heights[i] : 6,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFA5B4FC) : const Color(0xFF475569),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// Short-lived banner after payment — then premium status stays visible.
class _PaymentSuccessBanner extends StatelessWidget {
  const _PaymentSuccessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF166534)],
        ),
        border: Border.all(color: const Color(0xFF4ADE80)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Malipo yamekamilika!',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFFF0FDF4)),
                ),
                SizedBox(height: 2),
                Text(
                  'Channels zote zimefunguliwa — furahia premium!',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFFBBF7D0)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on Fungua zote when the user already has active premium.
class _PremiumAccountStatusPanel extends StatelessWidget {
  const _PremiumAccountStatusPanel({
    required this.userName,
    required this.endDate,
    required this.planLabel,
    required this.accessSource,
  });

  final String userName;
  final DateTime? endDate;
  final String planLabel;
  final String accessSource;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = endDate?.difference(now) ?? Duration.zero;
    final plan = planLabel.isNotEmpty ? planLabel : 'Premium';
    final sourceLabel = switch (accessSource) {
      'admin' => 'Ufikiaji kutoka msimamizi',
      'payment' => 'Malipo yaliyothibitishwa',
      _ => 'Usajili wa premium',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF312E81), Color(0xFF1E1B4B), Color(0xFF0F172A)],
            ),
            border: Border.all(color: const Color(0x44FBBF24)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF97316)]),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 38),
              ),
              const SizedBox(height: 14),
              Text(
                userName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x33FBBF24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x55FBBF24)),
                ),
                child: const Text(
                  'AKAUNTI YA PREMIUM',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Color(0xFFFDE68A)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _statusTile(
          icon: Icons.card_membership_rounded,
          label: 'Mpango',
          value: plan,
          accent: const Color(0xFF60A5FA),
        ),
        const SizedBox(height: 10),
        _statusTile(
          icon: Icons.info_outline_rounded,
          label: 'Chanzo',
          value: sourceLabel,
          accent: const Color(0xFFA78BFA),
        ),
        const SizedBox(height: 10),
        _statusTile(
          icon: Icons.hourglass_bottom_rounded,
          label: 'Muda uliosalia',
          value: '${diff.inDays} siku · ${diff.inHours % 24} masaa · ${diff.inMinutes % 60} dak',
          accent: const Color(0xFF34D399),
        ),
        if (endDate != null) ...[
          const SizedBox(height: 10),
          _statusTile(
            icon: Icons.event_rounded,
            label: 'Inaisha',
            value: '${endDate!.day}/${endDate!.month}/${endDate!.year} '
                '${endDate!.hour.toString().padLeft(2, '0')}:${endDate!.minute.toString().padLeft(2, '0')}',
            accent: const Color(0xFFFBBF24),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0x2210B981),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x3310B981)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Unaweza ku-stream channels zote za premium hadi muda uishe.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFCBD5E1)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x66111B2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
