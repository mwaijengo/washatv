import 'package:washa/models/remote_player_config.dart';
import 'package:washa/services/remote_config_service.dart';

/// Player policy — uses Washa remote config (same role as Supasoka defaults).
class PlayerConfigService {
  PlayerConfigService._();

  static RemotePlayerConfig get playerConfig => RemoteConfigService.playerConfig;

  static Future<void> syncFromServer() async {}
}
