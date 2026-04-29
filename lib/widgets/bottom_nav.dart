import 'dart:ui';

import 'package:flutter/material.dart';

import '../app.dart';
import '../theme/app_theme.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.current,
    required this.onTap,
  });

  final AppScreen current;
  final ValueChanged<AppScreen> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: AppTheme.glass(
              radius: BorderRadius.circular(26),
              color: AppTheme.navPanel,
              border: Border.all(color: AppTheme.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _item(Icons.home, 'Nyumbani', AppScreen.home),
                _item(Icons.satellite_alt, 'Aina', AppScreen.categories),
                _item(Icons.workspace_premium, 'Fungua zote', AppScreen.subscription),
                _item(Icons.account_circle, 'Mtumiaji', AppScreen.profile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, String text, AppScreen s) {
    final active = current == s;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: active ? const LinearGradient(colors: [AppTheme.indigo, AppTheme.purple]) : null,
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x996366F1),
                      blurRadius: 30,
                      offset: Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: active ? const Color(0xFFC7D2FE) : const Color(0xFF6B7280)),
              Text(text, style: TextStyle(fontSize: 10, color: active ? const Color(0xFFC7D2FE) : const Color(0xFF6B7280))),
            ],
          ),
        ),
      ),
    );
  }
}
