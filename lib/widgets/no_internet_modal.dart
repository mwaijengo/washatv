import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class NoInternetModal extends StatefulWidget {
  const NoInternetModal({
    super.key,
    required this.onRetry,
    this.isRetrying = false,
  });

  final VoidCallback onRetry;
  final bool isRetrying;

  @override
  State<NoInternetModal> createState() => _NoInternetModalState();
}

class _NoInternetModalState extends State<NoInternetModal>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _slideCtrl;
  late final AnimationController _spinCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _spinAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _spinAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _spinCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(NoInternetModal old) {
    super.didUpdateWidget(old);
    if (widget.isRetrying && !old.isRetrying) {
      _spinCtrl.repeat();
    } else if (!widget.isRetrying && old.isRetrying) {
      _spinCtrl.stop();
      _spinCtrl.reset();
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: const Color(0xCC020408),
          child: Center(
            child: SlideTransition(
              position: _slideAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _Card(
                  pulseAnim: _pulseAnim,
                  spinAnim: _spinAnim,
                  isRetrying: widget.isRetrying,
                  onRetry: widget.onRetry,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.pulseAnim,
    required this.spinAnim,
    required this.isRetrying,
    required this.onRetry,
  });

  final Animation<double> pulseAnim;
  final Animation<double> spinAnim;
  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCC0D1426), Color(0xCC080E1C)],
            ),
            border: Border.all(color: const Color(0x28FFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 48,
                spreadRadius: -8,
                offset: Offset(0, 24),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconBadge(pulseAnim: pulseAnim, isRetrying: isRetrying, spinAnim: spinAnim),
              const SizedBox(height: 28),
              _buildTitle(),
              const SizedBox(height: 12),
              _buildSubtitle(),
              const SizedBox(height: 10),
              _buildHint(),
              const SizedBox(height: 32),
              _RetryButton(isRetrying: isRetrying, onRetry: onRetry),
              const SizedBox(height: 16),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const Text(
      'Hakuna Internet',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: -0.3,
        height: 1.2,
      ),
    );
  }

  Widget _buildSubtitle() {
    return const Text(
      'Hakikisha umewasha data\nna una MB katika kifaa chako.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: Color(0xFFCBD5E1),
        height: 1.55,
      ),
    );
  }

  Widget _buildHint() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF818CF8)),
          SizedBox(width: 7),
          Flexible(
            child: Text(
              'Ahsante kwa uvumilivu wako!',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: isRetrying ? AppTheme.amber : const Color(0xFF374151),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isRetrying ? 'Inatafuta muunganiko…' : 'Haijaunganishwa',
          style: TextStyle(
            fontSize: 11,
            color: isRetrying ? AppTheme.amber : const Color(0xFF4B5563),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.pulseAnim,
    required this.spinAnim,
    required this.isRetrying,
  });

  final Animation<double> pulseAnim;
  final Animation<double> spinAnim;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow ring
        ScaleTransition(
          scale: pulseAnim,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6366F1).withValues(alpha: 0.18),
                  const Color(0xFF6366F1).withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // Mid ring
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0F1629),
            border: Border.all(color: const Color(0x33FFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x446366F1),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        // Icon or spinner
        if (isRetrying)
          RotationTransition(
            turns: spinAnim,
            child: const Icon(
              Icons.sync_rounded,
              size: 36,
              color: AppTheme.indigo,
            ),
          )
        else
          const Icon(
            Icons.wifi_off_rounded,
            size: 38,
            color: Color(0xFF818CF8),
          ),
      ],
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.isRetrying, required this.onRetry});

  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: isRetrying
              ? const LinearGradient(
                  colors: [Color(0xFF374151), Color(0xFF374151)],
                )
              : const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                ),
          boxShadow: isRetrying
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x666366F1),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                    spreadRadius: -4,
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: isRetrying ? null : onRetry,
            borderRadius: BorderRadius.circular(22),
            splashColor: const Color(0x226366F1),
            child: Center(
              child: isRetrying
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9CA3AF)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Inaunganisha…',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9CA3AF),
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Jaribu Tena',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
