// Bookfin's host channels as a Flutter plugin. Flutter's generated plugin
// registrant adds BookfinHostPlugin to every engine that it makes, so an
// engine that the audio service starts before any Activity has the channels
// too (t0-wedg). The OCR channel loads libbookfin_ocr.so, which the app
// builds (native/CMakeLists.txt), so this library needs no OCR dependency.
group = "dev.bookfin.host"
version = "1.0"

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "dev.bookfin.host"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin", "src/main/java")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
