---
name: gridgain-demo-toolkit
description: How to USE the GridGain Demo Toolkit (gridgain-demo-gradle-plugin) — its Gradle task surface, the demo-config.yaml element types (infrastructures, hosts, distributions, clusters, databases, cdc_connectors, data_generators, monitors, connector_templates, proxies, secrets, assemblies, node pools, data model), the gke/eks/hosts platforms, host-machine observability (Prometheus, Grafana and an OpenTelemetry Collector under systemd), schema versioning, and how it dispatches the data generator. Use when deploying or tearing down demo elements, editing demo-config.yaml, picking which plugin task to run, debugging a deploy, or running a load test against a deployed cluster.
---

# GridGain Demo Toolkit — Usage

*Last updated: 2026-09-02*

The toolkit is the `gridgain-demo-gradle-plugin` (the primary product). A target-demo project consumes it via `includeBuild`/`mavenLocal` and invokes its Gradle tasks; demo projects must not add bespoke tasks. This skill is the usage map: tasks, the config model, and gotchas. For the **data generator's own config surface** (ops.yaml/data.yaml, rate kinds, transaction_scope, distribution), see the `gridgain-demo-data-generator` skill — this skill only covers how the plugin *dispatches* it.

> **Verify before asserting.** Task options, element fields and `CURRENT_SCHEMA_VERSION` drift. Cite the source files in §Sources when a fact must be exact, and re-check. Keep *Last updated* current when you change this file.

## Mental model

**Pipeline:** `demo-config.yaml` → migrate to current `schema_version` → JSONSchema validate → deserialize to `ConfiguredState` → `*SpecAssembler` resolves templates+references into deployable specs → task renders k8s manifests / runs clients → records `deployment.yaml` (runtime state).

**Element hierarchy:** instances reference templates + accounts. e.g. a `clusters` entry → a `cluster_templates` entry → a `node_pool_templates` entry; an `infrastructures` entry → `infrastructure_templates` + `infrastructure_accounts`.

**Platforms.** `platform` on a template — and, since v18, on every `clusters` entry — is one of `gke`, `eks`, `hosts`. The first two are Kubernetes; `hosts` deploys to a collection of pre-existing Linux machines over ssh with systemd supervision (GG8 only for now). Platform-specific fields are prefixed `k8s_` or `host_` and live inside their platform's `if`/`then` branch in the schema, never at the top level — a top-level platform field gets its defaults injected into every other platform's entries.

## Task catalog

Tasks live in `src/main/kotlin/com/gridgain/demo/plugin/tasks/`. Most take `-P<name>=<value>` properties; `dataGenerate`/`dataGeneratorTeardown` use Gradle `--option`s. Most deploy/teardown tasks accept `-PdryRun=true` (render manifests, don't apply) and act on all entries of a type when the name is omitted.

| Task | Purpose | Key params | Blocking? |
|------|---------|-----------|-----------|
| `validateDemoConfiguration` | migrate + JSONSchema-validate the config | — | yes |
| `validateDataModel` | validate data-model files (zones/tables) | `-PclusterName` | yes |
| `deployInfrastructure` / `teardownInfrastructure` | GKE/EKS cluster + node pools, or prepare/reclaim a `hosts` machine set | `-PinfraName` | yes |
| `forceDestroyInfrastructure` | force-remove cloud resources; on `hosts`, sweep every toolkit unit + process from the machines regardless of recorded state. Units are found under all four naming prefixes (`gridgain-`, `gg-prometheus-`, `gg-grafana-`, `gg-otelcol-`) and from **both** `list-units` and `list-unit-files`, since a template unit with no running instance appears only in the second; the install, data, log **and staging** roots all go | `-PinfraName` (required) | yes |
| `deployCluster` / `teardownCluster` | a GG8/GG9 cluster | `-PclusterName` | yes |
| `deployDataModel` | zones/tables/indices into a cluster | `-PclusterName` (required) | yes |
| `deployDatabase` / `teardownDatabase` | Postgres / MariaDB | `-PdatabaseName` | yes |
| `deployCdcConnector` / `teardownCdcConnector` | Kafka + Kafka Connect + Debezium + registered connectors | `-PconnectorName` | yes |
| `deployDataGenerator` / `teardownDataGenerator` | streaming data generator as a first-class element — on k8s a dedicated `wp-<name>` pool + Deployment with placement; on `hosts` the archive + a systemd **template** unit, installed but **not started** | `-PdataGeneratorName` | yes |
| `warmupDataGeneratorPool` | pre-scale a data-generator's `wp-<name>` pool to `max_nodes` via async gcloud resize (UI / pre-demo button) | `-PdataGeneratorName` | yes (returns once gcloud accepts; pool scales in background) |
| `deployProxy` / `teardownProxy` | TCP proxy fronting a cluster or database (stable local address across redeploys) | `-PproxyName` | yes |
| `deploySecrets` / `teardownSecrets` | materialize the `secrets:` entries as k8s Secrets | `-PsecretName` | yes |
| `deployAssembly` / `teardownAssembly` | walk an `assemblies` entry, deploying/tearing down its elements in dependency order | `-PassemblyName` | yes |
| `initDemoConfig` | build a `demo-config.yaml` from `-Pwizard.*` answers — no starter file is read, and the output is comment-annotated. Refuses to overwrite an existing file. | `-PdemoConfigFile`; the four choices `-Pwizard.platform` (`gke`\|`eks`\|`hosts`, comma-separated), `-Pwizard.ggVersion` (`8`\|`9`), `-Pwizard.monitor` (`control-center`\|`prometheus-grafana`\|`none`), `-Pwizard.derivedImages` (`public`\|`skip`\|`build-and-push`) — **all four required**; then `-Pwizard.region`, `-Pwizard.hosts`/`hostArchitecture`/`hostOsFamily`/`hostAuth` for `hosts`, and `-Pwizard.secret.<name>` per secret. Pass the four choices alone and the task reports every remaining value it needs at once. | yes |
| `deployMonitor` / `teardownMonitor` | standalone monitor — Control Center or Prometheus-Grafana on Kubernetes, or Prometheus + Grafana + OTel Collector as systemd units on one machine (`platform: hosts`) | `-PmonitorName` | yes |
| `deployClusterMonitoring` / `teardownClusterMonitoring` | attach a monitor to a cluster | `-PclusterName`, `-PmonitorName` | yes |
| `deployClusterDcr` / `teardownClusterDcr` | DCR bindings between clusters | `-PclusterName`, `-PconnectionName` | yes |
| `takeSnapshot` / `restoreSnapshot` | cluster snapshot / restore | `-PclusterName`, `-PprofileName`, `-PsnapshotType`/`-PsnapshotId` | yes |
| `connectTestClient` | run a test client against a cluster | `-PclusterName`, `-Pmode` (`in-cluster` (default)\|`local`); a `platform: hosts` cluster accepts **`local` only** — there is no namespace to dispatch a Job into | yes |
| `dataGenerate` | run a generator scenario (see §Generator dispatch) | `--scenario` (req), **`--targetCluster` (req, every mode)**, `--ops`, `--data`, `--mode` (`local`\|`in-cluster`\|`hosts`), `--dataGenerator` (**required for `--mode=hosts`**), `--timeout` (in-cluster only), `--instanceIndex`/`--instanceCount` (**both or neither**; the key-space stripe a multi-process run needs) | **depends** |
| `deployMessageBroker` / `teardownMessageBroker` | `-PmessageBrokerName` | yes |
| `dataGeneratorTeardown` | stop a distributed or host generator run, recording an optional end-of-run summary | `-PrunId` / `--runId` (req); optional summary figures are `--`-only (not `-P`): `--achievedRate`, `--totalOps`, `--errorCount`, `--avgLatencyMs`, `--p90LatencyMs`, `--p99LatencyMs` | yes |
| `deleteDataGeneratorRun` | forget a finished run's record in `deployment.yaml` (refuses a live run) | `-PrunId` / `--runId` (req) | yes |
| `startDemoAccess` / `stopDemoAccess` / `refreshDemoAccess` | kubectl port-forward tunnels | — | no (bg) |
| `launchPluginUi` | operator UI (Ktor) | `-PuiPort` | no (server) |
| `bootstrapPublicImages` | seed the **public** images into config — `StandardImages` (GG8, GG9, Control Center backend/frontend) pulled anonymously from `docker.io`. It does **not** seed `data-generator-gg8`/`gg9`; see §Generator images | `-PdemoConfigFile` | yes |
| `clearPluginOutput` | delete generated output + runtime state | — | yes |

*This table reflects the current source — treat the `tasks/` package as authoritative if a task is missing or an option differs.*

**Switching configs inside the UI.** `launchPluginUi` starts with the config file `demoConfigFile`
names, but the operator can switch to another from the nav bar without restarting the server. The
switch re-derives `output_directory` and `runtime_directory` from the newly selected file's `demo:`
section — the same rule the plugin applies (`DemoDirectoryResolver`) — so deployment state and run
history follow the config. Two consequences worth knowing:
- Setting `demoOutputDirectory` or `demoRuntimeDirectory` in `gradle.properties` **pins** that
  directory: it overrides the config file for CLI tasks, so the UI keeps it fixed across a switch
  rather than letting the two disagree. `launchPluginUi` logs which directories are pinned.
- The switch is refused (HTTP 409) while a task is running or a cluster terminal session is open,
  because both write into or read from the directories that are about to move.
- **The UI forwards the active config file to every Gradle subprocess it spawns**
  (`-PdemoConfigFile=<active>`, for `dataGenerate`, `dataGeneratorTeardown` and `connectTestClient`).
  Without it Gradle resolves `demoConfigFile` from `gradle.properties`, which pins one file — so
  after a switch the in-process actions and the subprocesses would be operating on *different
  demos*. If you add another subprocess-dispatched task, pass this flag.

**Run records, summaries, and delete.** `dataGeneratorTeardown` transitions a run to `completed` /
`host-completed` rather than removing it, so the UI can render finished runs. `deleteDataGeneratorRun`
is what finally removes one. It touches `deployment.yaml` and nothing else — run logs, on-host run
directories and Prometheus series all stay — and it refuses a `running` or `host-running` record,
because that record is the only handle on the pods or the systemd unit behind it.

The teardown task's six summary options are optional and normally supplied by the UI, which observes
the run's Kafka metrics feed and merges the per-instance latency histograms the generator publishes
(percentiles do not compose, so it merges rather than averaging). A teardown run from the CLI omits
them and the record stores nulls — the sanctioned "nobody was watching" state, which the run card
reports as an unavailable summary rather than as zeros. Blank values are treated as absent; do not
pass `null` or `n/a` as a placeholder.

**The Load page (`/load`) needs a broker address.** Set `uiKafkaBootstrap=<host:port>` in the demo
project's `gradle.properties`; `launchPluginUi` forwards it as `-Dui.kafka.bootstrap` and logs
whether it is set. It must be reachable **from the machine running the UI** — deliberately *not*
read from the generator's `ops.yaml`, whose `kafka_bootstrap` is resolved from the generator's
vantage point (cluster-internal DNS for an in-cluster run, which the UI cannot dial). Unset simply
means the page reports itself unconfigured; the UI still starts.

## Element types (demo-config.yaml)

Top level is keyed maps. Instances reference templates/accounts by name; the strict layer (Kotlin DTOs) carries **no defaults** — defaults live only in the JSONSchema (UI/documentation). Schema files: `src/main/resources/schema/*.schema.json`.

| Key | Purpose | Variants / notes |
|-----|---------|------------------|
| `infrastructures` (+ `_accounts`, `_templates`) | cloud k8s env, or a set of Linux machines (region, zones) | template platform `gke`/`eks`/`hosts`; account provider `gcp`/`aws`/`host`. On `hosts`, `host_jdk_distribution` is **optional**: empty means no JDK is installed, which is valid only while nothing on those machines needs a JVM — a cluster *or* a `platform: hosts` data generator. Either on a JDK-less infrastructure is rejected at validation, naming the element. Adding a JDK to an infrastructure that had none changes `HostInfrastructurePlugin.preparedMarker` (it folds the JDK identity in with a deliberate `"no-jdk:no-jdk"` literal so the transition is visible), so those machines **re-prepare** and anything already running on them is interrupted. That is supported, not a workaround |
| `hosts` | one pre-existing machine in a `hosts` infrastructure | points **up** at its `infrastructure`; declares `zone`, `architecture`, `os_family`, and **three** addresses — `ssh_address` (how the controller reaches it), `advertised_address` (what a thin client dials), `bind_address` (what the JVM binds). Collapsing them works on a laptop VM and fails on a multi-NIC lab machine |
| `distributions` | archives installed on machines | `type: gridgain` / `jdk` / `prometheus` / `grafana` / `otel-collector` / `data-generator`. The observability three are static Go binaries and need no JVM; `data-generator` is the exception that does, which is why an infrastructure hosting one needs a `host_jdk_distribution` even if it hosts no cluster. `data-generator` additionally requires `gridgain_major_version` (matched against the target cluster's, so a generator cannot be pointed at a cluster its thin client cannot speak to) and `launcher_name` — the script in the archive's `bin/`, invoked rather than reassembled as a `java -cp` line, because the generator's own build bakes the GG8 `--add-opens` flags into it. `otel-collector` additionally requires `binary_name`, because upstream publishes `otelcol`, `otelcol-contrib` and `otelcol-k8s` and only the config knows which was downloaded. Version floors are enforced at assembly, not by the schema (a `pattern` cannot compare 2.9.0 against a 2.47.0 floor): Prometheus ≥ 2.47.0 for the OTLP receiver, Grafana ≥ 9.0.0, collector ≥ 0.90.0. Common to every type: `artifacts` keyed by architecture with a `source` that is a `url` (host pulls), a `file` (controller pushes), or an `image` (controller pulls the named `images` entry, extracts `path_in_image`, pushes the result) — no fallback between them. `sha256` lives **inside** the `source`, not beside it: it is required for `url`/`file` and absent for `image`, whose archive does not exist until the controller builds it, so the checksum is computed after extraction. Verification always happens on the machine after transfer. A missing architecture is an error, never substituted; declare `any` for an arch-independent archive. An `image` source may also carry `exclude: [<relative path>…]` to leave directories out of the built archive — every byte is transferred to every machine |
| `node_pool_templates` | hardware specs | `gke` / `eks` only — a `hosts` infrastructure has no node pools |
| `cluster_templates` → `clusters` | GG cluster (nodes, ports, resources, data_models, telemetry) | GG8/GG9 via image/template on k8s; **GG8 only** on `hosts`, via `host_gridgain_distribution`. On `hosts`: `nodes` must equal the enabled-host count exactly, at most one enabled cluster per infrastructure, `host_modules` must include `ignite-rest-http` and must not include `ignite-kubernetes`, and `host_rest_address` must be declared |
| `databases` | non-GG DB | `postgres` / `mariadb` (image, port, databaseName, authSecretRef, initDdlLocation, resources, storage) |
| `cdc_connectors` | Debezium + Kafka pipeline (source: a `databases`; sink: a `clusters`) | `kafka`, `kafka_connect` (`plugins[]`, `jvm_opts[]`), `debezium`, top-level `connectors[]` (extra Connect registrations w/ `__PLACEHOLDER__`→secret) |
| `secrets` | k8s Secret the toolkit materializes at deploy time, and the payload the `hosts` platform reads on the controller | payload from a pluggable `source` (v1: `kind: sops` — a SOPS-encrypted YAML file + a top-level `path` key). **`source.file` resolves against the demo config's own directory**, like `gridgain8_license_file` and the generator's paths — so with the config at `src/main/resources/demo-config.yaml`, `file: secrets/x.sops.yaml` means `src/main/resources/secrets/x.sops.yaml`, not a `secrets/` at the repo root. Referenced **by name** from the `*_secret_ref` fields below |
| `data_generators` | streaming data generator as a first-class element | Every entry carries a **`platform`** discriminator since v20 (`gke`/`eks`/`hosts`), which must agree with its infrastructure's template — materialised onto the generator rather than followed through the reference because Jackson subtype resolution and the schema's `if`/`then` branches both need a literal property. Common to both: `infrastructure`, `target_cluster` (a name only — the generator resolves addresses itself from `client-endpoints.yaml`), `scenario`, `ops_file`, `data_file`. **k8s** adds a dedicated `wp-<name>` pool with `WorkloadScheduling.forElement` placement: `k8s_namespace`, `k8s_node_pool_template`, `num_nodes`/`min_nodes`/`max_nodes`, `replicas` (0 = staged), `max_replicas`, `per_pod_rate` (0 = unbounded), `pod_resources`, `timeouts.deployment`. **`hosts`** adds `host_distribution` (a `type: data-generator` archive) + `host_timeouts.unit_active`, and carries **none** of the pod/node-pool fields — they describe a horizontally scaled set of containers and an autoscaler beneath them, and a host generator is one JVM under systemd. They are absent rather than defaulted, so a misplaced one is reported as the mistake it is |
| `monitors` | observability | `control-center` / `prometheus-grafana`. Every entry carries a **`platform`** discriminator since v19 (`gke`/`eks`/`hosts`), which must agree with its infrastructure's template. `control-center` is constrained to the two Kubernetes platforms — there is no host Control Center; a host cluster reaches one via `host_control_center_url`. `prometheus-grafana` on `hosts` takes `host_prometheus`, `host_grafana`, `host_otel_collector`, `host_storage` and `host_timeouts`; the Kubernetes branch keeps `num_nodes`/`min_nodes`/`max_nodes` and the `k8s_*` fields, which moved out of the top level at v19 because they are node-pool concepts a machine set has nothing to do with |
| `connector_templates` | cluster sidecars / agents | `cloud-connector` (CC) / `otel-collector` (Prom/Grafana) / `ignite-agent` |
| `dcr_templates` → `dcr_connections` | replication | `gg8` (push) / `gg9` (pull) |
| `image_registries` → `images` | container images by name | referenced by templates/databases/connectors |
| `proxies` | TCP forwarder giving a cluster/database a stable local address | `listeners[]` name a target kind + service; `startDemoAccess` port-forwards through it |
| `assemblies` | an ordered set of elements deployed/torn down together | `deployAssembly` walks it and reports config-drift skips at end-of-run |
| data model (`data_models` files) | zones + tables | `affinity_key` (PK column) → GG8 `WITH "AFFINITY_KEY"` / GG9 `COLOCATE BY`; zone `replicas` → GG8 `BACKUPS=replicas-1` |

**Secret references must resolve.** Every `databases.<n>.auth_secret_ref`,
`cdc_connectors.<n>.debezium.replication_user_secret_ref`,
`cdc_connectors.<n>.connectors[].secrets.<placeholder>.secret_ref`, and any
`cluster_templates.<n>.extra_volumes[].secret` that is set must name an entry under the
top-level `secrets:` section. Referencing a Kubernetes Secret created outside the toolkit is
**not** supported and fails validation with the list of declared secrets
(`SecretReferenceValidator.kt`). The one deliberate exception is
`image_registries.<n>.auth.pull_secret_name`, which is Mode A of the registry auth model — an
externally created, user-owned Secret. In the UI these fields render as dropdowns over the
`secrets:` section, driven by the `x-source-section` JSONSchema annotation.

**Schema versioning:** `CURRENT_SCHEMA_VERSION` lives in `ConfiguredState.kt` (currently **21** — v21 added an optional `message_brokers` section, rewriting no values. v20 made `platform` required on every `data_generators` entry, derived from its infrastructure, and split the entry into `K8s` and `Host` variants. v19 did the same for `monitors` and moved the Kubernetes-only fields of a `prometheus-grafana` monitor into its platform branch. v18 added `hosts`/`distributions` and did the same for `clusters`). Breaking config changes bump it + add a `MigrateVNtoVN+1` in `ConfigMigration.kt`'s runner list + update JSONSchema + add a `ConfigMigrationTest` case. Configs auto-migrate forward before validation.

⚠️ **Migration rewrites the user's config file in place through SnakeYAML, which discards every comment in it.** Back the file up before running any task against a config below `CURRENT_SCHEMA_VERSION`, and be aware that a hand-maintained (especially gitignored) config loses its entire rationale on first migration. Hand-bumping `schema_version` is equivalent *only* when the config already states everything the migration would inject.

`deployment.yaml` (runtime state) has its own `schemaVersion` with **no** migration — mismatch means tear down + redeploy. It is at **11**: v11 moved the pod and node-pool fields into `K8sDataGeneratorBaseSpec`, which changes `GkeDataGeneratorSpec`'s persisted shape non-additively (the fields are required and non-null, so a record written at 10 fails partway through loading). v10 did the same for a Prometheus & Grafana monitor's node counts. The gate fires with its tear-down message rather than letting a stale record fail deserialization with a generic error.

## Message brokers (`message_brokers`)

A Kafka broker the toolkit deploys, so a demo has a bus that outlives any one element. It exists for
the data generator's live-metrics feed and the UI Load page's rate control: the generator publishes
throughput/latency snapshots to it and consumes rate commands from it, which is what lets the page
drive a run wherever that run happens to be.

- **Hosts platform only.** `deployMessageBroker -PmessageBrokerName=<name>` installs the archive,
  places `server.properties`, formats KRaft storage, opens the listen port and starts the unit
  `gridgain-kafka-<name>`. Kubernetes already has a broker inside `cdc_connectors`; a standalone k8s
  variant would add its own `if`/`then` branch beside the hosts one.
- **The host is named, not inferred** — unlike a host data generator, which takes its
  infrastructure's single machine. A broker's address is baked into every producer and consumer
  configured against it, so placement must not shift with host ordering.
- **Single-node KRaft, and `auto.create.topics.enable=true` is required rather than convenient.** The
  generator's metrics sink is fire-and-forget (`acks=0`) and would silently drop every snapshot
  against a missing topic.
- **The archive comes from `images`, not a URL.** A `distributions` entry with `type: kafka` and a
  `kind: image` source extracting `/opt/kafka`. That payload is jars and shell scripts, so one `any`
  artifact serves every architecture — no ppc64le build to chase, unlike the JDK. An image source
  declares no checksum, because the archive does not exist until the controller builds it.
- **Two Kafka addresses, deliberately different.** `ops.yaml`'s `kafka_bootstrap` is the
  *generator's* vantage point; `uiKafkaBootstrap` in `gradle.properties` is the *UI's*. Never derive
  one from the other — an in-cluster generator's address is cluster-internal DNS a laptop cannot dial.
- **`control:` needs ops schema_version 5.** A generator archive built before v5 rejects it outright,
  so the rate slider requires a redeployed dist; `metrics:` alone is a v4 feature.

## The `hosts` platform

Deploys GG8 to pre-existing Linux machines over ssh, supervised by systemd. First target is IBM Power
(ppc64le, RHEL family), but nothing is hardcoded to it — architecture and OS family are **declared per
host and verified against what the machine reports**, so the same path runs on any architecture.

**Ownership split.** The infrastructure owns the machine: service identity, directory tree, OS tuning,
firewall ports, and the **JDK** (shared between clusters). The cluster owns the **GridGain distribution**
(a per-cluster choice), its config, licence, env file, systemd unit and start. So a second cluster on the
same machines reuses the JDK but installs its own distribution.

**"Deployed" means prepared, not reachable.** Machines always answer a ping; preparation does not. So
`deployInfrastructure` reports the infrastructure absent until a marker written *last* by the creation
stage is present on every machine, and `assessClusterAdequacy` is the real gate — it compares observed
architecture, free disk and installed JDK against the configuration and reports every mismatch at once.

**On-machine layout** (every root config-supplied):
`<installRoot>/{jdk/current→<version>, <cluster>/dist/current→<version>, <cluster>/conf, <cluster>/state}`,
`<dataRoot>/<cluster>/{work,storage,wal,walarchive}`, `<logRoot>/<cluster>`. Versioned directory plus a
`current` symlink, so an upgrade is a swap and a restart with no re-download.

**Readiness ladder** (ordering is load-bearing): systemd `ActiveState`/`NRestarts` (liveness + crash-loop
— `Type=simple` reports active on fork, so this alone is insufficient) → `control.sh --state` run **on the
machine against 127.0.0.1** (sidesteps every firewall question a controller-side probe would face) →
topology count via the REST endpoint → **then** activation, and only with persistence enabled. Activation
must come last because the first activation of a persistent cluster fixes the baseline to the topology
present at that moment; a node joining later runs outside it, degraded and silent.

**Teardown.** Cluster: stop (a clean SIGTERM checkpoints the WAL — never deactivate first), remove the
unit, remove conf + licence + toolkit state. Data goes only per `host_storage.retain_on_cluster_destroy`;
logs always stay; the JDK and distribution stay so a redeploy does not re-fetch them. Infrastructure:
reverts tuning and firewall, removes the roots, then the service identity — and refuses outright while any
cluster is still recorded on those machines.

**OS tuning is reversible by construction.** Every artifact is a uniquely named drop-in file the toolkit
owns (`/etc/sysctl.d/99-gridgain-<infra>.conf`, `/etc/security/limits.d/99-gridgain-<infra>.conf`, a
one-shot `gridgain-thp-<infra>.service`); shared system files are never edited, so reversal is deletion
plus a re-read with no save/restore bookkeeping. The one exception is the runtime transparent-hugepage
mode — a `/sys` write with no drop-in equivalent — recorded to `state/thp.prev` on apply and put back on
revert. Tuning is **infrastructure**-scoped, because sysctl values are machine-global.

**Authentication.** `host_access.auth` is a `key`|`password` union. A key is what the transport was built for: `BatchMode=yes` guarantees ssh can never prompt. `password` names a `secrets` entry and its key; the value is read on the controller at run time, handed to ssh through an `SSH_ASKPASS` helper (so it never appears in a command line), carried in the process environment, and redacted from the run log. Password mode necessarily drops `BatchMode` and sets `PubkeyAuthentication=no` + `NumberOfPasswordPrompts=1`. Needs OpenSSH ≥ 8.4 for `SSH_ASKPASS_REQUIRE=force`. Prefer a key where you can install one — a password is strictly more exposure.

**The JDK is checked before it is installed.** `ensure-jdk.sh` searches `host_jdk_search_paths` in order and reuses the first JDK whose *reported* `java.specification.version` and `os.arch` match, installing `host_jdk_distribution` only when none does. Suitability is the machine's answer, not a package name's — a `java-17` RPM can be a different major after an upgrade. `<installRoot>/jdk/current` is a symlink pointing at whichever won, so nothing downstream knows the difference.

**Observability on a machine.** A `prometheus-grafana` monitor with `platform: hosts` installs three
static Go binaries as systemd units on **exactly one** machine: Prometheus, Grafana, and an
OpenTelemetry Collector. The collector belongs to the monitor rather than to each cluster, unlike the
Kubernetes path's per-cluster sidecar — a host GG8 node exports OTLP from its own JVM and there is no
pod to attach a sidecar to, so one collector serves every node. It also bridges a real gap:
Prometheus's OTLP receiver speaks HTTP only while the node's exporter is configured for gRPC.

The flow is *node → collector (OTLP/gRPC) → Prometheus (OTLP/HTTP over loopback) → Grafana (loopback)*.
Only Grafana's `root_url` uses the machine's advertised address; everything internal uses `127.0.0.1`,
so no internal hop depends on lab routing or a firewall opening. Wiring a cluster to it is one field:
`host_otel_endpoint: http://<advertised>:<grpc_listen_port>` on the **cluster template**, which
`deployMonitor` prints as the exact lines to paste.

**Readiness is two rungs per component**, and stops there — a cluster's third rung (topology, then
activation) has no equivalent, because a Prometheus answering `/-/ready` is serving. Rung one is
systemd `ActiveState`/`NRestarts`; rung two is `http-ready.sh` on the machine against 127.0.0.1
(`/-/ready`, `/api/health` matching `"database": "ok"`, and the collector's `health_check` extension).
Both **poll**. Grafana's body match is not decoration: it answers 200 while its database migration is
still running.

**Teardown** stops in reverse order, always removes configuration (grafana.ini holds the admin
password) and always keeps the installed archives and the logs. Data goes only per
`host_storage.retain_on_destroy`.

**The data generator on a machine.** A `platform: hosts` `data_generators` entry installs its
`type: data-generator` archive and a systemd template unit on the infrastructure's machine, and runs as a
single JVM — no pods, no replicas, no autoscaler. It is the one host element that is a JVM application
rather than a Go binary, so its infrastructure needs a `host_jdk_distribution` even when it hosts no
cluster. Put it on a machine that is *not* a data node: it is a client, and co-locating it has it
competing with the thing it is meant to load. `host_distribution` sits on the generator rather than the
infrastructure (unlike `host_jdk_distribution`) because a JDK is shared by everything on a machine set
whereas a generator archive is pinned to one GridGain major version — an infrastructure hosting a GG8 and
a GG9 generator would need two. See **Generator dispatch** below for the deploy/run/teardown split.

**Endpoints.** `client-endpoints.yaml` is at `schema_version: 2` with a required `deployment_kind`
(`k8s`|`hosts`). A hosts entry has **no** `namespace` and no `in_cluster` context — its addresses go under
`local`, built from each host's `advertised_address`. `host_rest_address` is declared, never derived from
the host list. This file is the contract with `gridgain-demo-client-utils`, versioned in lock-step — and
the consumer is concretely `client-finder-common`'s `ClientEndpointsLoader` (which holds
`EXPECTED_SCHEMA_VERSION = 2` and throws `SchemaVersionMismatchException` on anything else) feeding
`AddressResolution`. Named here because confirming it once cost a whole session: the published jar can lag
the source by days, so when a contract spans repos, **check the artifact, not just the code**.

## Generator dispatch (`dataGenerate`)

The plugin runs the data generator from `ops.yaml`/`data.yaml` (see the `gridgain-demo-data-generator` skill for those files) in one of **three modes**, `--mode=local` / `in-cluster` / `hosts`.

**`--mode=hosts` additionally requires `--dataGenerator=<name>`**, and it is the only mode that does:

```bash
./gradlew deployDataGenerator -PdataGeneratorName=<name>      # installs; starts nothing
./gradlew dataGenerate --scenario <scenario> --targetCluster=<cluster> --mode=hosts --dataGenerator=<name>
./gradlew dataGeneratorTeardown --runId=<runId>               # stops the run
./gradlew teardownDataGenerator -PdataGeneratorName=<name>    # removes the install
```

**All three modes are drivable from the UI's Load page (`/load`)**, which shows a Generator picker
when `hosts` is selected (filtered to deployed `host-data-generator` elements) and refuses to launch
without one. The generic Tasks-page launcher still offers only `local`/`in-cluster`: its form renders
required params, and `--dataGenerator` is required *conditionally*, which that form cannot express.
`--targetCluster` is different — required in *every* mode, so the generic form can and does render it.

⚠️ **Four different spellings, and none is a typo.** `deployDataGenerator` / `teardownDataGenerator` / `warmupDataGeneratorPool` take the project property **`-PdataGeneratorName`** (`GridGainDemoPlugin.kt:410`); `dataGenerate` takes the Gradle option **`--dataGenerator`**; the cluster is **`--targetCluster`** as a Gradle option but reaches the generator as **`--target-cluster`**; and the key-space stripe is **`--instanceIndex` / `--instanceCount`** as Gradle options but reaches the generator as **`--instance-index` / `--instance-count`**. The camelCase→kebab split in the last two is the same rule both times: the Gradle option is the toolkit's, the kebab flag is the generator's own CLI. `InstanceStripe` holds all four spellings as constants and is the only place that translates — do not restate either form at a launch site. `dataGeneratorTeardown` is keyed on the run, not the element: `--runId` / `-PrunId` only.

⚠️ **A multi-process load test needs `--instanceIndex` / `--instanceCount`.** Nothing else divides the
key space outside Kubernetes distributed mode. Launch N generators without them and every one starts
each `sequence` value source at `start`, so they all write the *same* keys and contend on the same
entries and partitions instead of doing N times the work.

```bash
# four generators on one machine, dividing one key space
for i in 0 1 2 3; do
  ./gradlew dataGenerate --scenario load --targetCluster=power-payments \
    --mode=hosts --dataGenerator=payments-load --instanceIndex=$i --instanceCount=4
done
```

- **Both or neither**, and the index must be unique per process. One option without the other is
  refused naming both, as are a non-integer, a count below 1, and an index outside `0..n-1`. Nothing
  checks that a fleet used each index exactly once — two runs sharing an index write the same keys.
- **Refused for a distributed (`distribution:`) in-cluster run**, at plan time, before any manifest is
  written. That path runs under the generator's Coordinator, which partitions the key space from
  `partition_count`; a CLI stripe would be a second, disagreeing answer. The generator refuses the
  combination too, but there the failure is every pod crash-looping with the reason in its log.
- **The symptom of getting this wrong is not an error.** Measured on real hardware: 32 unstriped host
  processes against a 2-node GG8 cluster settled at 93 ops/s and 498 ms with **zero errors**, idle CPU
  on both hosts, server pools at `active=0, qSize=0` — and 50M+ operations left 383 MB of data. See the
  generator skill's gotcha 11.
- **`--mode=hosts` needs the unit re-installed after upgrading the plugin.** The stripe rides in the
  per-run `run.env` as `INSTANCE_ARGS` and the unit reads it as `$INSTANCE_ARGS` — unbraced, so systemd
  word-splits it into two flags or none. A unit installed by an older `deployDataGenerator` has no such
  line, so it would ignore the variable silently: `teardownDataGenerator` + `deployDataGenerator` before
  relying on the flags.

**Every mode names its cluster.** Since ops schema v7 removed `ops.yaml`'s `targets:` block, `--targetCluster` is required in all three modes and is the only thing that says which cluster a run writes to. The GridGain flavour is derived from it (`TargetResolution.resolveTarget`, which reads `ConfigurationQueries`, **not** ops.yaml), so the classpath, image or archive follows the cluster you name rather than a field in the ops file. A host run additionally needs *which machine* and *which installed archive*, which only the `data_generators` entry says — hence `--dataGenerator` on top.

**Deploy installs, the run starts** — and that split is what makes the deploy idempotent. `deployDataGenerator` puts the archive and a systemd **template** unit in place; `dataGenerate` starts an instance; `dataGeneratorTeardown` stops it. Consequences worth knowing:

- **The unit is `gridgain-datagen-<name>@`, not `gridgain-datagen@`.** The element name is in the filename deliberately: two generators on one machine would otherwise install the same template unit at the same path with different rendered contents, and the second deploy would silently overwrite the first.
- **Deploy readiness is `systemctl cat`, not `systemctl is-active`.** A template unit has no instance until a run starts one, so `is-active` reports `inactive` on a perfectly good install — and the generator binds no socket anywhere, so there is nothing to probe either.
- **Host run state is three distinct variants** — `HostRunning`/`HostFailed`/`HostCompleted` — not the k8s records with nullables. A host run has no namespace, replica count or image; those are questions that do not apply. A `DataGeneratorRunRecord` interface carries what all six share. (The UI's run card renders them already but still shows namespace/replicas; host name and unit instance are what it should show.)
- **The run's choices arrive in a per-run `run.env`, not in the unit.** `ExecStart` is rendered at *deploy* time and `%i` (the runId) is its only run-time variable, so `--target-cluster` and `--scenario` could not be baked in. `dataGenerate` writes `<runs_root>/<runId>/run.env` carrying `TARGET_CLUSTER=`, `SCENARIO=` and `INSTANCE_ARGS=`, and the unit reads it with `EnvironmentFile=` — deliberately **without** a leading `-`, so a missing file fails the start rather than launching with an empty cluster. Ordering is load-bearing: the file is pushed after the run-directory script and before `systemctl start`, because systemd opens it at start.
  - ⚠️ **`$INSTANCE_ARGS` is unbraced in `ExecStart`; the other two are braced, and both forms are deliberate.** systemd splits `$VAR` at whitespace into *zero or more* arguments and passes `${VAR}` as exactly one. The stripe is an optional *pair* of flags and `ExecStart` cannot include a flag conditionally, so it needs the splitting form — `${INSTANCE_ARGS}` would hand the generator `"--instance-index 0 --instance-count 4"` as a single token, and an empty one as a single empty argument. A cluster or scenario name is one value, so those stay braced. `INSTANCE_ARGS=` is written on every run, empty when the run owns the whole key space.
  - ⚠️ It is installed with a direct `install` argv, **not** through `place-config.sh`. That script does `install -d -o root -g root` on its destination's parent, which would chown the run's own output directory away from the service user — the generator would then fail every write while systemd reported the unit `active`. Same trap as the `install -d` gotcha below; do not "simplify" this back onto the shared helper.
  - Before this existed, the unit baked `--scenario` from the *element's* `scenario` field while the run pushed its own `ops.yaml`, so `--scenario X` ran whatever the element declared — and `deployment.yaml` recorded X regardless. Fixed; noted because a pre-fix archive still behaves that way.

Key behaviors that bite on the Kubernetes modes:

- ⚠️ **ops v7 invalidates every deployed generator archive and image.** A pre-v7 archive refuses a v7 ops file outright ("only supports up to schema_version 6"); a v7 archive refuses to start without `--target-cluster`. So upgrading the generator is not a config-only change — `teardownDataGenerator` + `deployDataGenerator` every element, and for the Kubernetes modes check the `data-generator-gg<N>` image's pull policy, or a pod caches the old jar and runs it against a new ops file. See the generator skill for the file-side detail.
- **No rate-override *property*.** `dataGenerate` has **no** `-Prate`/`-Preplicas` flag — the starting rate comes only from the ops file. To change the *starting* rate, write a runtime ops.yaml (override `rate.ops_per_second`, inject `distribution:`) and pass `--ops=<that file>`.
- **To change rate *while a run is in flight*, use the control channel, not a relaunch.** If the scenario's ops.yaml declares a `control:` block, the UI's **Load** page (`/load`) sets the fleet's rate live over Kafka — no restart, no new runId. See the generator skill §Runtime control.
- **Single-Job vs distributed:**
  - No `distribution:` block → one k8s **Job**; the task **BLOCKS** until the Job completes (the gradle invocation is long-lived).
  - With a `distribution:` block → a k8s **Deployment** of N pods; the task is **fire-and-forget** (returns once the Deployment is Ready). Stop it explicitly.
- **Rate is per-pod, not divided** — total ≈ `ops_per_second × replicas` (see the generator skill). Pre-divide if you want a total target.
- **Teardown:** distributed runs → `dataGeneratorTeardown -PrunId=<id>` (deletes by name; runId is printed by `dataGenerate`). Alternatively delete by label: `kubectl delete deployment,configmap,serviceaccount,role,rolebinding -l gridgain.com/scenario=<scenario> -n <cluster-namespace>` — wipes the current run **and any orphans**. Single-Job runs self-clean on success.
- **Manifest labels** (for selectors): `app.kubernetes.io/name=gridgain-demo-data-generator`, `gridgain.com/scenario=<scenario>`, `gridgain.com/run-id=<runId>` (distributed also `gridgain.com/distributed=true`); namespace = the target cluster's namespace.
- **Every launch path passes `--run-group`** (required by the generator). The plugin's runId is the group for a `dataGenerate` run — single-pod Job, distributed Deployment, local fork and the systemd unit (`%i`) all use it, so a fleet's live metrics aggregate correctly and one control command reaches all of it. The long-lived **element** Deployment is the exception: it has no runId, so its group is `element-<name>`, stable across scaling.

## Generator images (`in-cluster` only)

The two Kubernetes modes run the generator from `images.data-generator-gg8` / `-gg9`, resolved by
`DataGeneratorImageResolver`. The `hosts` mode uses an archive instead and needs none of this.

⚠️ **`bootstrapPublicImages` does not create these entries, despite what older error text said.**
That task seeds `StandardImages` only — GridGain 8/9 and Control Center — pulled anonymously from
`docker.io`. A generator image is **derived**: there is no public copy, so it must be *built* from a
`gridgain-demo-data-generator` checkout and *pushed* to a registry you can write to. Running
`bootstrapPublicImages` and expecting `data-generator-gg8` to appear is a dead end.

**What actually produces them** is `PublishStandardImagesAction` — the demo UI's image-bootstrap
wizard — which walks: choose a writable registry → plugin pushes the GridGain images → a
`gridgain-demo-data-generator` subprocess runs its `publishStandardImages` aggregate task → the
resulting `images` entries are persisted into `demo-config.yaml`. Each step aborts if the previous
one fails. Underneath, the generator's own `buildDataGeneratorImages` drives jib per flavour.

**So the registry and tag in those entries are whatever that push chose, and bear no relation to the
generator project's version.** In one working demo they are `pull_from: david-personal-ghcr` with
`tag: 0.5.1-SNAPSHOT` while the generator built a different version entirely — not a
misconfiguration, just the wizard having pushed to a personal registry under its own tag. Do not
"fix" such a mismatch by aligning it to the project version; the tag has to match what is actually
in the registry.

Since 2026-09-02 the generator shares the toolkit's release version (`0.7.0-SNAPSHOT`), so its
*default* jib tag — `imageTag` falls back to `project.version` — now coincides with the plugin
version. That makes an unoverridden hand-built image line up with the plugin by default, but it
changes nothing about the rule above: an entry written by the wizard still records the tag that was
actually pushed, and that is the one to trust.

Building by hand instead of through the wizard means overriding both, plus credentials:

```bash
./gradlew buildDataGeneratorImages \
  -PimageRegistry=<host>/<org> -PimageTag=<tag> \
  -PgridgainGhcrUsername=<user> -PgridgainGhcrPassword=<token>
```

`imageRegistry` defaults to `ghcr.io/gridgain-demos` and `imageTag` to the generator's project
version, so omitting them publishes somewhere your `demo-config.yaml` is probably not pointing.
Whatever you choose must then match the `images` entries, and `pull_policy: Always` is what makes a
re-pushed tag actually take effect on the next run.

**`test-client-gg8` / `-gg9` are derived in exactly the same way** — the wizard's `DerivedImage`
list covers both them and the two generator images. So `connectTestClient --mode=in-cluster` has the
same prerequisite, and the same "bootstrapPublicImages will not create this" caveat applies. The
authoritative list of what *is* public is `src/main/resources/standard-images.yaml`: GridGain
Ultimate, GridGain 9, Control Center backend/frontend, and Kafka. Anything not in that file has to
be built and pushed.

## Config-drift detection on redeploy

Each per-element `Deploy*Action` records a SHA-256 fingerprint of its
`demo-config.yaml` block (the YAML node at `<kind>.<name>`, canonicalised so
key order/whitespace/comments are ignored) into the matching `Deployed*`
record's `config_hash` field. On the next deploy, the action compares the
current fingerprint to the recorded one:

- **Match** (or no recorded hash yet) → action proceeds normally and stamps
  the current hash on success.
- **Mismatch** → action logs a warning and **skips the element**. The
  deployment.yaml record stays as-is. The walker (`deployAssembly`) appends
  the skip to `ctx.configDriftSkipped` and prints a summary at end-of-run
  listing every skipped element with its recorded vs current hash and the
  remediation: `teardownX` + `deployX`, or rerun with `-PforceRedeploy=true`.

**Scope of the hash.** Only the literal block under `<kind>.<name>`. Edits
elsewhere in `demo-config.yaml` (other elements, template definitions,
account credentials) do **not** flag this element. Template-ref drift is
intentionally out of scope (a referenced `cluster_template` change does
not propagate). Hash sources:

- `infrastructures`, `clusters`, `monitors`, `databases`, `cdc_connectors`,
  `data_generators`, `proxies` — all wired.
- `data_model`, `cluster_monitoring`, `cluster_dcr` — not wired (bindings
  with no top-level demo-config block of their own).

**`-PforceRedeploy=true`** bypasses the check on a deploy task. Use it when
you've reviewed the config change and intentionally want to re-apply
manifests on top of the running deployment. On success the recorded hash
is overwritten with the current one.

**Back-compat.** Pre-existing `deployment.yaml` records without
`config_hash` decode with `configHash = null` (treated as "no record" — the
action proceeds and stamps on first re-deploy under the new plugin). No
schema_version bump.

## Gotchas (verified)

- **A host element can report success at every step and be completely broken.** Two defects in the host
  data generator did exactly that, and only `run.log` on the machine showed either. Both are a class,
  not a pair of one-offs: (1) `place-config.sh` given a blank marker argument does
  `install -d "$(dirname "$marker")"` then `: > "$marker"`, failing with `: No such file or directory`
  and naming none of its six arguments; (2) **`install -d` resets ownership on a directory that already
  exists**, so `install -d -o root -g root` under a path `ensure-datagen-dirs.sh` had correctly created
  as the service user undid it — and the generator then failed every write with "Permission denied"
  *while systemd reported the unit active and every deploy step reported success*. When a host element
  "deploys fine" but does nothing, read the element's own log on the machine before trusting any
  controller-side status.
- **Migration rewrites the config file and drops every comment.** See §Schema versioning. Back up a
  hand-maintained config before running any task against it below `CURRENT_SCHEMA_VERSION`.
- **The generator's CLI reports a missing argument as a raw stacktrace** —
  `NoSuchElementException: Key --data is missing in the map` at `CliArgs.kt:33`. It is the first thing
  you see after a typo in a systemd unit's `ExecStart`, and it names neither the unit nor the option.
- **`distTar` produces an uncompressed `.tar`, which `ArchiveFormat` rejects.** Configure GZIP in the
  generator's dist build, or the archive builds cleanly and is refused on the machine.
- **`hosts` monitor: exactly one machine.** Two would need a federation or remote-write story that
  does not exist, so it is refused rather than silently using the first. And the monitor's machine
  cannot also be a cluster's machine: a host cluster requires `nodes` to equal the enabled-host count
  exactly, so a monitor host added to a cluster's infrastructure breaks that cluster.
- **`hosts` monitor: Grafana publishes no ppc64le build.** That alone decides which machine in a Power
  lab can host the monitor. Prometheus and the collector do publish ppc64le; Grafana does not.
- **Grafana 11 takes `--homepath` and `--config` *after* the `server` subcommand.** Only `--help` and
  `--version` are global. Ordered the other way it exits 1 on every start with "flag provided but not
  defined: -homepath", and systemd shows a crash loop with no hint at the cause.
- **Grafana's database outlives a redeploy, and several settings are only read when it is created.**
  `admin_password` is one: rotating the secret and redeploying does *not* change the login. A
  provisioned datasource's `uid` is another — Grafana will update a datasource by name but not
  re-assign its uid, so a datasource created before a uid was pinned keeps the generated one and every
  dashboard referencing the pinned value breaks. Both need `teardownMonitor` first, which with
  `retain_on_destroy: false` rebuilds the database from config. Note that teardown also wipes the
  Prometheus TSDB, so recent metrics go with it; they repopulate at the exporter's period.
- **Delivering OTLP straight to Prometheus skips the translation the Kubernetes path gets for free.**
  There, the collector's Prometheus exporter underscores metric names and promotes resource
  attributes to labels. The host path exports to Prometheus's OTLP receiver instead, which by default
  stores GridGain's dotted names verbatim (`cache.ignite-sys-cache.CacheGets` — not even a legal bare
  PromQL selector) and leaves the node's identity in `job`/`instance`. The bundled dashboards ask for
  `cache_ignite_sys_cache_CacheGets` and group by `service_instance_id`, so metrics arrive, Prometheus
  is healthy, the datasource resolves — and every panel is empty. `prometheus.yml` therefore sets
  `otlp.translation_strategy: UnderscoreEscapingWithSuffixes` and promotes `service.instance.id`,
  `service.name` and `service.namespace`. Both must stay in step with what the dashboards query.
- **Bundled dashboards carry `${DS_PROMETHEUS}`, an import-time placeholder.** Grafana substitutes it
  when a dashboard is imported through the UI and *not* when it is file-provisioned, so a verbatim
  copy leaves every panel pointing at a datasource that does not exist. Both platforms rewrite it to
  the provisioned datasource's uid when writing the dashboard out; the uid is pinned to `prometheus`
  in the datasource provisioning and the two must stay in step.
- **The collector's `health_check` extension must appear under both `extensions:` and
  `service.extensions:`.** Listed in only one it silently does not start, and the readiness probe
  waits out its whole timeout with nothing to report.
- **`host_manage_firewall` is a property of the machine, not of the lab.** Copying it between
  templates is how a monitor ends up bound correctly, answering on loopback, passing every readiness
  gate, and refused from everywhere else — because readiness deliberately probes 127.0.0.1 *on the
  machine* and cannot see a closed firewall. Check `systemctl is-active firewalld` on the actual host.
- **A no-strip archive can dictate its install directory's mode.** `tar` applies the mode of the
  archive's `./` entry to the directory it extracts into, so an archive built from a private directory
  produces an install the service user cannot enter — reported by systemd as `200/CHDIR`. The install
  script re-asserts 0755 afterwards; `--strip-components=1` discards that entry, which is why only the
  no-strip path was ever exposed.
- **Setting `host_otel_endpoint` changes the delivered archive.** It derives `ignite-opentelemetry`
  into the module list, and that list decides what is shipped — so the next cluster deploy reinstalls
  the distribution. A *running* node does not pick the exporter up at all: it is wired into
  `ignite-node-cfg.xml` at node start, so this needs `teardownCluster` + `deployCluster`.
- A generator run at the ops.yaml default rate on a single pod barely taxes GG — scale **pods** (`distribution.replicas`) to saturate, and divide the rate accordingly.
- `transaction_scope: business_event` against the default ATOMIC SQL caches rolls back every write (GG8 8.9+) — see the generator skill.
- CDC connector names are `<cdc_connectors-entry>-<connectors[].name>` (e.g. entry `mainframe-to-gg` + `cdc-sink` → `mainframe-to-gg-cdc-sink`), not the bare inner name.
- **`hosts`: `OPTION_LIBS` does not exist.** It is a feature of the GridGain *Docker image's* entrypoint. In a tarball an optional module must be physically copied out of `libs/optional/<module>` into `libs/`, which is what `host_modules` drives. A module the config forgets shows up as a `ClassNotFoundException` at node start.
- **GKE needs three GCP APIs enabled, and enabling them is itself a permission.** `container`, `compute` and `iam` `.googleapis.com` — all three; `container` alone gets a project far enough to look right and not far enough to build anything. Beware `containeranalysis.googleapis.com`, which is a different service and reads almost identically. `gcloud services enable <api> --project=<p>` answering `PERMISSION_DENIED ... serviceusage.services.enable` means the account can list services but not enable them: that needs `roles/serviceusage.serviceUsageAdmin` (or Owner/Editor) from an administrator. The wizard checks all three on the project before the interview ends; `GcpRequiredApis` is the one list both it and the deploy-time step read.
- **k8s GG8: metric export is gated on the image tag, at 8.9.33.** The exporter bean's class lives in `ignite-opentelemetry`, which first ships in that version. The node configuration renders the `metricExporterSpi` bean *and* names the module in `OPTION_LIBS` only when the cluster image is 8.9.33 or later, so an older pin costs metrics rather than the cluster — naming a module the image does not carry used to kill every node before the grid started, on any monitor choice including none. Binding such a cluster to a `prometheus-grafana` monitor is still refused at validation, with both versions in the message. `standard-images.yaml` defaults above the floor and `StandardImagesTest` holds it there.
- **`hosts`: do not copy the k8s JVM options.** The Kubernetes path sets `-XX:+UseG1GC`; IBM Semeru runs OpenJ9, which rejects it outright and refuses to start. `host_jvm_opts` deliberately specifies no GC flag. Deployment log diagnostics recognise `Unrecognized VM option` and say so.
- **`hosts`: a two-site DCR demo needs two infrastructures.** `nodes` must equal the enabled-host count exactly and at most one enabled cluster may occupy an infrastructure, so six machines become two infrastructures of three rather than one of six.
- **`hosts`: an `image` source needs a container runtime on the *controller*, never on the machines.** The toolkit pulls and extracts locally, then pushes — the machines are never given a runtime. **Either `docker` or `podman`** satisfies it (podman is argument-compatible for the pull-and-extract calls; the candidates and their preference order live in `tooling/hosts_tool_requirements.yaml` under `any_of_commands`, and `ContainerRuntimes.preferred()` picks whichever works). A demo whose distributions are all files or URLs needs none at all.
- **`hosts`: the delivered archive is a *subset* of the distribution, not a copy of it.** `libs/optional`
  is reduced to exactly the modules `host_modules` names, which is why that list matters beyond activation:
  it decides what is shipped. Measured on GridGain Ultimate, that is 1134 MB down to 76 — `libs/optional`
  alone is 89% of the tree and one module, `gridgain-bulkload`, is 856 MB. Consequences: a module named in
  the config but absent from the image fails on the controller (naming `host_modules`) rather than on the
  machine; adding a module changes the archive, so the install detects it and reinstalls; and a module
  cannot be activated by hand on a machine, because it was never delivered. Anything else unwanted goes in
  the source's `exclude`, stated rather than inferred.
- **`hosts`: `host_artifact_distribution` decides how archives reach the machines.** `kind: controller`
  (the default, and what an omitted block means) pushes to each machine in turn. `kind: seed` names one
  machine with `seed_host`, pushes once, and has the rest fetch from it over the local network via the same
  curl-and-checksum path a `url` source uses — reusing `serve_port` (default 18080) and
  `serve_timeout_seconds`. Rejected at validation: a seed host that is disabled, belongs to another
  infrastructure, or does not exist; and seeding a single-machine estate. A seeded JDK on a
  mixed-architecture estate is refused too, since one archive cannot serve two architectures. Needs
  `python3` on the machines and, when `host_manage_firewall` is true, opens the serve port for the transfer
  and closes it after.
- **`hosts`: GridGain 8's server distribution is architecture-independent**, so an archive extracted from an amd64 image runs on ppc64le; declare it under `artifacts.any`. A JDK is not — it needs a real ppc64le artifact.
- **`hosts`: ppc64le pages are 64 KiB.** Hugepage counts and THP behaviour differ from x86; do not carry x86 numbers across.
- **A host run stays `host-running` until someone tears it down.** A run that finishes naturally on a
  machine leaves a phantom `host-running` record — nothing on the host writes state back. Check
  Prometheus or the run log to tell a live run from a finished one, not `deployment.yaml`.
  `deleteDataGeneratorRun` refuses such a record on purpose; run `dataGeneratorTeardown` first, which
  is what turns it into `host-completed` and is also the point at which the summary is recorded.
- **A new plugin test class must be added to the `include(...)` allowlist in the plugin's
  `build.gradle.kts`.** It is an allowlist, not an exclude list, and `--tests` does not override it —
  an unlisted class silently reports zero tests executed while the build goes green.

## Sources of truth (verify here when exact)

- tasks + options: `src/main/kotlin/com/gridgain/demo/plugin/tasks/*Task.kt`
- schema version + migrations: `…/core/configuration/ConfiguredState.kt`, `ConfigMigration.kt`
- element DTOs + assemblers: `…/core/configuration/Configured*.kt`, `*SpecAssembler.kt`
- JSONSchema: `src/main/resources/schema/*.schema.json`
- host monitor: `…/core/infrastructure/HostPrometheusGrafanaPlugin.kt`, `…/core/specs/MonitorSpec.kt` (`HostPrometheusGrafanaMonitorSpec`), `…/core/configuration/MonitorSpecAssembler.kt` (`HostPrometheusGrafanaSpecAssembler`), `…/core/recording/HostMonitorTemplateModel.kt`, `src/main/resources/templates/hosts/monitor/**`
- JDK provision: `…/core/specs/HostJdkProvision.kt`
- `hosts` platform: `…/core/infrastructure/HostInfrastructurePlugin.kt`, `HostGridGainV8ClusterPlugin.kt`, `HostStepBuilder.kt`, `HostResolvers.kt`, `…/core/deployment/HostClusterDeployer.kt`, `HostClusterDestroyer.kt`, `HostInfrastructureForceDestroyer.kt`, `HostLogDiagnostics.kt`, `…/core/command/SshCliExecutor.kt`, `src/main/resources/templates/hosts/**`
- endpoints contract: `src/main/resources/schema/client-endpoints.schema.json`, `…/core/infrastructure/ClientEndpointsWriter.kt`, `…/core/actions/ClusterEndpointPublisher.kt`
- generator dispatch: `…/core/datagen/InClusterDataGenerateAction.kt`, `DataGeneratorJobManifestWriter.kt`, `DistributedDataGeneratorManifestWriter.kt`, `LocalDataGenerateAction.kt`, `HostDataGenerateAction.kt`, `plugin/tasks/DataGenerateTask.kt`, `DataGeneratorTeardownTask.kt`
- key-space striping: `…/core/datagen/InstanceStripe.kt` (the four spellings, the both-or-neither rule, and `generatorArgs()` — every launch path forwards through it), plus the four forwarding sites: `LocalDataGenerateAction.execute`, `DataGeneratorJobManifestWriter.buildJob`, `HostDataGenerateAction.renderEnvFile` + `templates/hosts/data-generator/gridgain-datagen.service`, and the plan-time refusal in `InClusterDataGenerateAction.planDistributed`
- run records + delete: `…/core/state/DeployedDataGeneratorRun.kt` (incl. `DataGeneratorRunStats`), `DeploymentManager.kt`, `plugin/tasks/DeleteDataGeneratorRunTask.kt`

## Maintenance

This skill documents a moving target. **When you change a Gradle task's options, an element-type schema (incl. a `CURRENT_SCHEMA_VERSION` bump), or how the plugin dispatches the generator, update this file in the same change and bump *Last updated*.** Generator *config* facts belong in the `gridgain-demo-data-generator` skill, not here (keep the plugin→generator direction). Prefer citing a source file over duplicating volatile detail. This rule is also in this repo's `CLAUDE.md`.
