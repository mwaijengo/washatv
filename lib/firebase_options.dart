// Generated from android/app/google-services.json (Firebase project supasoka-18128).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Washa FCM is not configured for web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'Add GoogleService-Info.plist from Firebase for ${defaultTargetPlatform.name}.',
        );
      default:
        throw UnsupportedError('Washa FCM is only configured for Android and iOS.');
    }
  }

  /// `com.washatv` — must match [android/app/build.gradle.kts] applicationId.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCJmMsez-AInf54lyXpVHkbvF9iKX2B-vg',
    appId: '1:904780930630:android:aabdfad37fe224783bf447',
    messagingSenderId: '904780930630',
    projectId: 'supasoka-18128',
    storageBucket: 'supasoka-18128.firebasestorage.app',
  );
}
