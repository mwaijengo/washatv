import 'package:flutter/material.dart';

import 'admin_auth.dart';
import 'admin_colors.dart';
import 'admin_ui.dart';

/// Password-only gate. The session stays valid for 24 hours, then the password is asked again.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({
    super.key,
    required this.auth,
    required this.onLoggedIn,
    this.notice,
  });

  final AdminAuth auth;
  final VoidCallback onLoggedIn;

  /// Shown above the field, e.g. when the previous 24-hour session ran out.
  final String? notice;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  late final TextEditingController _password;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await widget.auth.login(password: _password.text);
    if (!mounted) return;
    if (err == null) {
      widget.onLoggedIn();
      return;
    }
    setState(() {
      _error = err;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.bgPrimary,
      body: Stack(
        children: [
          const Positioned.fill(child: AdminAmbientBackground()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FadeSlideIn(
                  offset: 24,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    decoration: adminCardDecoration(radius: 26),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: adminBrandGradient,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x666366F1),
                                blurRadius: 32,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => const LinearGradient(
                            colors: [Color(0xFF818CF8), Color(0xFFA78BFA)],
                          ).createShader(r),
                          child: const Text(
                            'Waisa',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${adminGreeting()} · Weka neno la siri ili kuingia',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                        if (widget.notice != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x22F59E0B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x44F59E0B),
                              ),
                            ),
                            child: Text(
                              widget.notice!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          autofocus: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Neno la siri',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Onyesha' : 'Ficha',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                            ),
                            filled: true,
                            fillColor: AdminColors.bgPrimary,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0x1AFFFFFF),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: AdminColors.accentPrimary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 22),
                        AdminPressable(
                          onTap: _loading ? null : _submit,
                          lift: 2,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: adminBrandGradient,
                              boxShadow: _loading
                                  ? null
                                  : const [
                                      BoxShadow(
                                        color: Color(0x596366F1),
                                        blurRadius: 20,
                                        offset: Offset(0, 8),
                                      ),
                                    ],
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Ingia',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_clock_rounded,
                              size: 14,
                              color: AdminColors.textSecondary,
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Login inadumu saa 24, kisha utaombwa neno la siri tena.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AdminColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}
