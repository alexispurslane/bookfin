import java.io.File
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val ocrAar = file(requireNotNull(System.getenv("BOOKFIN_OCR_ANDROID_AAR")) {
    "Build through the pinned project Nix shell."
})
fun verifyOcrFile(file: File, expected: String) {
    val actual = MessageDigest.getInstance("SHA-256")
        .digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    require(actual == expected) { "Pinned OCR dependency verification failed: $file" }
}
verifyOcrFile(ocrAar, "bce5d6413a1a5ae3d7240033fbbc851ba3217d0a08d9769400e17a077f42cb2a")
val verifyBundledOcr by tasks.registering {
    doLast {
        verifyOcrFile(file("../../.cache/ocr/bundle/bookfin-ocr/eng.traineddata"),
            "7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2")
    }
}
tasks.named("preBuild") { dependsOn(verifyBundledOcr) }
// The speech model that the APK bundles (tool/reader/speech_package.py).
val verifyBundledSpeech by tasks.registering {
    doLast {
        verifyOcrFile(file("../../.cache/speech/bundle/bookfin-speech/tiny.en-q5_1.ggml"),
            "c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b")
    }
}
tasks.named("preBuild") { dependsOn(verifyBundledSpeech) }

android {
    namespace = "dev.bookfin.bookfin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.bookfin.bookfin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val requestedPlatforms = providers.gradleProperty("target-platform").orNull
        if (requestedPlatforms != null && providers.gradleProperty("split-per-abi").orNull != "true") {
            ndk {
                abiFilters.clear()
                abiFilters += requestedPlatforms.split(",").map { platform ->
                    when (platform) {
                        "android-arm" -> "armeabi-v7a"
                        "android-arm64" -> "arm64-v8a"
                        "android-x64" -> "x86_64"
                        else -> error("Unsupported Flutter Android target: $platform")
                    }
                }
            }
        }
        externalNativeBuild {
            cmake {
                targets += listOf("bookfin_mobi", "bookfin_ocr", "bookfin_speech")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets["main"].assets.srcDir("../../.cache/ocr/bundle")
    sourceSets["main"].assets.srcDir("../../.cache/speech/bundle")
    // The speech library reads its model in place from the APK, so the
    // model stays uncompressed.
    androidResources { noCompress += listOf("traineddata", "ggml") }
    packaging.jniLibs.keepDebugSymbols += setOf("**/libtesseract.so", "**/libleptonica.so", "**/libpngx.so", "**/libjpeg.so")

}

dependencies { implementation(files(ocrAar)) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
