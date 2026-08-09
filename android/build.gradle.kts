// AGP and the Android/Compose plugins are declared in app/build.gradle.kts only,
// so that `-Ppenpot.coreOnly=true` builds (JVM-only :core, e.g. CI without an
// Android SDK or access to Google Maven) never need to resolve them.
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
