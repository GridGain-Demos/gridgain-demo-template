# CLAUDE.md — gridgain-demo-template

## What this project is

This is a **user-facing template** for creating GridGain demo projects. Users clone it, rename it,
fill in their configuration, and use the `gridgain-demo-gradle-plugin` tasks to deploy GridGain clusters
and related infrastructure.

This project does **not** contain plugin source code — all custom Gradle tasks come from the
`gridgain-demo-gradle-plugin` resolved via Maven. Do not add bespoke Gradle tasks here.

## Using the toolkit — read the skills

The toolkit ships two usage skills that document how to deploy/tear down elements, edit
`demo-config.yaml`, choose plugin tasks, and run the data generator — including non-obvious behavior
you'd otherwise rediscover the hard way (e.g. `dataGenerate` has no rate-override property; multi-pod
generator rate is per-pod, so total ≈ rate × pods).

This template consumes the plugin/generator from Maven and has **no sibling repos**, so read the
skills from their canonical location on GitHub (fetch the raw form to read them in-session):

- **Toolkit (plugin tasks, element types, generator dispatch):**
  `https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin/blob/main/.claude/skills/gridgain-demo-toolkit/SKILL.md`
- **Data generator (ops.yaml/data.yaml config + semantics):**
  `https://github.com/GridGain-Demos/gridgain-demo-data-generator/blob/main/.claude/skills/gridgain-demo-data-generator/SKILL.md`

Those skills are the source of truth and are kept current in their own repos — don't copy them here
(a local copy would drift). When working inside the full toolkit workspace (sibling repos present),
they also auto-load from each repo's `.claude/skills/`.

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
| `demo-config.yaml` | User's actual config (gitignored, contains secrets) |

## Rules

- `demo-config.yaml` contains secrets — never commit it.
- Do not create missing config files; a missing file indicates a bug.
- Keep this template minimal — it exists for end users, not plugin development.
