> This is really the READ.me for your project. Once you have set up the project as described belwo, you should delete the following section, up to but not including the last paragragh. That section
contains a link to this information (managed in another location) should you need it in the future.

# GridGain Demo Toolkit

The GridGain Demo Toolkit is a set of tools for deploying GridGain clusters in various environments.
Internally to GridGain, there is a [project goals presentation](https://docs.google.com/presentation/d/1EafadCta4LH6VcilLQFJ4wfXdda5J67i/edit?slide=id.p1#slide=id.p1) that may be useful for understanding the structure of the toolkit. This presentation covers the currently supported environments as well as future considerations, so we will not try to keep that information synchonrized here.

There is a MariaDB slack channel dedicated to asking for help and requesting enhancements on this proejct:
- **#proj-gridgain-gradle-plugin**

There are currently two main components:
- **gridgain-demo-gradle-plugin** which implements the deployment tasks
- **gridgain-demo-ui** which provides a UI layer over configuration and task deployment

Users of the toolkit have no need to reference the repositories for the above projects. Those projects have been built and published to a GridGain hosted maven repository. The **gridgain-demo-template** project has been designed to abstract away the complexity of configuring the use of those projects in a gradle environment.

The gradle layer is a very thin layer over a set of Kotlin classes. These classes could be packaged in a way that they could be used without the gradle layer. If that is something you would need, please request it in the slack channel mentioned above.


## GridGain Demo Template
This repo contains a minimal shell that is preconfigured for creating a new GridGain demo project driven by the GridGain Demo Toolkit.

There are mulltiple ways to incorporate the toolkit into your project, with the use of this repo being only one option.

1. If you haven't started your project yet, you can follow [these](#starting-with-the-template) instructions below to start a new project directory that is preconfigured for gradle.

2. If you have started your project, but it doesn't use gradle, it may be easiest just to do the same as above, follow [these](#starting-with-the-template) instructions, and copy your existing files into that directory.

3. If you already have a gradle project you can follow [these](#adding-to-an-existing-gradle-project) instructions to incorporate the toolkit into your existing project. You should review the
complexity of those instructions before choosing this option.



## Prerequisites
- Java 17 (the Gradle toolchain will download it if missing)
- git cli

You will need access to a GridGain cloud account. If you do not have this, please request it
via the [Support Portal](https://it.gridgain.com/portal/22)

The plugin **DOES NOT** handle the permutations and combinations of setting up cloud CLIs and logging in.
Please do that before using the tool.

- For AWS
    - For GridGain, from a Chrome browser logged into your corporate account, open the Google Apps window
      (the 'nine dot' menu beside your profile). You should see an AWS Access option.
      For SEs, SAs and TAMs, this is a shared account, and we should all have the administrative permissions needed.
      The shared account number is `930793918939`. Otherwise, the account number should be available from a dropdown
      in the top-right corner of the console page.
    - Create a user in the [IAM Dashboard](https://console.aws.amazon.com/iam/home) The user must have the following
      permissions (at a minimum)
        - AmazonEC2FullAccess 
        - AmazonVPCFullAccess
        - AWSCloudFormationFullAccess
        - IAMFullAccess
        - AutoScalingFullAccess 
        - ElasticLoadBalancingFullAccess
      - On the IAM user's Permissions tab, select Add Permissions -> Create inline policy -> JSON and paste the following:
      ```
          {                  
            "Version": "2012-10-17",
            "Statement": [
              {
              "Sid": "EksUserActions",
              "Effect":"Allow",                           
              "Action":[
                "eks:*"
                ], 
              "Resource": "*"                                        
              }                                       
            ]                                                           
          }
        ```
          
        Select 'Next' and give this profile a name, (suggested) `eksctl`
    - On the Security credentials tab of the new user's info, create and save an access key of type Command Line Interface (CLI)
    - Install the AWS CLI `brew install awscli eksctl kubectl`
    - Configure an AWS CLI profile  `aws configure --profile <my-demo-profile>`
        - Supply it with the AWS Access Key (from above)
        - Supply it with the AWS Secret Access Key (from above)
        - Supply it with a default region (e.g. `us-west-2`)
        - Supply it with a default output format (e.g. `json`)

    - Capture the account number — 12-digit AWS account ID ()

    - **not yet supported** roleArn (optional) — plugin will assume this role at run time via aws sts assume-role
    - **not yet supported** externalId (optional) — paired with roleArn
    - The profile name and account number must be added to an infrastructure account entry in the `demo-configuration.yaml` file.

- For GCP
    - A GCP account and project
    - Install the gcloud CLI `brew install --cask gcloud-cli`
    - Install kubectl `brew install kubectl`
    - Install additional components ` gcloud components install gke-gcloud-auth-plugin gcloud-crc32c kubectl`
    - Run `gcloud components update`
    - Incorporate this into your ~/.rshrc `export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"`
    - Run `gcloud init` to login

## Starting a new project using the template


For clarity, **this** [repo](https://github.com/GridGain-Demos/gridgain-demo-template) is the template repo. You are likely viewing this document as the README.md of that repo.

The instructions below detail how you can clone this repo onto your computer, and then make a copy of it into another directory. Replace `../my-demo` with any path you choose.  Step 5 is important to clear the git history and origins from the template repo if you wish to use git to manage your own project.

Alternatively, you could clone this repo anywhere, not copy it, and run Step 5 on the directory you cloned the repo into in order to disconnect its git history and origins from the template project.

There is no dependency on the original repo cloned to your computer after a copy is made.

```bash
# 1.  Clone the template into a directory and make a copy to your new project location.
git clone https://github.com/GridGain-Demos/gridgain-demo-template
cp -r gridgain-demo-template ../my-demo
cd ../my-demo

# 2. Optional - This only matters if you intend to package and publish your project as maven artifacts or jar files for use in other projects. There is a convenience script to reset the default name used in the template.

./rename-demo.sh my-demo com.example.mydemo

# 4. Verify the plugin is working correctly:

./gradlew tasks

# 5. Optional, does no harm - critical if you want to use git to backup your project
rm -rf .git && git init && git add . && git commit -m "Initial commit"

# 6. Copy the configuration file template to be your configuration file and edit the copy.
#    Then replace the <YOUR_...> placeholders with your account, licenses, namespaces, etc.

cp .src/main/resources/demo-config.yaml.template ./src/main/resources/demo-config.yaml

# 7. Start the Plugin UI and edit the configuration file
./gradlew launchPluginUi

```

## Adding the toolkit to an existing gradle project

You can skip this section if you have chosen to use the template as a starting point of your project.
Jump to [this section](#what's-in-here)

Use this path if you already have a Gradle project (Kotlin DSL) and want to graft the GridGain
demo toolkit onto it instead of starting from the template directory.

**Prerequisites**
- Gradle build using the **Kotlin DSL** (`*.gradle.kts`). Groovy DSL is not supported by these
  snippets — translate manually if you must.
- **Java 17** available (Gradle's toolchain will fetch it if needed).
- A working `gradle/wrapper/` directory (`./gradlew`). Run `gradle wrapper` first if you don't
  have one.

> The snippets below use plugin/UI version `0.0.5-SNAPSHOT`.
> Check the [plugin repo](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin) for
> the current released version and update both the `id(...) version` and the matching
> `implementation` / `runtimeOnly` coordinates in lock-step.

### 1. Add GridGain repositories to `settings.gradle.kts`

In the `pluginManagement { repositories { ... } }` block, add the three GridGain Maven repos
alongside whatever you already have:

```kotlin
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        maven {
            name = "GridGainNexus"
            url = uri("https://nexus.gridgain.com/repository/public-snapshots/")
        }
    }
}
```

The `nexus.gridgain.com/repository/public-snapshots/` repo allows anonymous reads — no
credentials are required to consume the plugin or UI artifacts.


### 2. Apply the plugin in `build.gradle.kts`

Add a `buildscript` block (needed for SnakeYAML/Jackson on the build classpath), apply the
`com.gridgain.demo.plugin` id, and add the same GridGain Maven repos to your `repositories`
block:

```kotlin
import java.util.concurrent.TimeUnit

buildscript {
    repositories { mavenCentral() }
    dependencies {
        classpath("org.yaml:snakeyaml:2.2")
        classpath("com.fasterxml.jackson.core:jackson-databind:2.17.2")
    }
}

plugins {
    java // or your existing language plugins
    id("com.gridgain.demo.plugin") version "0.0.5-SNAPSHOT"
}

repositories {
    mavenCentral()
    maven { url = uri("https://nexus.gridgain.com/repository/public-snapshots/") }
}
```

### 3. Force SnakeYAML 1.33 and disable SNAPSHOT caching

This pin is **mandatory** — newer SnakeYAML pulls in an Android variant that breaks the build.
Add to `build.gradle.kts`:

```kotlin
configurations.all {
    resolutionStrategy {
        force("org.yaml:snakeyaml:1.33")
        cacheChangingModulesFor(0, TimeUnit.SECONDS)
        cacheDynamicVersionsFor(0, TimeUnit.SECONDS)
    }
}
```

### 4. Add the dependencies

The plugin itself supports both GridGain 8 and GridGain 9 demos. Add the runtime artifacts for
whichever target you're deploying — both blocks are included below so you can simply **delete
the one you don't need** rather than hunt for the right coordinates.

> **Important:** GG8 and GG9 share artifact names (e.g., `ignite-core`). If you leave both
> blocks in place, Gradle will resolve to the higher version (GG9) and silently drop GG8 from
> the classpath. Keep only the block matching your target GridGain major version.

```kotlin
dependencies {
    implementation("org.yaml:snakeyaml:1.33")
    implementation("com.gridgain.demo:gridgain-demo-gradle-plugin:0.0.5-SNAPSHOT")
    // UI project — provides the Ktor server for the launchDemoUi task
    runtimeOnly("com.gridgain.demo:gridgain-demo-ui:0.0.5-SNAPSHOT")

    // ---------------------------------------------------------------------------
    // GridGain 9 runtime — keep this block if your target cluster is GG9.
    // ---------------------------------------------------------------------------
    implementation("org.gridgain:ignite-core:9.1.3")
    implementation("org.gridgain:ignite-api:9.1.3")
    implementation("org.gridgain:ignite-runner:9.1.3")
    implementation("org.gridgain:ignite-client:9.1.3")
    implementation("org.gridgain:ignite-jdbc:9.1.3")

    // ---------------------------------------------------------------------------
    // GridGain 8 runtime — keep this block if your target cluster is GG8.
    // Conflicts with the GG9 block above on `ignite-core`; do not keep both.
    // ---------------------------------------------------------------------------
    implementation("org.gridgain:ignite-core:8.9.20")
    implementation("org.gridgain:ignite-spring:8.9.20")
    implementation("org.gridgain:ignite-indexing:8.9.20")
    implementation("org.gridgain:ignite-control-utility:8.9.20")
    implementation("org.gridgain:ignite-slf4j:8.9.20")
}
```

The plugin and UI versions **must match**. If you bump one, bump the other.

The GridGain runtime version (`9.1.3` / `8.9.20` shown above) should match the cluster image
tag you intend to deploy — set the latter via the `version` field on your cluster entry in
`demo-config.yaml`.

### 5. Java 17 toolchain and task wiring

```kotlin
java {
    toolchain { languageVersion = JavaLanguageVersion.of(17) }
}

tasks.withType<JavaCompile> { options.encoding = "UTF-8" }

// Wire validateRequirements into ./gradlew check
tasks.named("check").configure { dependsOn("validateRequirements") }

// Ensure launchDemoUi sees runtime-classpath changes (so the UI reloads)
tasks.named("launchDemoUi") {
    inputs.files(configurations.named("runtimeClasspath"))
}

// Avoid duplicate-file failures in any distribution tasks you happen to have
tasks.withType<Tar> { duplicatesStrategy = DuplicatesStrategy.EXCLUDE }
tasks.withType<Zip> { duplicatesStrategy = DuplicatesStrategy.EXCLUDE }
```

### 6. Point the plugin at your config file via `gradle.properties`

Add (or merge with) the following entries in `gradle.properties` at the project root:

```properties
# Required — path to the demo configuration file (relative to demoRootDirectory)
demoConfigFile=src/main/resources/demo-config.yaml

# Optional — defaults to '.' (project root)
demoRootDirectory=.

# Recommended for SNAPSHOT plugin/UI users
org.gradle.caching=false
org.gradle.warning.mode=none
```

You can also pass `-PdemoConfigFile=...` on the command line to override per invocation.

### 7. Seed your demo config and update `.gitignore`

Copy the starter template into your resources directory:

```bash
mkdir -p src/main/resources
curl -fsSL https://raw.githubusercontent.com/GridGain-Demos/gridgain-demo-template/main/src/main/resources/demo-config.yaml.template \
  -o src/main/resources/demo-config.yaml.template
cp src/main/resources/demo-config.yaml.template src/main/resources/demo-config.yaml
```

Add these entries to your existing `.gitignore` — `demo-config.yaml` and license files contain
secrets and must never be committed:

```gitignore
# GridGain demo plugin
.gridgain-runtime/
demo-config.yaml
environment-config.yaml
**/gridgain-license.json
**/controlcenter-license.json
**/**-license.json
```

Keep `demo-config.yaml.template` tracked — it has only `<YOUR_...>` placeholders.

### 8. Verify

```bash
./gradlew tasks --group "GridGain Demo"
./gradlew validateRequirements
./gradlew launchDemoUi
```

If `tasks` lists `validateRequirements`, `launchDemoUi`, etc., the plugin is wired in
correctly. Edit `src/main/resources/demo-config.yaml` (or use `launchDemoUi`) to fill in
your account, licenses, namespaces, and infrastructure details.

## What's in here

| Path | Purpose |
|------|---------|
| `settings.gradle.kts` | Sets `rootProject.name`; resolves the plugin and UI from GridGain Maven repos. |
| `build.gradle.kts` | Applies `com.gridgain.demo.plugin`; depends on GridGain 9 runtime + the UI project. |
| `gradle.properties` | Points the plugin at `src/main/resources/demo-config.yaml`. |
| `rename-demo.sh` | Updates `rootProject.name` and (optionally) `group`; seeds `demo-config.yaml`. |
| `src/main/resources/demo-config.yaml.template` | Starter configuration. Copy to `demo-config.yaml` and edit. |
| `.gitignore` | Ignores `demo-config.yaml`, license files, build outputs, IDE files. |

## Manual rename (if you can't run the script)
Again, the gradle project name is only important if you plan on publishing your project as maven artifacts or zip files.

Three edit points:

1. `settings.gradle.kts` — `rootProject.name = "..."`.
2. `build.gradle.kts` — `group = "..."` (and `version` if desired).
3. The containing directory name on disk.

## Java Clients
The `dependencies` section of the `build.gradle.kts` file contains entries for both GridGain8 and GridGain 9 clients. The `ignite-core` package is named the same in both and will cause a conflict if you use GridGain java clients in your proeject. To correct this, simply edit that file an remove the set of dependencies that you do not need.

## Secrets handling

`demo-config.yaml` is **gitignored**. It will typically contain account emails,
admin passwords, and cloud credentials, so it must never be committed. The
tracked `demo-config.yaml.template` has only placeholders and is safe to commit.
License files (`**/gridgain-license.json`, `**/controlcenter-license.json`) are
also gitignored.

## Further reading

See the [plugin's own documentation](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin)
for the full list of tasks, configuration schema, and processing-pipeline details.


> It is recommended that you delete everything above this section and replace it with the READ.me contents of your demo.
> Leave the section below for its links back to the plugin project.

## gridgain-demo-template
This project was created using the [gridgain-demo-template](https://github.com/GridGain-Demos/gridgain-demo-template)
Information on installing and using the plugin may be found in it's
[READ.me](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin)






