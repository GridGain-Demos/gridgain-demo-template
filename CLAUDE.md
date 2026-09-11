# CLAUDE.md — gridgain-demo-template

## What this project is

This is a **user-facing template** for creating GridGain demo projects. Users clone it, rename it,
fill in their configuration, and use the `gridgain-demo-gradle-plugin` tasks to deploy GridGain clusters
and related infrastructure.

This project does **not** contain plugin source code — all custom Gradle tasks come from the
`gridgain-demo-gradle-plugin` resolved via Maven. Do not add bespoke Gradle tasks here.

## Using the toolkit — the skills are here

Two usage skills ship **in this project**, under `.claude/skills/`:

- **`gridgain-demo-toolkit`** — the plugin's task surface, the `demo-config.yaml` element types,
  schema versioning, and how the data generator is dispatched.
- **`gridgain-demo-data-generator`** — the generator's own `ops.yaml` / `data.yaml` config surface
  and semantics.

They auto-load when Claude Code is run from this directory, so there is nothing to fetch and
nothing to set up. Both document behaviour that is otherwise rediscovered the hard way — that
`dataGenerate` has no rate-override property, that a multi-pod generator's rate is per pod so the
total is roughly rate × pods, that `OPTION_LIBS` does not exist on the `hosts` platform.

They are **copies**, and the copy is deliberate. A fetched URL is not a registered skill, so it
only ever helps a reader who already knew to go and get it; it assumes a public repo and a network;
and it points at `main`, which is ahead of the plugin version this project pins. A copy that ships
with a release matches the release.

Each is authored in the repo it documents — the toolkit skill in `gridgain-demo-gradle-plugin`, the
generator skill in `gridgain-demo-data-generator` — and refreshed here by that plugin's
`bin/sync-scaffold.sh`. So **edit them there, not here**: an edit made in this copy is what the
next sync discards.

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
