import java.util.concurrent.TimeUnit

buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath("org.yaml:snakeyaml:2.2")
        classpath("com.fasterxml.jackson.core:jackson-databind:2.17.2")
    }
}

plugins {
    java
    id("com.gridgain.demo.plugin") version "0.5.0-SNAPSHOT"
}

group = "org.gridgain.demo"
version = "1.0-SNAPSHOT"

repositories {
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
        name = "GridGainNexus"
        url = uri("https://nexus.gridgain.com/repository/public-snapshots/")
    }
}

configurations.all {
    resolutionStrategy {
        // Force all SnakeYAML dependencies to use version 1.33
        force("org.yaml:snakeyaml:1.33")

        // Ensure we don't cache corrupted results
        cacheChangingModulesFor(0, TimeUnit.SECONDS)
        cacheDynamicVersionsFor(0, TimeUnit.SECONDS)
    }
}

dependencies {
    // Explicitly add standard SnakeYAML to override any Android variants
    implementation("org.yaml:snakeyaml:1.33")
    implementation("com.gridgain.demo:gridgain-demo-gradle-plugin:0.5.0-SNAPSHOT")
    // UI project — provides the Ktor server for launchDemoUi task
    runtimeOnly("com.gridgain.demo:gridgain-demo-ui:0.5.0-SNAPSHOT")
    implementation("org.gridgain:ignite-core:9.1.3")
    implementation("org.gridgain:ignite-api:9.1.3")
    implementation("org.gridgain:ignite-runner:9.1.3")
    implementation("org.gridgain:ignite-client:9.1.3")
    implementation("org.gridgain:ignite-jdbc:9.1.3")

    testImplementation(platform("org.junit:junit-bom:5.10.0"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

// Make validateRequirements part of the standard verification lifecycle
tasks.named("check").configure {
    dependsOn("validateRequirements")
}

// Ensure launchDemoUi picks up changes to the UI dependency on the runtime classpath.
tasks.named("launchDemoUi") {
    inputs.files(configurations.named("runtimeClasspath"))
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
}

tasks.named<Test>("test") {
    useJUnitPlatform()
}

// Fix duplicate files in distribution tasks
tasks.withType<Tar> {
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}

tasks.withType<Zip> {
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
}
