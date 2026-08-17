# Nenjam Matrimony — R8 / ProGuard keep rules for the release build.
#
# The Flutter Gradle plugin already contributes the engine's own rules
# (io.flutter.**, the embedding, plugin registrant). Everything below covers
# what R8 cannot see from bytecode alone: classes reached only by reflection,
# by JNI, or by a native framework at runtime.

# --- Firebase (Auth, Core, Messaging) ---------------------------------------
# FirebaseMessagingService and friends are instantiated by the Android
# framework from the manifest, and Firebase models are populated reflectively
# from JSON, so their members must survive renaming.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Play Core / deferred components ----------------------------------------
# Flutter's embedding references SplitCompat even when the app ships no
# dynamic feature modules; without this R8 fails on the missing symbols.
-dontwarn com.google.android.play.core.**

# --- Core library desugaring ------------------------------------------------
# flutter_local_notifications requires desugared java.time APIs (see
# isCoreLibraryDesugaringEnabled in build.gradle.kts).
-dontwarn java.lang.invoke.**
-dontwarn build.IgnoreJava8API

# --- Kotlin metadata --------------------------------------------------------
-keepattributes *Annotation*, InnerClasses, Signature, RuntimeVisible*Annotations

# Keep crash-report line numbers meaningful while still obfuscating names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
