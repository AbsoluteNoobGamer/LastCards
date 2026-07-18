# Flutter / plugin keep rules (see flutter_tools gradle flutter_proguard_rules.pro).
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

-if class * implements io.flutter.embedding.engine.plugins.FlutterPlugin
-keep,allowshrinking,allowobfuscation class <1>

-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.plugin.**
-dontwarn android.**

# Google Play / Firebase / Ads — reflection-heavy SDKs.
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.firebase.**

# Keep native methods for plugins that use JNI.
-keepclasseswithmembernames class * {
    native <methods>;
}
