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

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val ciKeystorePath = System.getenv("CM_KEYSTORE_PATH")
val hasCiReleaseKeystore = !ciKeystorePath.isNullOrBlank()

if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

android {
    namespace = "com.ahmed.buildozer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("profile") {
            kotlin.srcDirs("src/debug/kotlin")
        }
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.ahmed.buildozer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCiReleaseKeystore || hasReleaseKeystore) {
            create("release") {
                if (hasCiReleaseKeystore) {
                    storeFile = file(ciKeystorePath)
                    storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                    keyAlias = System.getenv("CM_KEY_ALIAS")
                    keyPassword = System.getenv("CM_KEY_PASSWORD")
                } else {
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                    storePassword = keystoreProperties["storePassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            // Use a real upload keystore when available, otherwise keep local release
            // builds working with the debug key.
            signingConfig = if (hasCiReleaseKeystore || hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    debugImplementation("com.google.firebase:firebase-appcheck-debug")
    profileImplementation("com.google.firebase:firebase-appcheck-debug")
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
}
