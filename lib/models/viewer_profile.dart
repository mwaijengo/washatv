/// Viewer account state from `GET /api/v1/public/user-profile/:device_id`.
class ViewerProfile {
  const ViewerProfile({
    required this.name,
    required this.phone,
    required this.premiumActive,
    this.premiumUntil,
    this.adminAccessUntil,
    this.planKey,
    this.planName,
    required this.accessSource,
  });

  final String name;
  final String phone;
  final bool premiumActive;
  final DateTime? premiumUntil;
  /// Admin-granted expiry (when set and active).
  final DateTime? adminAccessUntil;
  final String? planKey;
  final String? planName;

  /// `admin` | `payment` | `legacy` | `none`
  final String accessSource;

  bool get isAdminGrant => accessSource == 'admin';

  String get displayName {
    final n = name.trim();
    if (n.isEmpty || isGenericViewerName(n)) return 'Mtumiaji';
    return n;
  }
}

bool isGenericViewerName(String name) {
  final n = name.trim().toLowerCase();
  return n.isEmpty || n == 'free user' || n == 'viewer' || n == 'freeuser';
}
