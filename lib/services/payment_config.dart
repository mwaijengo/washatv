/// Tanzania mobile-money checkout rules (local phone format, dev vs production API).
class PaymentConfig {
  PaymentConfig._();

  /// `07XXXXXXXX` — 10 digits, must start with 0 (no +255 in the form).
  static final RegExp tzLocalPhone = RegExp(r'^0\d{9}$');

  static bool isValidTzLocalPhone(String raw) => tzLocalPhone.hasMatch(raw.trim());

  /// At least two name parts (jina kamili).
  static bool isValidFullName(String raw) {
    final t = raw.trim();
    if (t.length < 4) return false;
    return RegExp(r'\s+').hasMatch(t);
  }

  static bool isLocalApiHost(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '10.0.2.2' ||
        host.endsWith('.local');
  }

  static const mobileMoneyNetworks = <String>[
    'M-Pesa',
    'Mixx by Yas',
    'Airtel Money',
    'Halotel',
  ];

  static const paymentPromptSw =
      'Angalia simu yako — thibitisha PIN (M-Pesa, Mixx by Yas, Airtel Money, Halotel).';
}
