import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/plan.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_panel.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.plans,
    required this.premium,
    required this.selectedPlan,
    required this.onPlanChange,
    required this.onPay,
    required this.onOpenTutorial,
  });

  final List<Plan> plans;
  final bool premium;
  final Plan selectedPlan;
  final ValueChanged<Plan> onPlanChange;
  final Future<void> Function(String phone, String name) onPay;
  final VoidCallback onOpenTutorial;

  static Widget buildTutorialModal({
    required int step,
    required VoidCallback onClose,
    required VoidCallback onNext,
    required VoidCallback onBack,
    required VoidCallback onFinish,
    ValueChanged<int>? onHighlightedOptionChanged,
  }) {
    return Positioned.fill(
      child: _TutorialPlayerModal(
        step: step,
        onClose: onClose,
        onNext: onNext,
        onBack: onBack,
        onFinish: onFinish,
        onHighlightedOptionChanged: onHighlightedOptionChanged,
      ),
    );
  }

  static Widget buildPinModal({
    required VoidCallback onCancel,
    required Future<void> Function() onConfirm,
  }) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xE0000000),
        child: Center(
          child: GlassPanel(
            radius: 28,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔐', style: TextStyle(fontSize: 50)),
                  const SizedBox(height: 10),
                  const Text('Thibitisha Malipo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
                  const SizedBox(height: 8),
                  const Text('Ingiza PIN yako ya simu'),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      4,
                      (_) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xCC1F2937),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('•', style: TextStyle(fontSize: 24)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(onPressed: onConfirm, child: const Text('Thibitisha')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: onCancel, child: const Text('Ghairi')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool success = false;
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
      Center(
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.9,
          height: 60,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFFA855F7)]),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: widget.onOpenTutorial,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              icon: const Icon(Icons.help_outline_rounded, color: Colors.white, size: 18),
              label: const Row(
                children: [
                  Expanded(
                    child: Text(
                      'JINSI YA KUFUNGUA CHANNEL ZOTE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.4),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
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
                                    await widget.onPay(phone.text.trim(), name.text.trim());
                                    if (!mounted) return;
                                    setState(() => success = true);
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

class _TutorialPlayerModal extends StatefulWidget {
  const _TutorialPlayerModal({
    required this.step,
    required this.onClose,
    required this.onNext,
    required this.onBack,
    required this.onFinish,
    this.onHighlightedOptionChanged,
  });

  final int step;
  final VoidCallback onClose;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onFinish;
  final ValueChanged<int>? onHighlightedOptionChanged;

  @override
  State<_TutorialPlayerModal> createState() => _TutorialPlayerModalState();
}

class _TutorialPlayerModalState extends State<_TutorialPlayerModal> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  int _priceSelection = 0;
  Timer? _priceTimer;
  Timer? _typingTimer;
  Timer? _step5Timer;
  Timer? _autoAdvanceTimer;
  int _phoneChars = 0;
  int _nameChars = 0;
  bool _payPressed = false;
  int _pinFilled = 0;
  bool _sendPressed = false;
  bool _step5Success = false;
  bool _autoProgressScheduled = false;

  static const List<String> _titles = <String>[
    'Karibu Washa Tv',
    'UMEKWAMA',
    'Hatua 3: Vifurushi',
    'Hatua 4: Taarifa za Mtumiaji',
    'Hatua 5: Kamilisha Malipo',
  ];

  @override
  void initState() {
    super.initState();
    _audioPlayer.setSpeed(1.15);
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      final done = state.processingState == ProcessingState.completed;
      if (done || !state.playing) {
        setState(() => _isPlaying = false);
      }
      if (done) {
        _scheduleAutoProgress();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safePlayStepAudio();
    });
    _startPriceAnimation();
  }

  Future<void> _safePlayStepAudio() async {
    try {
      await _playStepAudio();
    } catch (_) {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  @override
  void didUpdateWidget(covariant _TutorialPlayerModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      _autoAdvanceTimer?.cancel();
      _autoProgressScheduled = false;
      _safePlayStepAudio();
      if (widget.step == 3) {
        _startPriceAnimation();
      } else {
        _priceTimer?.cancel();
      }
      if (widget.step == 4) {
        _startStep4TypingDemo();
      } else {
        _typingTimer?.cancel();
      }
      if (widget.step == 5) {
        _startStep5PinDemo();
      } else {
        _step5Timer?.cancel();
      }
    }
  }

  Future<void> _playStepAudio() async {
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() => _isPlaying = false);
    const audioByStep = <int, String>{
      1: 'assets/audio/1.Salamu.mp3',
      2: 'assets/audio/2.dhumuni.mp3',
      3: 'assets/audio/3.Vifurushi.mp3',
      4: 'assets/audio/4.Taarifa za mtumiaji.mp3',
      5: 'assets/audio/5.Kamilisha malipo.mp3',
    };
    final asset = audioByStep[widget.step];
    if (asset == null) return;
    await _audioPlayer.setAsset(asset);
    await _audioPlayer.play();
    if (!mounted) return;
    setState(() => _isPlaying = true);
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _typingTimer?.cancel();
    _step5Timer?.cancel();
    _autoAdvanceTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _scheduleAutoProgress() {
    if (_autoProgressScheduled) return;
    _autoProgressScheduled = true;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (widget.step < 5) {
        widget.onNext();
      } else {
        widget.onFinish();
      }
    });
  }

  void _startPriceAnimation() {
    _priceTimer?.cancel();
    if (widget.step != 3) return;
    _priceSelection = 0;
    _notifyHighlightedOptionChanged();
    _priceTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (!mounted || widget.step != 3) return;
      setState(() => _priceSelection = (_priceSelection + 1) % 3);
      _notifyHighlightedOptionChanged();
    });
  }

  void _notifyHighlightedOptionChanged() {
    final cb = widget.onHighlightedOptionChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(_priceSelection);
    });
  }

  void _startStep4TypingDemo() {
    _typingTimer?.cancel();
    _phoneChars = 0;
    _nameChars = 0;
    _payPressed = false;
    const phone = '07123456789';
    const userName = 'John Joel';
    _typingTimer = Timer.periodic(const Duration(milliseconds: 130), (t) {
      if (!mounted || widget.step != 4) return;
      setState(() {
        if (_phoneChars < phone.length) {
          _phoneChars++;
          return;
        }
        if (_nameChars < userName.length) {
          _nameChars++;
          return;
        }
        if (!_payPressed) {
          _payPressed = true;
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (!mounted || widget.step != 4) return;
            setState(() => _payPressed = false);
          });
          t.cancel();
        }
      });
    });
  }

  void _startStep5PinDemo() {
    _step5Timer?.cancel();
    _pinFilled = 0;
    _sendPressed = false;
    _step5Success = false;
    _step5Timer = Timer.periodic(const Duration(milliseconds: 520), (t) {
      if (!mounted || widget.step != 5) return;
      setState(() {
        if (_pinFilled < 4) {
          _pinFilled++;
          return;
        }
        if (!_sendPressed) {
          _sendPressed = true;
          return;
        }
        _step5Success = true;
        t.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final modalWidth = (size.width * 0.94).clamp(360.0, 760.0);
    final modalMaxHeight = size.height * 0.9;

    return Container(
      color: const Color(0xE0000000),
      child: Center(
        child: GlassPanel(
          radius: 30,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: modalWidth,
              maxHeight: modalMaxHeight,
              minWidth: 360,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(alignment: Alignment.topRight, child: IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close))),
                  Text(_titles[widget.step - 1], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
                  const SizedBox(height: 14),
                  if (widget.step == 1) _step1Brand(),
                  if (widget.step == 2) _step2Image(),
                  if (widget.step == 3) _step3Prices(),
                  if (widget.step == 4) _buildStep4Demo(),
                  if (widget.step == 5) _buildStep5Demo(),
                  _audioControls(),
                  const SizedBox(height: 14),
                  _stepDots(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.step > 1) TextButton(onPressed: widget.onBack, child: const Text('Nyuma')),
                      const SizedBox(width: 8),
                      if (widget.step < 5) FilledButton(onPressed: widget.onNext, child: const Text('Endelea')),
                      if (widget.step == 5)
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: const Color(0xFF111827)),
                          onPressed: widget.onFinish,
                          child: const Text('Nimeelewa'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step1Brand() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x331E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, color: AppTheme.amber, size: 20),
          SizedBox(width: 8),
          Text('WASHA TV', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
        ],
      ),
    );
  }

  Widget _step2Image() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Image.asset('assets/images/tutorial_home.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _step3Prices() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x331E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chagua bei unayoweza kumudu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFE2E8F0))),
          const SizedBox(height: 10),
          ...List.generate(3, (i) {
            final active = _priceSelection == i;
            const labels = ['WEEK', 'MONTH', '3 MONTHS'];
            const prices = ['TSh 2,000', 'TSh 5,000', 'TSh 12,000'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _priceSelection = i);
                  _notifyHighlightedOptionChanged();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(width: active ? 1.8 : 1, color: active ? const Color(0xFF60A5FA) : const Color(0x26FFFFFF)),
                    gradient: active
                        ? const LinearGradient(colors: [Color(0x2A3B82F6), Color(0x1A6366F1)])
                        : const LinearGradient(colors: [Color(0x1A0F172A), Color(0x1A1E293B)]),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(labels[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? const Color(0xFFBFDBFE) : const Color(0xFFCBD5E1))),
                      ),
                      Text(prices[i], style: TextStyle(fontSize: active ? 15 : 14, fontWeight: FontWeight.w900, color: active ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0))),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _audioControls() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x66111B2C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.tonalIcon(
            onPressed: _safePlayStepAudio,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0x406366F1),
              foregroundColor: const Color(0xFFA5B4FC),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(_isPlaying ? Icons.graphic_eq_rounded : Icons.volume_up_rounded),
            label: const Text('Spika'),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: _safePlayStepAudio,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0x4038BDF8),
              foregroundColor: const Color(0xFFBAE6FD),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Sikiliza tena'),
          ),
        ],
      ),
    );
  }

  Widget _stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final active = i + 1 == widget.step;
        return Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: active ? AppTheme.indigo : const Color(0xFF374151),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text('${i + 1}')),
        );
      }),
    );
  }

  Widget _buildStep4Demo() {
    const phone = '07123456789';
    const userName = 'John Joel';
    final typedPhone = phone.substring(0, _phoneChars.clamp(0, phone.length));
    final typedName = userName.substring(0, _nameChars.clamp(0, userName.length));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x331E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ingiza taarifa zako', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFE2E8F0))),
          const SizedBox(height: 10),
          _demoInputBox(label: 'NAMBA YA SIMU', value: typedPhone, showCursor: _phoneChars < phone.length),
          const SizedBox(height: 8),
          _demoInputBox(label: 'JINA KAMILI', value: typedName, showCursor: _phoneChars >= phone.length && _nameChars < userName.length),
          const SizedBox(height: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            transform: Matrix4.identity()..scale(_payPressed ? 0.97 : 1.0),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF3B82F6)]),
            ),
            child: const Center(
              child: Text('LIPIA SASA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _demoInputBox({
    required String label,
    required String value,
    required bool showCursor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x66111B2C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(value.isEmpty ? '...' : value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: showCursor ? 1 : 0,
                child: const Text('|', style: TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Demo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x331E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        child: _step5Success ? _step5DoneView() : _step5PinView(),
      ),
    );
  }

  Widget _step5PinView() {
    return Column(
      key: const ValueKey('pin-state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Weka PIN kufanya malipo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFE2E8F0))),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(4, (i) {
            final active = i < _pinFilled;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 56,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: active ? const Color(0x1A3B82F6) : const Color(0x66111B2C),
                border: Border.all(color: active ? const Color(0xFF60A5FA) : const Color(0x26FFFFFF)),
              ),
              child: Center(
                child: Text(active ? '•' : '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF93C5FD))),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          transform: Matrix4.identity()..scale(_sendPressed ? 0.96 : 1),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF16A34A)]),
          ),
          child: const Center(
            child: Text('Send', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          ),
        ),
      ],
    );
  }

  Widget _step5DoneView() {
    return Column(
      key: const ValueKey('done-state'),
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF22C55E),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 10),
        const SizedBox(height: 8),
        const Text(
          'Malipo yamepokelewa sasa channel zote zimefunguliwa',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0)),
        ),
      ],
    );
  }
}
