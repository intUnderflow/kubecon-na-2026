plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Where the app looks for newer schedule data (data/manifest.json and the files it lists).
// A fork can point it elsewhere with -PKCNA26_DATA_BASE_URL=… (must end with '/').
val dataBaseUrl: String = providers.gradleProperty("KCNA26_DATA_BASE_URL")
    .getOrElse("https://raw.githubusercontent.com/intUnderflow/kubecon-na-2026/main/data/")

// Release signing comes from Gradle properties (e.g. ~/.gradle/gradle.properties), never from
// the repo. Without all four, assembleRelease still works and produces an unsigned APK.
val releaseSigning: Map<String, String>? = listOf(
    "KCNA26_STORE_FILE", "KCNA26_STORE_PASSWORD", "KCNA26_KEY_ALIAS", "KCNA26_KEY_PASSWORD",
).associateWith { providers.gradleProperty(it).orNull.orEmpty() }.takeIf { m -> m.values.all { it.isNotEmpty() } }

android {
    namespace = "app.kcna26"
    // compileSdk 37 (Android 17); targetSdk stays 36.
    compileSdk = 37

    defaultConfig {
        applicationId = "app.kcna26"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        buildConfigField("String", "DATA_BASE_URL", "\"$dataBaseUrl\"")
    }

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = file(releaseSigning.getValue("KCNA26_STORE_FILE"))
                storePassword = releaseSigning.getValue("KCNA26_STORE_PASSWORD")
                keyAlias = releaseSigning.getValue("KCNA26_KEY_ALIAS")
                keyPassword = releaseSigning.getValue("KCNA26_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Off: turning it on needs verified keep rules for kotlinx-serialization and Compose.
            isMinifyEnabled = false
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    lint {
        // False positive: MainActivity is a ComponentActivity and the activity-result APIs come
        // from activity 1.13; the old fragment 1.1.0 is only pulled in by play-services-base.
        disable += "InvalidFragmentVersionForActivityResult"
    }

    testOptions {
        unitTests {
            // android.* calls in code under test return defaults instead of throwing.
            isReturnDefaultValues = true
            // Tests run with app/ as the working directory, so they read
            // src/main/assets/*.json directly (see TestData.kt).
            all { it.workingDir = projectDir }
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.savedstate)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.compose.foundation)
    implementation(libs.compose.animation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.adaptive)
    implementation(libs.compose.adaptive.layout)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.play.services.location)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
