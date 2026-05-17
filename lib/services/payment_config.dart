/// Tanzania mobile-money checkout rules (local phone format, dev vs production API).
class PaymentConfig {
  PaymentConfig._();

  /// Local `0XXXXXXXXX` after [normalizeTzLocalPhone] (M-Pesa, Mixx, Airtel, Halotel).
  static final RegExp tzLocalPhone = RegExp(r'^0[67]\d{8}$');

  /// Halotel + other TZ mobile prefixes (national format, with leading 0).
  static const halotelPrefixes = <String>['061', '062', '063', '069'];

  /// `07…` / `06…` (10 digits), or `7…` / `6…` (9 digits), or `255…` / `+255…`.
  static String? normalizeTzLocalPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('255') && digits.length >= 12) {
      digits = digits.substring(3, 12);
    }

    if (digits.startsWith('0') && digits.length >= 10) {
      digits = digits.substring(0, 10);
    } else if (digits.length == 9 && RegExp(r'^[67]').hasMatch(digits)) {
      digits = '0$digits';
    }

    if (!tzLocalPhone.hasMatch(digits)) return null;
    return digits;
  }

  static bool isValidTzLocalPhone(String raw) => normalizeTzLocalPhone(raw) != null;

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
