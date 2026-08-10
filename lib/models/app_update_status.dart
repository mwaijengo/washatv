class AppUpdateStatus {
  const AppUpdateStatus({
    required this.updateRequired,
    required this.forceUpdateEnabled,
    required this.minVersion,
    required this.latestVersion,
    required this.minBuild,
    required this.latestBuild,
    required this.playStoreUrl,
    required this.updateTitle,
    required this.updateMessage,
    this.currentVersion = '',
    this.currentBuild = 0,
  });

  final bool updateRequired;
  final bool forceUpdateEnabled;
  final String minVersion;
  final String latestVersion;
  final int minBuild;
  final int latestBuild;
  final String playStoreUrl;
  final String updateTitle;
  final String updateMessage;
  final String currentVersion;
  final int currentBuild;

  static const empty = AppUpdateStatus(
    updateRequired: false,
    forceUpdateEnabled: false,
    minVersion: '',
    latestVersion: '',
    minBuild: 0,
    latestBuild: 0,
    playStoreUrl: 'https://play.google.com/store/apps/details?id=com.washatv',
    updateTitle: 'Sasisha WASHA TV',
    updateMessage:
        'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.',
  );

  AppUpdateStatus copyWith({
    bool? updateRequired,
    String? currentVersion,
    int? currentBuild,
  }) {
    return AppUpdateStatus(
      updateRequired: updateRequired ?? this.updateRequired,
      forceUpdateEnabled: forceUpdateEnabled,
      minVersion: minVersion,
      latestVersion: latestVersion,
      minBuild: minBuild,
      latestBuild: latestBuild,
      playStoreUrl: playStoreUrl,
      updateTitle: updateTitle,
      updateMessage: updateMessage,
      currentVersion: currentVersion ?? this.currentVersion,
      currentBuild: currentBuild ?? this.currentBuild,
    );
  }

  factory AppUpdateStatus.fromJson(
    Map<String, dynamic>? raw, {
    String currentVersion = '',
    int currentBuild = 0,
  }) {
    if (raw == null) {
      return empty.copyWith(currentVersion: currentVersion, currentBuild: currentBuild);
    }
    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }

    String asStr(Object? v, [String fallback = '']) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? fallback : s;
    }

    return AppUpdateStatus(
      updateRequired: raw['updateRequired'] == true || raw['update_required'] == true,
      forceUpdateEnabled:
          raw['forceUpdateEnabled'] == true || raw['force_update_enabled'] == true,
      minVersion: asStr(raw['minVersion'] ?? raw['min_version']),
      latestVersion: asStr(raw['latestVersion'] ?? raw['latest_version']),
      minBuild: asInt(raw['minBuild'] ?? raw['min_build']),
      latestBuild: asInt(raw['latestBuild'] ?? raw['latest_build']),
      playStoreUrl: asStr(
        raw['playStoreUrl'] ?? raw['play_store_url'],
        'https://play.google.com/store/apps/details?id=com.washatv',
      ),
      updateTitle: asStr(raw['updateTitle'] ?? raw['update_title'], 'Sasisha WASHA TV'),
      updateMessage: asStr(
        raw['updateMessage'] ?? raw['update_message'],
        'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.',
      ),
      currentVersion: currentVersion,
      currentBuild: currentBuild,
    );
  }

  Map<String, dynamic> toJson() => {
        'updateRequired': updateRequired,
        'forceUpdateEnabled': forceUpdateEnabled,
        'minVersion': minVersion,
        'latestVersion': latestVersion,
        'minBuild': minBuild,
        'latestBuild': latestBuild,
        'playStoreUrl': playStoreUrl,
        'updateTitle': updateTitle,
        'updateMessage': updateMessage,
      };
}
