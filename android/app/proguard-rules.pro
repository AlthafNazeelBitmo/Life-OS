# R8 rules for LifeOS.
#
# Most plugins ship consumer rules, so this file only covers the cases R8
# cannot infer: reflection-based entry points and optional dependencies that
# are referenced but never bundled.

# --- Flutter engine ----------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- flutter_local_notifications --------------------------------------------
# Scheduled notifications are restored by deserialising this model after a
# reboot, so its fields must survive obfuscation.
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# --- Play Core -----------------------------------------------------------
# Referenced by the Flutter engine's deferred-components path, which this app
# does not use. Without this, R8 fails on missing classes.
-dontwarn com.google.android.play.core.**

# --- Firebase (optional at runtime) -----------------------------------------
# LifeOS treats a missing Firebase config as normal, so these must not fail the
# build when the classes are absent.
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }

# --- Kotlin / coroutines / serialization (Supabase) --------------------------
-keepattributes *Annotation*, InnerClasses, Signature, Exceptions
-dontwarn kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }

# --- OkHttp / Conscrypt ------------------------------------------------------
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

# --- Keep enum values used by name -------------------------------------------
# Drift stores enums as text via textEnum(), which resolves them by name.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
