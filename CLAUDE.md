# CLAUDE.md — gridgain-demo-template

## What this project is

This is a **user-facing template** for creating GridGain demo projects. Users clone it, rename it,
fill in their configuration, and use the `gridgain-demo-gradle-plugin` tasks to deploy GridGain clusters
and related infrastructure.

This project does **not** contain plugin source code — all custom Gradle tasks come from the
`gridgain-demo-gradle-plugin` resolved via Maven. Do not add bespoke Gradle tasks here.

## Build setup

- **Java 17** required (enforced via Gradle toolchain). Kotlin DSL throughout.
- Dependencies (including the plugin and UI) are resolved from Maven repos — primarily
  `https://nexus.gridgain.com/repository/public-snapshots/`, which allows anonymous reads.
  No Nexus credentials are needed to consume the plugin/UI artifacts.
- **No `mavenLocal()`** — this template should never depend on locally published artifacts.
- **No `includeBuild()`** — this template should never reference sibling project directories.
- **SnakeYAML** is forced to `1.33` to prevent Android variant conflicts. This is intentional.

## Key files

| File | Purpose |
|------|---------|
| `gradle.properties` | Points plugin at `src/main/resources/demo-config.yaml` |
| `demo-config.yaml.template` | Tracked starter config with `<YOUR_...>` placeholders |
| `demo-config.yaml` | User's actual config (gitignored, contains secrets) |

## Rules

- `demo-config.yaml` contains secrets — never commit it.
- Do not create missing config files; a missing file indicates a bug.
- Keep this template minimal — it exists for end users, not plugin development.
