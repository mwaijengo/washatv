import 'package:flutter/painting.dart';

import 'public_api_service.dart';

/// Clears on-disk bootstrap cache and in-memory image cache.
class AppCacheService {
  AppCacheService._();

  static final AppCacheService instance = AppCacheService._();

  Future<void> clearAll({PublicApiService? api}) async {
    await clearBootstrap(api: api);
    clearImageMemory();
  }

  Future<void> clearBootstrap({PublicApiService? api}) async {
    final service = api ?? PublicApiService();
    await service.clearBootstrapCache();
  }

  void clearImageMemory() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}
