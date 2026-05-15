// Generated from android/app/google-services.json (Firebase project supasokatv-d238c).
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
    apiKey: 'AIzaSyA2TKmWfzwCBTVOkfjl8t3DTjobEnaHIFw',
    appId: '1:88812273490:android:fa7b080cc6c51d9743048b',
    messagingSenderId: '88812273490',
    projectId: 'supasokatv-d238c',
    storageBucket: 'supasokatv-d238c.firebasestorage.app',
  );
}
