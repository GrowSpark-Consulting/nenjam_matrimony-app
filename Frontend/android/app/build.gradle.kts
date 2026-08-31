import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material, kept OUT of version control: android/key.properties
// holds the passwords and a path to the keystore, and .gitignore already
// excludes it along with *.jks/*.keystore. See key.properties.example for the
// expected shape, and README/docs for generating the keystore.
//
// Absence is tolerated at configuration time so `flutter run`, `flutter test`
// and debug/profile builds keep working on a machine that has no signing
// material. A *release* build without it fails loudly instead — see the
// verification task at the bottom of this file.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

android {
    namespace = "com.growspark.nenjam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (v10+) — it uses Java 8+
        // APIs that need to be desugared to run on older Android API levels.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.growspark.nenjam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Registered only when key.properties is present. Declaring it
        // unconditionally would make every debug build fail at configuration
        // time on a machine with no keystore.
        if (hasReleaseKeystore) {
            create("release") {
                // trim() is load-bearing, not tidiness. java.util.Properties
                // strips LEADING whitespace from a value but keeps TRAILING
                // whitespace, so one stray space after a password in
                // key.properties is read as part of the password. The result is
                // a six-minute build that dies at :app:packageRelease with
                // "keystore password was incorrect" — an error that points at
                // the keystore rather than the invisible space that caused it.
                keyAlias = keystoreProperties.getProperty("keyAlias")?.trim()
                keyPassword = keystoreProperties.getProperty("keyPassword")?.trim()
                storeFile = keystoreProperties.getProperty("storeFile")?.trim()?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")?.trim()
            }
        }
    }

    buildTypes {
        release {
            // Real release signing — never the debug keystore. A debug-signed
            // artifact is rejected by Play, and shipping one would mean every
            // install shares the publicly-known Android debug key.
            //
            // Null when no keystore is configured, which yields an *unsigned*
            // artifact rather than a silently debug-signed one; the
            // requireReleaseKeystore task below turns that into a hard error.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                null
            }

            // R8: strip unused code and resources from the shipped artifact.
            // Both are required for a reasonable APK/AAB size; `shrinkResources`
            // is only legal alongside `minifyEnabled`.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Kotlin 2.2 deprecates the `android.kotlinOptions {}` DSL in favour of the
// `kotlin.compilerOptions {}` extension; using the old block emits a
// deprecation warning on every build.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// Turns "no signing material" into an actionable failure at the moment a
// release artifact is actually assembled — deliberately not at configuration
// time, which would break debug builds and IDE sync for everyone without a
// keystore. Without this, `flutter build appbundle --release` would quietly
// emit an unsigned AAB that only fails much later, at Play upload.
tasks.matching {
    (it.name.startsWith("assemble") || it.name.startsWith("bundle")) &&
        it.name.contains("Release")
}.configureEach {
    doFirst {
        if (!hasReleaseKeystore) {
            throw GradleException(
                """
                Release signing is not configured.

                Create android/key.properties (see android/key.properties.example):
                    storePassword=<password>
                    keyPassword=<password>
                    keyAlias=upload
                    storeFile=<absolute path to upload-keystore.jks>

                Generate the keystore with:
                    keytool -genkey -v -keystore upload-keystore.jks \
                      -keyalg RSA -keysize 2048 -validity 10000 -alias upload

                key.properties and *.jks are gitignored — never commit them.
                """.trimIndent(),
            )
        }

        // Catch an incomplete key.properties here rather than ~6 minutes later
        // inside :app:packageRelease, where a null password surfaces as the
        // same misleading "keystore password was incorrect".
        val missing = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")
            .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "android/key.properties is missing or blank for: " +
                    missing.joinToString(", ") +
                    "\nSee android/key.properties.example for the expected shape.",
            )
        }

        val resolvedStore = file(keystoreProperties.getProperty("storeFile").trim())
        if (!resolvedStore.exists()) {
            throw GradleException(
                "Keystore not found at: $resolvedStore\n" +
                    "storeFile in android/key.properties is resolved relative to " +
                    "android/app/ — use an absolute path if that is not what you meant.",
            )
        }
    }
}

dependencies {
    // Required by flutter_local_notifications' core library desugaring
    // requirement (see compileOptions above).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
