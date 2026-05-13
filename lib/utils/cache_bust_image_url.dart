/// Busts HTTP/CDN caches when the API [configVersion] bumps but the image URL string is unchanged.
String imageUrlWithCacheEpoch(String imageUrl, int configVersion) {
  if (configVersion <= 0 || imageUrl.trim().isEmpty) return imageUrl;
  try {
    final u = Uri.parse(imageUrl.trim());
    final q = Map<String, String>.from(u.queryParameters);
    q['washa_cv'] = '$configVersion';
    return u.replace(queryParameters: q).toString();
  } catch (_) {
    final sep = imageUrl.contains('?') ? '&' : '?';
    return '$imageUrl${sep}washa_cv=$configVersion';
  }
}
