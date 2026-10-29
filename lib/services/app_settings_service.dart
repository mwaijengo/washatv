import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user_settings.dart';
import 'storage_service.dart';

/// Local viewer preferences — player, layout, quality.
class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();
  static final AppSettingsService instance = AppSettingsService._();

  static const _qualityKey = 'washatvUserVideoQuality';
  static const _playerKey = 'washatvUserPlayerType';
  static const _zoomKey = 'washatvUserVideoZoom';
  static const _layoutKey = 'washatvChannelDisplay';

  final _storage = StorageService();
  AppUserSettings _settings = AppUserSettings.defaults;
  bool _loaded = false;

  AppUserSettings get settings => _settings;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final dataSaver = await _storage.getDataSaverEnabled();
    _settings = AppUserSettings(
      videoQuality: VideoQualityPreference.fromStored(p.getString(_qualityKey)),
      playerType: PlayerTypePreference.fromStored(p.getString(_playerKey)),
      videoZoom: VideoZoomPreference.fromStored(p.getString(_zoomKey)),
      channelDisplay: ChannelDisplayStyle.fromStored(p.getString(_layoutKey)),
      dataSaver: dataSaver,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(AppUserSettings next) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_qualityKey, next.videoQuality.name);
    await p.setString(_playerKey, next.playerType.name);
    await p.setString(_zoomKey, next.videoZoom.name);
    await p.setString(_layoutKey, next.channelDisplay.name);
    await _storage.setDataSaverEnabled(next.dataSaver);
    _settings = next;
    notifyListeners();
  }

  Future<void> update({
    VideoQualityPreference? videoQuality,
    PlayerTypePreference? playerType,
    VideoZoomPreference? videoZoom,
    ChannelDisplayStyle? channelDisplay,
    bool? dataSaver,
  }) async {
    await save(
      _settings.copyWith(
        videoQuality: videoQuality,
        playerType: playerType,
        videoZoom: videoZoom,
        channelDisplay: channelDisplay,
        dataSaver: dataSaver,
      ),
    );
  }

  String resolvePlaybackQuality({required String serverDefault}) {
    if (_settings.dataSaver) return '360p';
    if (_settings.videoQuality == VideoQualityPreference.auto) {
      final s = serverDefault.trim();
      return s.isEmpty ? 'AUTO' : s;
    }
    return _settings.videoQuality.apiValue;
  }

  String? resolvePlayerEngineOverride() {
    if (_settings.playerType == PlayerTypePreference.auto) return null;
    return _settings.playerType.engineValue;
  }
}
