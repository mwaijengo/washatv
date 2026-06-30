import '../models/remote_player_config.dart';

/// Minimal stub — Washa uses local defaults until server player config is wired.
class RemoteConfigService {
  RemoteConfigService._();

  static RemotePlayerConfig playerConfig = RemotePlayerConfig.defaults;
}
