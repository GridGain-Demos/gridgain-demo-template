
> This is really the READ.me for your project. Once you have set up the project as described below,
> you should delete the following section, up to but not including the last paragragh. That section
> contains a link to this information (managed in another location) should you need it in the future.

# GridGain Demo Toolkit

**In a hurry, or setting up for the first time? Start with [QUICKSTART.md](QUICKSTART.md).** It is
the short path — what to install, how to start the wizard, and the cloud permissions to request
before you begin, since those have a lead time and are the usual reason a first attempt stalls.
This file is the reference for everything after that.

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

1. If you haven't started your project yet, you can follow [these](#starting-a-new-project-using-the-template) instructions below to start a new project directory that is preconfigured for gradle.

2. If you have started your project, but it doesn't use gradle, it may be easiest just to do the same as above, follow [these](#starting-a-new-project-using-the-template) instructions, and copy your existing files into that directory.

3. If you already have a gradle project you can follow [these](#adding-the-toolkit-to-an-existing-gradle-project) instructions to incorporate the toolkit into your existing project. You should review the
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

- For a writable image registry (required for the test-client and data-generator images)

  The demo deploys two kinds of derived container images that aren't published to any public registry: the **test client** (one per GridGain major version) and the **data generator** (one per GridGain major version). The plugin's image-bootstrap wizard builds these locally with jib and pushes them to a registry **you control**, then references them from your `demo-config.yaml`. Kubernetes pulls them at cluster-deploy time, so the registry must be publicly readable.

  The simplest option is **GitHub Container Registry** (GHCR), which gives every GitHub user a personal namespace at `ghcr.io/<your-github-username>`. The setup is a one-time, ~5-minute task.

    - **Mint a Personal Access Token (PAT).** Visit https://github.com/settings/tokens → **Generate new token (classic)**.
        - Note: `gridgain demo wizard`
        - Expiration: pick a sensible duration (e.g., 90 days)
        - Scopes: check exactly **`write:packages`** (it auto-checks `read:packages`). No other scopes.
        - Click **Generate token** and **copy the value immediately** (`ghp_…`) — GitHub won't show it again.

    - **Verify the PAT (optional but recommended).**
        ```bash
        echo "$GHCR_PAT" | docker login ghcr.io -u <your-github-username> --password-stdin
        # Expected: Login Succeeded
        ```
        If this fails, don't proceed — the wizard's connectivity test would surface the same failure later.

    - **Export the PAT in the shell that will launch the demo UI.** The plugin reads it via `System.getenv("GHCR_PAT")` at push time, so it must be present in the JVM's environment.
        ```bash
        export GHCR_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        ```
        For persistence across terminal sessions, add the `export` line to `~/.zshrc` (or your shell's rc) and `source` it.

    - **Make the published packages public after the wizard pushes them** (one-time, per package). When jib first pushes to GHCR it creates the packages as **private**; the wizard's `auth.credentials.kind: anonymous` default assumes they're public, so Kubernetes pulls would otherwise fail with `ImagePullBackOff`. After the wizard's Phase 2 completes:
        1. Visit `https://github.com/users/<your-github-username>/packages/container/<package-name>/settings`
        2. **Danger Zone** → **Change package visibility** → **Public** → confirm.
        Four packages will need this flip on first run: `demo-test-client-gg8`, `demo-test-client-gg9`, `gridgain-data-generator-gg8`, `gridgain-data-generator-gg9`. Subsequent pushes inherit the public visibility.

  GitHub Packages, GCP Artifact Registry, and any other publicly-readable / write-authenticated registry will also work — the wizard's form supports an `env-var token` mode (GHCR / Docker Hub / Quay) and a `GCP Artifact Registry via infrastructure_account` mode.

## Secrets

Credentials a demo needs — database passwords, a replication user, an ssh password for the `hosts`
platform — live in a SOPS-encrypted file under `src/main/resources/secrets/`, referenced by name from `demo-config.yaml`'s
`secrets:` section. They are never written into `demo-config.yaml` itself.

### The naming is the safety mechanism

`.sops.` in a filename means encrypted. Always.

| File | State | Git |
|------|-------|-----|
| `src/main/resources/secrets/demo-secrets.yaml.example` | plaintext placeholders | committed |
| `src/main/resources/secrets/demo-secrets.yaml` | plaintext, yours | **gitignored** |
| `src/main/resources/secrets/demo-secrets.sops.yaml` | encrypted | committed |

Because the two forms have **different names**, `.gitignore` can tell them apart and does the work:
`src/main/resources/secrets/*` is denied, and only `*.sops.yaml` and `*.yaml.example` are allowed back. A plaintext secrets
file cannot be committed by accident, not even by `git add -A`.

There is also a `.sops.yaml` at the repo root. That one is SOPS's **configuration** — it names the public
key to encrypt to, and is safe to commit. It is not a secrets file. The similar names are SOPS's
convention, not ours.

### Setup — one command

Two tools are needed first: **sops** encrypts and decrypts the file, and **age** holds the key it
uses. On macOS, `brew install sops age`. On Linux, take them from your distribution's package
manager if it carries them — neither is in every distribution's default repositories — or take the
static binaries from [sops releases](https://github.com/getsops/sops/releases) and
[age releases](https://github.com/FiloSottile/age/releases).

Then, once per repo, from the project root:

```bash
./scripts/bootstrap-secrets.sh   # idempotent, safe to re-run
```

It creates an age key if you have none, writes `.sops.yaml` with your public key, and creates
`src/main/resources/secrets/demo-secrets.sops.yaml` by encrypting the example **directly** — so the real file is born
encrypted and never exists as plaintext. That window is where credentials get left behind.

### Editing values

Preferred, because no plaintext ever reaches the disk:

```bash
sops src/main/resources/secrets/demo-secrets.sops.yaml     # opens $EDITOR, re-encrypts on save
```

For bulk editing, if you would rather work in a plain file:

```bash
sops --decrypt src/main/resources/secrets/demo-secrets.sops.yaml > src/main/resources/secrets/demo-secrets.yaml   # gitignored
$EDITOR src/main/resources/secrets/demo-secrets.yaml
./scripts/encrypt-secrets.sh            # re-encrypts, then removes the plaintext
```

Check state at any time:

```bash
grep -q '^sops:' src/main/resources/secrets/demo-secrets.sops.yaml && echo ENCRYPTED || echo PLAINTEXT
```

An example file having no `sops:` block is correct — the block appears only after encryption.

`.githooks/pre-commit` remains as a second line of defence, for a file hand-made under the encrypted name.
`bootstrap-secrets.sh` enables it.

## Starting a new project using the template


For clarity, **this** [repo](https://github.com/GridGain-Demos/gridgain-demo-template) is the template repo. You are likely viewing this document as the README.md of that repo.

The instructions below detail how you can clone this repo onto your computer, and then make a copy of it into another directory. Replace `../my-demo` with any path you choose.  Step 5 is important to clear the git history and origins from the template repo if you wish to use git to manage your own project.

Alternatively, you could clone this repo anywhere, not copy it, and run Step 5 on the directory you cloned the repo into in order to disconnect its git history and origins from the template project.

There is no dependency on the original repo cloned to your computer after a copy is made.

### Primary path — wizard-driven

```bash
# 1.  Clone the template and copy it to your new project location.
git clone https://github.com/GridGain-Demos/gridgain-demo-template
cp -r gridgain-demo-template ../my-demo
cd ../my-demo

# 2. Optional — only matters if you'll publish your project as Maven artifacts. The script
#    sets rootProject.name (and optionally group). It no longer seeds demo-config.yaml.
./rename-demo.sh my-demo com.example.mydemo

# 3. Generate src/main/resources/demo-config.yaml.
#    The configuration is built from the answers you give — nothing is pruned from a
#    template and there are no placeholders left to substitute. The result is annotated
#    with what each entry is for, so it is worth reading before you change it.
#
#    You do not have to know which properties to pass. Give the four choices below and
#    the task reports every remaining value it needs, all of them at once, each with the
#    property that supplies it and why it is asked rather than assumed.
./gradlew initDemoConfig \
    -Pwizard.platform=gke \
    -Pwizard.ggVersion=9 \
    -Pwizard.monitor=none \
    -Pwizard.derivedImages=public \
    -Pwizard.region=us-west1 \
    -Pwizard.secret.ownership_tag=you \
    -Pwizard.secret.gcp_account=you@example.com \
    -Pwizard.secret.gcp_project=demo-project \
    -Pwizard.secret.gg9_license_file=cluster/gridgain-license.json
#
# The four choices, and what each costs you:
#   -Pwizard.platform       gke, eks or hosts (comma-separate for more than one)
#   -Pwizard.ggVersion      8 or 9
#   -Pwizard.monitor        control-center, or none. A cluster deploys and serves traffic
#                           without one; control-center additionally needs
#                           -Pwizard.secret.cc_license_file, cc_admin_email and
#                           cc_admin_password.
#   -Pwizard.derivedImages  public pulls the published test-client and data-generator
#                           images and needs nothing else. skip is also fine — it costs
#                           only connectTestClient and dataGenerate. build-and-push needs
#                           Docker, a registry you can write to, and source checkouts.

# 4. Verify the wizard's output and the plugin wiring.
./gradlew validateDemoConfiguration
./gradlew tasks

# 5. Optional — clear the template's git history so this is your project's history.
rm -rf .git && git init && git add . && git commit -m "Initial commit"
# Or, if you don't intend to use git, remove the git artifacts entirely:
rm -rf .git && rm .gitignore

# 6. Use the UI to clone clusters or fine-tune your configuration.
./gradlew launchPluginUi
```

### Editing the configuration by hand

`initDemoConfig` is the way to *create* the file; editing it afterwards is expected and safe. The
output is commented throughout, and `./gradlew launchPluginUi` gives you a form-driven editor over
the same document if you prefer that to YAML.

## Adding the toolkit to an existing gradle project

You can skip this section if you have chosen to use the template as a starting point of your project.
Jump to [this section](#whats-in-here)

Use this path if you already have a Gradle project (Kotlin DSL) and want to graft the GridGain
demo toolkit onto it instead of starting from the template directory.

**Prerequisites**
- Gradle build using the **Kotlin DSL** (`*.gradle.kts`). Groovy DSL is not supported by these
  snippets — translate manually if you must.
- **Java 17** available (Gradle's toolchain will fetch it if needed).
- A working `gradle/wrapper/` directory (`./gradlew`). Run `gradle wrapper` first if you don't
  have one.

> The snippets below use plugin/UI version `0.7.0-SNAPSHOT`.
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
    id("com.gridgain.demo.plugin") version "0.7.0-SNAPSHOT"
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
    implementation("com.gridgain.demo:gridgain-demo-gradle-plugin:0.7.0-SNAPSHOT")
    // UI project — provides the Ktor server for the launchPluginUi task
    runtimeOnly("com.gridgain.demo:gridgain-demo-ui:0.7.0-SNAPSHOT")

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

// Ensure launchPluginUi sees runtime-classpath changes (so the UI reloads)
tasks.named("launchPluginUi") {
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

There is nothing to download. `initDemoConfig` builds the configuration from your answers:

```bash
mkdir -p src/main/resources
./gradlew initDemoConfig \
    -Pwizard.platform=gke \
    -Pwizard.ggVersion=9 \
    -Pwizard.monitor=none \
    -Pwizard.derivedImages=public \
    -Pwizard.region=us-west1 \
    -Pwizard.secret.ownership_tag=you \
    -Pwizard.secret.gcp_account=you@example.com \
    -Pwizard.secret.gcp_project=demo-project \
    -Pwizard.secret.gg9_license_file=cluster/gridgain-license.json
```

Pass just the four choices — `platform`, `ggVersion`, `monitor`, `derivedImages` — and the task
reports every remaining value it needs in one go, each with the property that supplies it and why
it is asked rather than assumed. See step 3 of the Quick Start above for what each choice costs
you.

The output is annotated with what each entry is for, and the task will not overwrite a
configuration that already exists.

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

### 8. Verify

```bash
./gradlew tasks --group "GridGain Demo"
./gradlew validateDemoConfiguration
```

If `tasks` lists `initDemoConfig`, `validateDemoConfiguration`, `launchPluginUi`, etc.,
the plugin is wired in correctly. Use `./gradlew initDemoConfig -Pwizard.platform=… …` to
generate a populated `demo-config.yaml` — pass the four choices and it will tell you every other
value it needs. Then run `./gradlew launchPluginUi` to fine-tune via the UI.

## What's in here

| Path | Purpose |
|------|---------|
| `settings.gradle.kts` | Sets `rootProject.name`; resolves the plugin and UI from GridGain Maven repos. |
| `build.gradle.kts` | Applies `com.gridgain.demo.plugin`; depends on GridGain 9 runtime + the UI project. |
| `gradle.properties` | Points the plugin at `src/main/resources/demo-config.yaml`. |
| `rename-demo.sh` | Updates `rootProject.name` and (optionally) `group`. Config-seeding moved to `./gradlew initDemoConfig`. |
| `src/main/resources/generator/ops.yaml` | Data-generator scenarios: one worked example load profile. The path the UI looks at on startup. |
| `src/main/resources/generator/data.yaml` | The data schemas those scenarios generate against. Always paired with the `ops.yaml` beside it. |
| `.gitignore` | Ignores `demo-config.yaml`, license files, build outputs, IDE files. |

### The data generator's scenarios file

`src/main/resources/generator/{ops,data}.yaml` ship as a tracked, working pair — unlike
`demo-config.yaml`, they hold no credentials, so they are committed rather than gitignored. The demo
UI reads that exact path when it starts, so the Scenarios page and the Load page have something to
show in a fresh clone. Both files are commented throughout; the two things you are most likely to
change are:

- **`provisioning:`** on the example scenario — set it to `apply` for a first run against a cluster
  that has never seen the schema, so the generator creates the tables before writing to them.
- **the `metrics:` and `control:` blocks** at the bottom of `ops.yaml`, which are commented out.
  Uncomment them and set `kafka_bootstrap` to drive the generator's rate live from the UI's Load
  page. That address is resolved from the *generator's* vantage point and is deliberately separate
  from `uiKafkaBootstrap` in `gradle.properties`, which is resolved from the machine running the UI.

Which cluster a run writes to is **not** in these files — it is chosen at launch, from the Load
page's target selector or `--targetCluster` on the generator CLI.

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
admin passwords, and cloud credentials, so it must never be committed — and neither may a backup or
a dated snapshot of one, which is why `.gitignore` names those shapes too. Licence files are
ignored in every form the vendor issues them: `**/*-license.json` and `**/*-license.xml`.

## gridgain-demo-template
This project was created using the [gridgain-demo-template](https://github.com/GridGain-Demos/gridgain-demo-template)

For information about the plugin and its associated projects, please see the [plugin's own documentation](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin)
for the full list of requirements, tasks, configuration schema, and processing-pipeline details.






