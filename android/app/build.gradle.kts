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
    // On-device (offline) OCR engine for the fast local reader mode. Arabic
    // isn't supported by ML Kit, so we use Tesseract (ara+eng) on the device.
    implementation("cz.adaptech.tesseract4android:tesseract4android:4.9.0")
}
