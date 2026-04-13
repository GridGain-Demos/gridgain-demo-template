# gridgain-demo-template

A minimal shell for creating a new GridGain demo project driven by the
[`gridgain-demo-gradle-plugin`](../gridgain-demo-gradle-plugin).
Clone it, rename it, drop in your own code and configuration, and the plugin's
tasks (e.g. `validateRequirements`, `launchDemoUi`) will be available immediately.

## Prerequisites

- Java 17 (the Gradle toolchain will download it if missing).
- Sibling projects present at `../gridgain-demo-gradle-plugin` and
  `../gridgain-demo-ui`. The `settings.gradle.kts` uses `includeBuild(...)` to
  consume them directly — no `publishToMavenLocal` step is required.

## Quickstart

```bash
# 1. Copy this directory to your new project location.
cp -r gridgain-demo-template ../my-demo
cd ../my-demo

# 2. Initialize names and seed the config file.
./rename-demo.sh my-demo com.example.mydemo

# 3. Edit src/main/resources/demo-config.yaml and replace the <YOUR_...>
#    placeholders with your account, licenses, namespaces, etc.

# 4. Verify the plugin is wired in correctly:
./gradlew tasks

# 5. When you want a fresh git history:
rm -rf .git && git init && git add . && git commit -m "Initial commit"
```

## What's in here

| Path | Purpose |
|------|---------|
| `settings.gradle.kts` | Sets `rootProject.name`; `includeBuild`s the plugin + UI siblings. |
| `build.gradle.kts` | Applies `com.gridgain.demo.plugin`; depends on GridGain 9 runtime + the UI project. |
| `gradle.properties` | Points the plugin at `src/main/resources/demo-config.yaml`. |
| `rename-demo.sh` | Updates `rootProject.name` and (optionally) `group`; seeds `demo-config.yaml`. |
| `src/main/resources/demo-config.yaml.template` | Starter configuration. Copy to `demo-config.yaml` and edit. |
| `.gitignore` | Ignores `demo-config.yaml`, license files, build outputs, IDE files. |

## Manual rename (if you can't run the script)

Three edit points:

1. `settings.gradle.kts` — `rootProject.name = "..."`.
2. `build.gradle.kts` — `group = "..."` (and `version` if desired).
3. The containing directory name on disk.

Then `cp src/main/resources/demo-config.yaml.template src/main/resources/demo-config.yaml`
and edit the copy.

## Secrets handling

`demo-config.yaml` is **gitignored**. It will typically contain account emails,
admin passwords, and cloud credentials, so it must never be committed. The
tracked `demo-config.yaml.template` has only placeholders and is safe to commit.
License files (`**/gridgain-license.json`, `**/controlcenter-license.json`) are
also gitignored.

## Further reading

See the plugin's own README in `../gridgain-demo-gradle-plugin/` for the full
list of tasks, configuration schema, and processing-pipeline details.
