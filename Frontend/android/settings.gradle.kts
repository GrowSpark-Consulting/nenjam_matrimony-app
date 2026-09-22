pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Face Liveness (docs/development/selfie-verification-frontend-handoff.md
    // §2/§3): Amplify's FaceLivenessDetector is a Jetpack Compose composable.
    // With Kotlin 2.x this plugin replaces the old
    // composeOptions { kotlinCompilerExtensionVersion } block — don't add
    // that block back.
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.20" apply false
}

include(":app")
