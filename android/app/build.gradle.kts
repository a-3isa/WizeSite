import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
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

// versionCode auto-derived from commit count: every commit gets a new, strictly
// increasing value with zero manual bumping, so a fresh AAB/APK is always
// uploadable to Play without editing pubspec.yaml by hand. Falls back to 1 if
// git isn't available (e.g. a source archive with no .git directory).
val autoVersionCode: Int = try {
    val process = ProcessBuilder("git", "rev-list", "--count", "HEAD")
        .directory(rootDir.parentFile)
        .redirectErrorStream(true)
        .start()
    val output = process.inputStream.bufferedReader().readText().trim()
    process.waitFor()
    output.toInt()
} catch (e: Exception) {
    1
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

    defaultConfig {
        applicationId = "com.ahmed.buildozer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = autoVersionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

val devOnlyGeneratedPlugins = listOf(
    "flutter_native_splash",
    "integration_test",
)

fun sanitizeReleaseGeneratedPluginRegistrant() {
    val registrant = layout.projectDirectory.file(
        "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
    )
    val file = registrant.asFile
    if (!file.exists()) {
        return
    }

    var content = file.readText()
    devOnlyGeneratedPlugins.forEach { pluginName ->
        val pattern = Regex(
            """(?s)\n    try \{\R      flutterEngine\.getPlugins\(\)\.add\(new [^;]+;\R    \} catch \(Exception e\) \{\R      Log\.e\(TAG, "Error registering plugin $pluginName, [^"]+", e\);\R    \}""",
        )
        content = content.replace(pattern, "")
    }
    file.writeText(content)
}

tasks.register("sanitizeReleaseGeneratedPluginRegistrant") {
    doLast {
        sanitizeReleaseGeneratedPluginRegistrant()
    }
}

tasks.matching { it.name == "compileReleaseJavaWithJavac" }.configureEach {
    dependsOn("sanitizeReleaseGeneratedPluginRegistrant")
    doFirst {
        sanitizeReleaseGeneratedPluginRegistrant()
    }
}

tasks.matching { it.name == "uploadCrashlyticsMappingFileRelease" }.configureEach {
    onlyIf {
        providers.environmentVariable("UPLOAD_CRASHLYTICS_MAPPING")
            .map { it.equals("true", ignoreCase = true) }
            .orElse(false)
            .get()
    }
}

dependencies {
    debugImplementation("com.google.firebase:firebase-appcheck-debug")
    profileImplementation("com.google.firebase:firebase-appcheck-debug")
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
}
