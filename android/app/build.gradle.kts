import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// All four must be set and store file must exist, or we fall back to debug signing
// (wrong cert for Play if you upload that bundle).
val hasValidReleaseKeystore: Boolean
    get() {
        if (!keystorePropertiesFile.exists()) return false
        val alias = keystoreProperties.getProperty("keyAlias")?.trim() ?: return false
        val keyPassword = keystoreProperties.getProperty("keyPassword")?.trim() ?: return false
        val storePassword = keystoreProperties.getProperty("storePassword")?.trim() ?: return false
        val store = keystoreProperties.getProperty("storeFile")?.trim() ?: return false
        if (alias.isEmpty() || keyPassword.isEmpty() || storePassword.isEmpty() || store.isEmpty()) {
            return false
        }
        return rootProject.file(store).isFile
    }

android {
    namespace = "com.lastcards.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasValidReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")?.trim()!!
                keyPassword = keystoreProperties.getProperty("keyPassword")?.trim()!!
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile")!!.trim())
                storePassword = keystoreProperties.getProperty("storePassword")?.trim()!!
            }
        }
    }

    defaultConfig {
        applicationId = "com.lastcards.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasValidReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Never ship an AAB to Play that was signed with the debug key: require upload keystore
// (android/key.properties + .p12) for bundleRelease.
afterEvaluate {
    tasks.findByName("bundleRelease")?.doFirst {
        if (!hasValidReleaseKeystore) {
            throw GradleException(
                "Play upload: android/key.properties must exist with keyAlias, keyPassword, " +
                    "storePassword, storeFile, and the keystore file must be present. " +
                    "Without that, the release app bundle is signed with the debug key and " +
                    "Google Play will reject it (upload certificate SHA-1 mismatch). " +
                    "Copy android/key.properties and android/upload-keystore.p12 from your secure backup, " +
                    "or inject them in CI from secrets, then run: flutter build appbundle --release",
            )
        }
    }
}

flutter {
    source = "../.."
}
