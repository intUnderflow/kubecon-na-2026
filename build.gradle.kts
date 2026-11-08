// Root build file. Only declares plugin versions; :app applies them.
plugins {
    alias(libs.plugins.android.application) apply false
    // Not applied anywhere (AGP 9 compiles Kotlin itself); declared so AGP
    // builds with this Kotlin rather than the older one it depends on.
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
