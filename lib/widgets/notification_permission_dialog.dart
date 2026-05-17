import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';

/// Same flow as Supasoka — ask once until OS notification permission is granted.
Future<void> maybeShowWashaNotificationPermissionDialog(
  BuildContext context, {
  String? deviceId,
  bool isPremium = false,
}) async {
  final shouldAsk = await PushNotificationService.shouldShowPermissionPrompt();
  if (!shouldAsk || !context.mounted) return;

  final granted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0E172A), Color(0xFF0A1120)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: Color(0xFF22C55E), size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Pokea taarifa za Washa TV',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Taarifa kutoka admin zitafika hata ukikaa wiki bila kufungua programu — hakikisha “Ruhusu” na usizime arifa za Washa TV kwenye mipangilio ya simu.',
              style: TextStyle(color: Color(0xFFD1D5DB), height: 1.45, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await PushNotificationService.markPermissionPromptSeen();
                      if (ctx.mounted) Navigator.pop(ctx, false);
                    },
                    child: const Text('Baadaye'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF22C55E)),
                    child: const Text('Washa'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (granted == true) {
    await PushNotificationService.requestPermissionFromPrompt(
      deviceId: deviceId,
      isPremium: isPremium,
    );
  }
}
