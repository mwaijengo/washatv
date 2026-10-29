# Strip all android.util.Log calls from release builds (stream URLs and headers were logged).
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
    public static boolean isLoggable(java.lang.String, int);
}

# WebView JavaScript bridge methods are looked up by name from page scripts.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface

# Flutter deferred components reference Play Core classes that this app does not ship.
-dontwarn com.google.android.play.core.**

-repackageclasses ''
-allowaccessmodification
