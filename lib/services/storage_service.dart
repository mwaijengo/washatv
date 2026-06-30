import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for viewer identity and subscription.
///
/// **Device ID** is created once and stored in SharedPreferences. It survives
/// normal app updates on Android/iOS/Web (same install / same site origin).
/// Do not rename [_deviceIdKey] — that would orphan existing users.
class StorageService {
  static const _nameKey = 'washatvUserName';
  static const _subEndKey = 'washatvSubEnd';
  static const _deviceIdKey = 'washatvDeviceId';
  static const _deviceIdBackupKey = 'washatvDeviceId_backup';

  /// Older builds — read once and migrate to [_deviceIdKey].
  static const _legacyDeviceIdKeys = <String>[
    'device_id',
    'washatv_device_id',
    'viewer_device_id',
  ];

  static final RegExp _deviceIdPattern = RegExp(r'^WTV-[A-Z0-9]{4}-[A-Z0-9]{4,32}$');

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

  /// Stable viewer id for API + premium. Never rotated after first save.
  Future<String> getOrCreateDeviceId() async {
    final p = await SharedPreferences.getInstance();

    final primary = _normalizeDeviceId(p.getString(_deviceIdKey));
    if (primary != null) {
      await _persistDeviceId(p, primary);
      return primary;
    }

    final backup = _normalizeDeviceId(p.getString(_deviceIdBackupKey));
    if (backup != null) {
      await _persistDeviceId(p, backup);
      return backup;
    }

    for (final legacyKey in _legacyDeviceIdKeys) {
      final legacy = _normalizeDeviceId(p.getString(legacyKey));
      if (legacy != null) {
        await _persistDeviceId(p, legacy);
        return legacy;
      }
    }

    final id = _generateDeviceId();
    await _persistDeviceId(p, id);
    if (kDebugMode) {
      debugPrint('WASHA: created new device id $id (first launch on this install)');
    }
    return id;
  }

  /// Re-read storage and repair primary/backup copies (e.g. after OS restore).
  Future<String> ensureDeviceIdPersisted() => getOrCreateDeviceId();

  Future<void> _persistDeviceId(SharedPreferences p, String id) async {
    await p.setString(_deviceIdKey, id);
    await p.setString(_deviceIdBackupKey, id);
    for (final legacyKey in _legacyDeviceIdKeys) {
      final existing = p.getString(legacyKey);
      if (existing != id) {
        await p.setString(legacyKey, id);
      }
    }
  }

  String? _normalizeDeviceId(String? raw) {
    if (raw == null) return null;
    final id = raw.trim().toUpperCase();
    if (id.isEmpty) return null;
    if (_deviceIdPattern.hasMatch(id)) return id;
    // Accept legacy ids from very old builds (alphanumeric + dashes).
    if (RegExp(r'^[A-Z0-9][A-Z0-9._-]{7,63}$').hasMatch(id)) return id;
    return null;
  }

  String _generateDeviceId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = Random.secure();
    String seg(int len) =>
        List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
    return 'WTV-${seg(4)}-${seg(8)}';
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

  static const _dataSaverKey = 'washatvOkoaBando';
  static const _pendingPayOrderKey = 'washatvPendingPayOrder';
  static const _pendingPayPhoneKey = 'washatvPendingPayPhone';
  static const _pendingPayNameKey = 'washatvPendingPayName';
  static const _pendingPayPlanKey = 'washatvPendingPayPlan';

  /// Okoa bando (data saver) — default ON (360p cap).
  Future<bool> getDataSaverEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_dataSaverKey) ?? true;
  }

  Future<void> setDataSaverEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_dataSaverKey, value);
  }

  Future<void> savePendingPayment({
    required String orderId,
    required String phone,
    required String name,
    required String planKey,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_pendingPayOrderKey, orderId);
    await p.setString(_pendingPayPhoneKey, phone);
    await p.setString(_pendingPayNameKey, name);
    await p.setString(_pendingPayPlanKey, planKey);
  }

  Future<({String orderId, String phone, String name, String planKey})?> loadPendingPayment() async {
    final p = await SharedPreferences.getInstance();
    final orderId = p.getString(_pendingPayOrderKey)?.trim() ?? '';
    if (orderId.isEmpty) return null;
    return (
      orderId: orderId,
      phone: p.getString(_pendingPayPhoneKey)?.trim() ?? '',
      name: p.getString(_pendingPayNameKey)?.trim() ?? '',
      planKey: p.getString(_pendingPayPlanKey)?.trim() ?? '',
    );
  }

  Future<void> clearPendingPayment() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pendingPayOrderKey);
    await p.remove(_pendingPayPhoneKey);
    await p.remove(_pendingPayNameKey);
    await p.remove(_pendingPayPlanKey);
  }
}
