plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uk.laurencegouws.howl_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "uk.laurencegouws.howl_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    packaging {
        // Flutter native-assets plugins may contribute prebuilt helper libraries for
        // every Android ABI even when the app itself is arm64-only. Keep the accepted
        // Howl artifact shape exact: retain the arm64 helper and refuse packaging of
        // the three non-arm64 DataStore slices.
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/libdatastore_shared_counter.so",
                "lib/x86/libdatastore_shared_counter.so",
                "lib/x86_64/libdatastore_shared_counter.so",
            )
        }
    }

    buildTypes {
        release {
            // Experimental local client: keep release installs reproducible without a private keystore.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("../../native/android")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

val howlNativeHost = file("../../native/android/arm64-v8a/libhowl_native_host.so")

tasks.register("verifyHowlNativeHost") {
    doLast {
        check(howlNativeHost.isFile) {
            "missing native Howl host; run howl-flutter/native/build-android.sh first"
        }
        val targets = providers.gradleProperty("target-platform").orNull
        check(targets == "android-arm64") {
            "Howl native host currently supports Android arm64 only; use howl-flutter/build-android.sh or --target-platform android-arm64"
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn("verifyHowlNativeHost")
}
