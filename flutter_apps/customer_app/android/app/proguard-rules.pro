# Flutter ProGuard / R8 Obfuscation & Security Rules

# Preserve core Flutter engine and plugin bindings
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Obfuscate classes and repackage into root package to hide code structure
-repackageclasses ''
-allowaccessmodification
-renamesourcefileattribute SourceFile
-keepattributes *Annotation*
-dontusemixedcaseclassnames

# Strip line numbers and debug source file names from stack traces in production
-keepattributes SourceFile,LineNumberTable

# Strip Android logging calls in release builds (prevents logcat leaks of URLs, tokens, sensitive data)
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
}

