import java.util.Properties
import java.io.FileInputStream
import java.security.SecureRandom
import java.util.Base64

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Must equal APP_SIGNING_SECRET on the API server. Release builds refuse to build without it.
val devAppSigningSecret = "dev-only-washa-app-signing-secret-change-me"
val releaseAppSigningSecret: String =
    (System.getenv("WASHA_APP_SIGNING_SECRET") ?: keystoreProperties.getProperty("appSigningSecret") ?: "").trim()

/** Splits the secret into two XOR shares so it never appears as one literal in the dex. */
fun maskedSecretFields(secret: String): Pair<String, String> {
    if (secret.isEmpty()) return "" to ""
    val plain = secret.toByteArray(Charsets.UTF_8)
    val mask = ByteArray(plain.size).also { SecureRandom().nextBytes(it) }
    val shareA = ByteArray(plain.size) { i -> (plain[i].toInt() xor mask[i].toInt()).toByte() }
    val enc = Base64.getEncoder()
    return enc.encodeToString(shareA) to enc.encodeToString(mask)
}

android {
    namespace = "com.washatv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.washatv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            val (a, b) = maskedSecretFields(devAppSigningSecret)
            buildConfigField("String", "WS_A", "\"$a\"")
            buildConfigField("String", "WS_B", "\"$b\"")
        }
        release {
            val (a, b) = maskedSecretFields(releaseAppSigningSecret)
            buildConfigField("String", "WS_A", "\"$a\"")
            buildConfigField("String", "WS_B", "\"$b\"")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildingRelease && releaseAppSigningSecret.length < 32) {
        throw GradleException(
            "Release build needs appSigningSecret (>= 32 chars) in android/key.properties " +
                "or WASHA_APP_SIGNING_SECRET env — same value as APP_SIGNING_SECRET on the API server.",
        )
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.15.0")
    val media3 = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-dash:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.webkit:webkit:1.12.1")
}
