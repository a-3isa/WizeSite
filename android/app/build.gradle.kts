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

// Auto-versioning, but ONLY for an AAB build (`flutter build appbundle` ->
// Gradle task `bundleRelease`). APK builds (`flutter build apk`,
// `flutter run`, etc.) are unaffected and keep pubspec.yaml's version as-is.
//
// On a bundle build:
//   - versionName's patch number is bumped by 1 (1.0.0 -> 1.0.1 -> 1.0.2 ...)
//     and the new version is written back into pubspec.yaml, so the bump is
//     visible there and persists into the next build.
//   - versionCode is derived from git commit count: strictly increasing and
//     unique per commit, so Play never rejects an upload for reusing a code.
// Caveat: the pubspec.yaml bump happens at Gradle configuration time, before
// the bundle is actually produced — if the build fails afterwards, the
// version has still been consumed (rare in practice, but re-running after a
// genuine failure will skip a patch number rather than reuse one).
val isBundleBuild = gradle.startParameter.taskNames.any {
    it.contains("bundle", ignoreCase = true)
}
val pubspecFile = rootDir.parentFile.resolve("pubspec.yaml")
val pubspecVersionLine = Regex("""(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)""")

val bundleVersionName: String? = if (isBundleBuild) {
    val text = pubspecFile.readText()
    val match = pubspecVersionLine.find(text)
    if (match == null) {
        null
    } else {
        val (major, minor, patch, build) = match.destructured
        val newVersionName = "$major.$minor.${patch.toInt() + 1}"
        pubspecFile.writeText(
            pubspecVersionLine.replaceFirst(text, "version: $newVersionName+$build"),
        )
        newVersionName
    }
} else {
    null
}

val autoVersionCode: Int = if (isBundleBuild) {
    try {
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
} else {
    flutter.versionCode
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
        versionName = bundleVersionName ?: flutter.versionName
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
