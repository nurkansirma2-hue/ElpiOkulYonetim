plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val testApk = System.getenv("OKUL_TEST_APK") == "true"

android {
    namespace = "com.example.elpi_okul_yonetim"
    compileSdk = flutter.compileSdkVersion
    // Match the Android CI toolchain and use an NDK with 16 KiB page support.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.elpi_okul_yonetim"
        if (testApk) {
            applicationIdSuffix = ".test"
        }
        manifestPlaceholders["okulAppLabel"] =
            if (testApk) "Okul Yönetim Test" else "elpi_okul_yonetim"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Dar dosya izniyle Google Picker; mevcut Google giriş API'leri korunur.
    implementation("com.google.android.gms:play-services-auth:21.5.1")
    // Model APK içinde: öğrenci formu görüntüleri cihazdan gönderilmez.
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
