plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.bookfin.speech_probe"
    compileSdk = flutter.compileSdkVersion
    // The NDK of the dev shell (flake.nix).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.bookfin.speech_probe"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // arm64 only: the emulator and the Pixel 8 run it.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
        externalNativeBuild {
            cmake {
                abiFilters("arm64-v8a")
                // The pinned whisper.cpp source of nix develop .#speech.
                val source = System.getenv("BOOKFIN_WHISPER_SOURCE")
                    ?: error("Build in nix develop .#speech, which sets BOOKFIN_WHISPER_SOURCE.")
                arguments += listOf("-DWHISPER_SOURCE=$source", "-DCMAKE_BUILD_TYPE=Release")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // A throwaway probe: the debug key signs the release build.
            signingConfig = signingConfigs.getByName("debug")
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
