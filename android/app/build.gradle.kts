plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.bellinghamfolks.docconverter"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.bellinghamfolks.docconverter"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        // Ship native libraries for arm64 only (every modern phone). The OCR
        // engines (ONNX + Tesseract) otherwise bundle .so for 4 CPU types,
        // roughly doubling the APK size and slowing the download.
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // On-device (offline) Arabic OCR: PaddleOCR (PP-OCRv5) models run on ONNX
    // Runtime. Models are downloaded at runtime.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.19.2")
}
