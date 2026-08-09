pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "penpot-android"
include(":core")
// `./gradlew -Ppenpot.coreOnly=true :core:test` runs the pure-JVM test suite
// without configuring the Android module (no Android SDK / Google Maven needed).
if (!providers.gradleProperty("penpot.coreOnly").isPresent) {
    include(":app")
}
