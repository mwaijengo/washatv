import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_auth.dart';
import 'admin_colors.dart';

/// Supasoka-style gate: email + password once; JWT stays on device until logout.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, required this.auth, required this.onLoggedIn});

  final AdminAuth auth;
  final VoidCallback onLoggedIn;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  late final TextEditingController _email;
  late final TextEditingController _password;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.auth.savedEmail);
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await widget.auth.login(
      email: _email.text,
      password: _password.text,
    );
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.admin_panel_settings_rounded, size: 72, color: AdminColors.accentPrimary),
                const SizedBox(height: 20),
                Text(
                  'WASHA Admin',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AdminColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Barua pepe',
                    hintText: 'admin@…',
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                    filled: true,
                    fillColor: AdminColors.bgTertiary,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Neno la siri',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    ),
                    filled: true,
                    fillColor: AdminColors.bgTertiary,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Color(0xFFF87171), fontSize: 13), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: AdminColors.accentPrimary),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ingia'),
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
