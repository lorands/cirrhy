import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Which key signs a release build is a property of the machine, not of the
// project — the same rule ios/Flutter/Signing.xcconfig follows, and for the
// same reason: nobody's signing material belongs in a public repository.
// tool/android-signing.sh writes android/key.properties, which is gitignored.
// Without it a release build falls back to the debug keys, so a fresh clone
// still builds `--release`; it just cannot publish what it builds.
val signing =
    Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }

// Gradle does not expand a leading ~, and a keystore path is exactly where
// someone writes one by hand.
fun signingFile(raw: String): File {
    val expanded =
        if (raw.startsWith("~/")) System.getProperty("user.home") + raw.substring(1) else raw
    return rootProject.file(expanded)
}

android {
    namespace = "com.lorands.cirrhy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The project's identity, DESIGN.md §7. Android and Linux keep the
        // plain reverse domain; only the Apple bundle ID carries the `app`
        // suffix, and it is not a mistake that the two differ.
        applicationId = "com.lorands.cirrhy"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signing.isNotEmpty()) {
            create("upload") {
                val path =
                    signing.getProperty("storeFile")
                        ?: throw GradleException(
                            "android/key.properties has no storeFile — " +
                                "rerun tool/android-signing.sh",
                        )
                storeFile = signingFile(path)
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")

                // Loud on purpose. A missing keystore that quietly fell back
                // to debug keys would produce a build that looks releasable,
                // uploads, and is refused by the Play Console — the slowest
                // possible way to discover it.
                if (!storeFile!!.exists()) {
                    throw GradleException(
                        "keystore not found: ${storeFile!!.absolutePath}\n" +
                            "  android/key.properties points at a file that is not there. " +
                            "Restore it from your backup, rerun tool/android-signing.sh, " +
                            "or delete android/key.properties to go back to debug-signed builds.",
                    )
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // DocumentFile wraps the Storage Access Framework's tree URIs, which is
    // how DESIGN.md §4.2's "ask for a folder" is expressed on Android.
    // Apache-2.0, so it raises no licensing question for this project.
    implementation("androidx.documentfile:documentfile:1.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
