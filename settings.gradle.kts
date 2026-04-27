pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        maven {
            name = "GridGain External Repository"
            url = uri("https://maven.gridgain.com/nexus/content/repositories/external")
        }
        maven {
            name = "GridGain Beta Repository"
            url = uri("https://maven.gridgain.com/nexus/content/repositories/external-beta")
        }
        maven {
            name = "GridGainSnapshots"
            url = uri("https://nexus.gridgain.com/public-snapshots")
        }
    }
}

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
    id("com.gradle.enterprise") version "3.16"
}

rootProject.name = "gridgain-demo-template"
