import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _nameKey = 'washatvUserName';
  static const _subEndKey = 'washatvSubEnd';
  static const _deviceIdKey = 'washatvDeviceId';
  /// Written by admin Settings; read by the viewer app Profile WhatsApp row.
  static const supportWhatsappPrefsKey = 'washatvSupportWhatsapp';

  Future<String> getName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_nameKey) ?? '';
  }

  Future<void> setName(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_nameKey, value);
  }

  Future<DateTime?> getSubscriptionEnd() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_subEndKey);
    if (v == null) return null;
    return DateTime.tryParse(v);
  }

  Future<void> setSubscriptionEnd(DateTime? value) async {
    final p = await SharedPreferences.getInstance();
    if (value == null) {
      await p.remove(_subEndKey);
      return;
    }
    await p.setString(_subEndKey, value.toIso8601String());
  }

  Future<String> getOrCreateDeviceId() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_deviceIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = DateTime.now().microsecondsSinceEpoch;
    String next(int add) => chars[(r + add) % chars.length];
    final id = 'WTV-${next(1)}${next(2)}${next(3)}${next(4)}-'
        '${next(5)}${next(6)}${next(7)}${next(8)}';
    await p.setString(_deviceIdKey, id);
    return id;
  }

  /// Raw number as saved by admin (may include spaces/+). Empty if not configured.
  Future<String> getSupportWhatsapp() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(supportWhatsappPrefsKey) ?? '';
  }

  Future<void> setSupportWhatsapp(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(supportWhatsappPrefsKey, value);
  }
}
