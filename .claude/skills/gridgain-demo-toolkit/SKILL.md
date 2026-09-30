---
name: gridgain-demo-toolkit
description: How to USE the GridGain Demo Toolkit (gridgain-demo-gradle-plugin) — its Gradle task surface, the demo-config.yaml element types (infrastructures, hosts, distributions, clusters, databases, cdc_connectors, data_generators, monitors, connector_templates, proxies, secrets, assemblies, node pools, data model), the gke/eks/hosts/docker/ocp platforms, host-machine observability (Prometheus, Grafana and an OpenTelemetry Collector under systemd), schema versioning, and how it dispatches the data generator. Use when deploying or tearing down demo elements, editing demo-config.yaml, picking which plugin task to run, debugging a deploy, or running a load test against a deployed cluster.
---

# GridGain Demo Toolkit — Usage

*Last updated: 2026-09-30*

The toolkit is the `gridgain-demo-gradle-plugin` (the primary product). A target-demo project consumes it via `includeBuild`/`mavenLocal` and invokes its Gradle tasks; demo projects must not add bespoke tasks. This skill is the usage map: tasks, the config model, and gotchas. For the **data generator's own config surface** (ops.yaml/data.yaml, rate kinds, transaction_scope, distribution), see the `gridgain-demo-data-generator` skill — this skill only covers how the plugin *dispatches* it.

> **Verify before asserting.** Task options, element fields and `CURRENT_SCHEMA_VERSION` drift. Cite the source files in §Sources when a fact must be exact, and re-check. Keep *Last updated* current when you change this file.

## Mental model

**Pipeline:** `demo-config.yaml` → migrate to current `schema_version` → JSONSchema validate → deserialize to `ConfiguredState` → `*SpecAssembler` resolves templates+references into deployable specs → task renders k8s manifests / runs clients → records `deployment.yaml` (runtime state).

**Element hierarchy:** instances reference templates + accounts. e.g. a `clusters` entry → a `cluster_templates` entry → a `node_pool_templates` entry; an `infrastructures` entry → `infrastructure_templates` + `infrastructure_accounts`.

**Platforms.** `platform` on a template — and, since v18, on every `clusters` entry — is one of `gke`, `eks`, `hosts`, `docker`, `ocp`. Three are Kubernetes (`gke`, `eks`, `ocp`); `hosts` deploys to a collection of pre-existing Linux machines over ssh with systemd supervision; `docker` (since v28) runs containers on a single Docker daemon reached over a local socket, **GridGain 9 clusters only**; `ocp` (since v30) deploys onto an **existing** OpenShift cluster reached through a named kubeconfig context. Platform-specific fields are prefixed `k8s_`, `host_`, `docker_` or `ocp_` and live inside their platform's `if`/`then` branch in the schema, never at the top level — a top-level platform field gets its defaults injected into every other platform's entries. `ocp` shares the `k8s_` fields with `gke`/`eks` because its workload is an ordinary Kubernetes one; the one it does **not** share is `k8s_node_pool_template`.

**`hosts`, `docker` and `ocp` prepare rather than provision.** None creates the thing it deploys onto: the machines, the daemon and the OpenShift cluster are the operator's, and a teardown removes only what the toolkit installed. `ocp` is the one where that is least obvious, because it really is a Kubernetes cluster and the manifests are the Kubernetes ones. The cloud platforms create and destroy their clusters.

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
| `initDemoConfig` | build a `demo-config.yaml` from `-Pwizard.*` answers — no starter file is read, and the output is comment-annotated. Refuses to overwrite an existing file. | `-PdemoConfigFile`; the four choices `-Pwizard.platform` (`gke`\|`eks`\|`hosts`, comma-separated — **not `docker`**, which the wizard cannot scaffold and refuses by name; see §The `docker` platform), `-Pwizard.ggVersion` (`8`\|`9`), `-Pwizard.monitor` (`control-center`\|`prometheus-grafana`\|`none`), `-Pwizard.derivedImages` (`skip`\|`build-and-push` — `public` parses but is **refused** at scaffold time, because the four packages at `ghcr.io/gridgain-demos` are private) — **all four required**; plus the optional `-Pwizard.demoUse` (`performance-testing`\|`custom-demo`, default: neither, which means a load test and no registry); then `-Pwizard.nodeIdentity` (`project-default`\|`named-account`) for `gke` — `named-account` additionally requires `-Pwizard.secret.gke_node_service_account`, and is what an organisation that forbids the default Compute Engine account needs; then `-Pwizard.region.<platform>` per cloud (`-Pwizard.region.gke=us-central1`, `-Pwizard.region.eks=us-west-2` — one each, since the clouds' region names do not overlap; an omitted one is refused rather than assumed), `-Pwizard.hosts`/`hostArchitecture`/`hostOsFamily`/`hostAuth` for `hosts`, and `-Pwizard.secret.<name>` per secret. Pass the four choices alone and the task reports every remaining value it needs at once. | yes |
| `deployMonitor` / `teardownMonitor` | standalone monitor — Control Center or Prometheus-Grafana on Kubernetes, or Prometheus + Grafana + OTel Collector as systemd units on one machine (`platform: hosts`) | `-PmonitorName` | yes |
| `deployClusterMonitoring` / `teardownClusterMonitoring` | attach a monitor to a cluster | `-PclusterName`, `-PmonitorName` | yes |
| `catalogMetrics` | inventory every metric reaching Prometheus, one file per producer (**read-only**) | `-PmonitorName`, `-PprometheusUrl`, `-PmetricsWindowDays` (default 15), `-PmetricsSnapshotDir` | yes |
| `deployClusterDcr` / `teardownClusterDcr` | DCR bindings between clusters | `-PclusterName`, `-PconnectionName` | yes |
| `takeSnapshot` / `restoreSnapshot` | cluster snapshot / restore | `-PclusterName`, `-PprofileName`, `-PsnapshotType`/`-PsnapshotId` | yes |
| `connectTestClient` | run a test client against a cluster | `-PclusterName`, `-Pmode` (`in-cluster` (default)\|`local`); a `platform: hosts` cluster accepts **`local` only** — there is no namespace to dispatch a Job into | yes |
| `dataGenerate` | run a generator scenario (see §Generator dispatch) | `--scenario` (req), **`--targetCluster` (req, every mode)**, `--ops`, `--data`, `--mode` (`local`\|`in-cluster`\|`hosts`), `--dataGenerator` (**required for `--mode=hosts`**), `--timeout` (in-cluster only), `--instanceIndex`/`--instanceCount` (**both or neither**; `--mode=local` only — on `hosts` the fleet's stripes come from `host_instances_per_host`) | **depends** |
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

**The Load page (`/load`) needs a broker the UI can reach**, and from ops v9 there are two ways to
give it one. If the toolkit deploys the broker, name it from the generator's `ops.yaml`
(`broker: { kind: element, name: <a message_brokers entry> }`) and the UI resolves the address
itself from `deployment.yaml` — **`uiKafkaBootstrap` is then neither read nor required**. It is
needed only for a broker the toolkit does *not* deploy, whose ops literal is resolved from the
generator's vantage point (cluster-internal DNS for an in-cluster run, which the UI cannot dial);
set `uiKafkaBootstrap=<host:port>` in the demo project's `gradle.properties` and `launchPluginUi`
forwards it as `-Dui.kafka.bootstrap`. Either way the page never guesses: it reports the actual
obstacle per channel — broker not defined, disabled, not deployed, or no UI address for a literal
— rather than one catch-all sentence. The UI still starts with none of it configured.

## Element types (demo-config.yaml)

Top level is keyed maps. Instances reference templates/accounts by name; the strict layer (Kotlin DTOs) carries **no defaults** — defaults live only in the JSONSchema (UI/documentation). Schema files: `src/main/resources/schema/*.schema.json`.

| Key | Purpose | Variants / notes |
|-----|---------|------------------|
| `infrastructures` (+ `_accounts`, `_templates`) | cloud k8s env, an existing OpenShift cluster, a set of Linux machines, or a Docker daemon (region, zones) | template platform `gke`/`eks`/`hosts`/`docker`/`ocp`; account provider `gcp`/`aws`/`host`/`docker`/`ocp`. On `ocp` the template carries just `ocp_storage_class` — the name of a StorageClass that **already exists** (`oc get storageclass`), because nothing is created here — and the account just `ocp_context`, the name from `oc config get-contexts`, required for the same reason `docker_context` is and one more that has actually happened: the current context is shared with every Kubernetes tool on the machine, so a `gcloud container clusters get-credentials` run half an hour earlier makes `oc` answer about a GKE cluster. On `docker` the template carries just `docker_network_name` and `docker_host_port_base`, and the account just `docker_context` — the name from `docker context ls`, required rather than defaulted to the active one, because the active context is ambient state and a socket path is a trap (the `default` context's `unix:///var/run/docker.sock` does not exist under Docker Desktop on macOS). On `hosts`, `host_jdk_distribution` is **optional**: empty means no JDK is installed, which is valid only while nothing on those machines needs a JVM — a cluster *or* a `platform: hosts` data generator. Either on a JDK-less infrastructure is rejected at validation, naming the element. Adding a JDK to an infrastructure that had none changes `HostInfrastructurePlugin.preparedMarker` (it folds the JDK identity in with a deliberate `"no-jdk:no-jdk"` literal so the transition is visible), so those machines **re-prepare** and anything already running on them is interrupted. That is supported, not a workaround |
| `hosts` | one pre-existing machine in a `hosts` infrastructure | points **up** at its `infrastructure`; declares `zone`, `architecture`, `os_family`, and **three** addresses — `ssh_address` (how the controller reaches it), `advertised_address` (what a thin client dials), `bind_address` (what the JVM binds). Collapsing them works on a laptop VM and fails on a multi-NIC lab machine |
| `distributions` | archives installed on machines | `type: gridgain` / `jdk` / `prometheus` / `grafana` / `otel-collector` / `node-exporter` / `data-generator` / `kafka`. The observability four are static Go binaries and need no JVM; `data-generator` is the exception that does, which is why an infrastructure hosting one needs a `host_jdk_distribution` even if it hosts no cluster. `data-generator` additionally requires `gridgain_major_version` (matched against the target cluster's, so a generator cannot be pointed at a cluster its thin client cannot speak to) and `launcher_name` — the script in the archive's `bin/`, invoked rather than reassembled as a `java -cp` line, because the generator's own build bakes the GG8 `--add-opens` flags into it. `otel-collector` and `node-exporter` additionally require `binary_name`, because upstream publishes `otelcol`, `otelcol-contrib` and `otelcol-k8s` and only the config knows which was downloaded. **`node-exporter` is the per-machine metrics agent**, and unlike the other three it is named by an *infrastructure* (`host_metrics_distribution`) rather than by a monitor: what it measures — the host's CPU, memory, disk and network — belongs to the machine. Note its tarball's root directory embeds the architecture (`node_exporter-1.12.1.linux-ppc64le`) while `expected_root_entry` is one per-distribution value, so a mixed-architecture estate needs **two** `distributions` entries, not two artifacts under one. Version floors are enforced at assembly, not by the schema (a `pattern` cannot compare 2.9.0 against a 2.47.0 floor): Prometheus ≥ 2.47.0 for the OTLP receiver, Grafana ≥ 9.0.0, collector ≥ 0.90.0. Common to every type: `artifacts` keyed by architecture with a `source` that is a `url` (host pulls), a `file` (controller pushes), or an `image` (controller pulls the named `images` entry, extracts `path_in_image`, pushes the result) — no fallback between them. `sha256` lives **inside** the `source`, not beside it: it is required for `url`/`file` and absent for `image`, whose archive does not exist until the controller builds it, so the checksum is computed after extraction. Verification always happens on the machine after transfer. A missing architecture is an error, never substituted; declare `any` for an arch-independent archive. An `image` source may also carry `exclude: [<relative path>…]` to leave directories out of the built archive — every byte is transferred to every machine |
| `node_pool_templates` | hardware specs | `gke` / `eks` only — a `hosts`, `docker` or `ocp` infrastructure has no node pool the toolkit owns. On `ocp` the machines were sized by whoever installed the cluster, which is why `k8s_node_pool_template` is asked for on the two cloud branches and not on the shared Kubernetes one |
| `cluster_templates` → `clusters` | GG cluster (nodes, ports, resources, data_models, telemetry) | On k8s, `k8s_jvm_max_mem`/`k8s_jvm_min_mem` are **required** and consumed by GridGain 9 only — see §Gotchas. GG8/GG9 via image/template on `gke`/`eks`; **GG8 only** on `hosts`, via `host_gridgain_distribution`; **GG9 only** on `docker`, via `docker_image` (a GG8 image is refused by name at plugin selection); **GG8 and GG9** on `ocp`, via the shared `image` — GG8 was refused until `gridgain/ultimate` had been measured under `restricted-v2`; see §The `ocp` platform. An `ocp` template is the `gke`/`eks` field set minus `k8s_node_pool_template`; the cluster entry takes the same `k8s_namespace`/`k8s_service_name`, because an OpenShift project is a Namespace. On `docker` the template also requires `docker_jvm_max_mem`/`docker_jvm_min_mem` and `docker_work_dir`, and the cluster entry takes `docker_container_prefix`. On `hosts`: `nodes` must equal the enabled-host count exactly, at most one enabled cluster per infrastructure, `host_modules` must include `ignite-rest-http` and must not include `ignite-kubernetes`, and `host_rest_address` must be declared |
| `databases` | non-GG DB | `postgres` / `mariadb` (image, port, databaseName, authSecretRef, initDdlLocation, resources, storage) |
| `cdc_connectors` | Debezium + Kafka pipeline (source: a `databases`; sink: a `clusters`) | `kafka`, `kafka_connect` (`plugins[]`, `jvm_opts[]`), `debezium`, top-level `connectors[]` (extra Connect registrations w/ `__PLACEHOLDER__`→secret) |
| `secrets` | k8s Secret the toolkit materializes at deploy time, and the payload the `hosts` platform reads on the controller | payload from a pluggable `source` (v1: `kind: sops` — a SOPS-encrypted YAML file + a top-level `path` key). **`source.file` resolves against the demo config's own directory**, like `gridgain8_license_file` and the generator's paths — so with the config at `src/main/resources/demo-config.yaml`, `file: secrets/x.sops.yaml` means `src/main/resources/secrets/x.sops.yaml`, not a `secrets/` at the repo root. Referenced **by name** from the `*_secret_ref` fields below |
| `data_generators` | streaming data generator as a first-class element | **Not available on `docker` or `ocp`** in this release; drive a Docker cluster from a local run against its published loopback endpoints instead. Every entry carries a **`platform`** discriminator since v20 (`gke`/`eks`/`hosts`), which must agree with its infrastructure's template — materialised onto the generator rather than followed through the reference because Jackson subtype resolution and the schema's `if`/`then` branches both need a literal property. Common to both: `infrastructure`, `target_cluster` (a name only — the generator resolves addresses itself from `client-endpoints.yaml`), `scenario`, `ops_file`, `data_file`. **k8s** adds a dedicated `wp-<name>` pool with `WorkloadScheduling.forElement` placement: `k8s_namespace`, `k8s_node_pool_template`, `num_nodes`/`min_nodes`/`max_nodes`, `replicas` (0 = staged), `max_replicas`, `per_pod_rate` (0 = unbounded), `pod_resources`, `timeouts.deployment`. **`hosts`** adds `host_distribution` (a `type: data-generator` archive), **`host_instances_per_host`** (v22+, required — processes on *each* of the infrastructure's machines), **`host_jvm_opts`** (v26+, required — the unit's `JAVA_OPTS`; see below), the optional `host_cpus_per_host`, and `host_timeouts.unit_active`, and carries **none** of the pod/node-pool fields — they describe a horizontally scaled set of containers and an autoscaler beneath them, whereas these are processes on machines that already exist. They are absent rather than defaulted, so a misplaced one is reported as the mistake it is |
| `monitors` | observability | `control-center` / `prometheus-grafana`. **Not available on `docker`**; on `ocp` only `prometheus-grafana` (see §The `ocp` platform) — a Docker infrastructure deploys clusters only. Every entry carries a **`platform`** discriminator since v19 (`gke`/`eks`/`hosts`), which must agree with its infrastructure's template. `control-center` is constrained to the two Kubernetes platforms — there is no host Control Center; a host cluster reaches one via `host_control_center_url`. `prometheus-grafana` on `hosts` takes `host_prometheus`, `host_grafana`, `host_otel_collector`, `host_storage` and `host_timeouts`; the Kubernetes branch keeps `num_nodes`/`min_nodes`/`max_nodes` and the `k8s_*` fields, which moved out of the top level at v19 because they are node-pool concepts a machine set has nothing to do with |
| `connector_templates` | cluster sidecars / agents | `cloud-connector` (CC) / `otel-collector` (Prom/Grafana) / `ignite-agent` |
| `dcr_templates` → `dcr_connections` | replication | `gg8` (push) / `gg9` (pull) |
| `image_registries` → `images` | container images by name | referenced by templates/databases/connectors |
| `proxies` | TCP forwarder giving a cluster/database a stable local address | `listeners[]` name a target kind + service; `startDemoAccess` port-forwards through it |
| `assemblies` | an ordered set of elements deployed/torn down together | `deployAssembly` walks it and reports config-drift skips at end-of-run. Kinds: `infrastructure`, `cluster`, `monitor`, `cluster_monitoring`, `database`, `cdc_connector`, `message_broker`, `data_generator`, `data_model`, `cluster_dcr`, `proxy`, `secrets` — pinned against the schema by `AssemblyElementKindSchemaTest` |
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

**Schema versioning:** `CURRENT_SCHEMA_VERSION` lives in `ConfiguredState.kt` (currently **30** — v30 opened the `ocp` platform across infrastructure templates, accounts, cluster templates and clusters, writing nothing: every change is additive, so a v29 document is a valid v30 one. The bump is for the affordance rather than the data — that number is how the wizard and the UI learn `ocp` is an option, and shipping a platform as an accepted value before it works puts a dead option in front of a reader. v29 added the required `k8s_jvm_max_mem`/`k8s_jvm_min_mem` to every Kubernetes cluster template, written at half the template's declared memory limit: the GridGain 9 image hard-codes a 16 GiB heap that the pod's memory limit does not constrain, so a 10Gi pod asked for 16 GiB and was taken by the OOM killer under load. Unlike v27's thread pools this writes a value, because the existing behaviour was harmful rather than merely default — the same reasoning v26 applied to `host_jvm_opts`. v28 introduced the `docker` platform across infrastructure templates, accounts, cluster templates and clusters, writing nothing: every change is additive, so a v27 document is a valid v28 one. v27 introduced the optional `host_thread_pools` block on a hosts cluster template, writing nothing: sizing a pool during an upgrade would change every cluster's throughput and latency invisibly. v26 added the required `host_jvm_opts` to every `platform: hosts` data generator, written as `-Xms2g -Xmx2g`: with nothing set a generator ran on OpenJ9's defaults (8 MB heap growing to 15.4 GB, 3.9 GB nursery) and paused for close to a second, *inside* the operation latency it reports. v25 added the optional `host_cpus_per_host` on a `platform: hosts` data generator, rewriting no values. v24 added the optional `host_cpus_per_node` on a `platform: hosts` cluster, rewriting no values. v23 added the optional `host_metrics_distribution`/`host_metrics_port` on a hosts infrastructure template and `scrape_targets` on a host monitor, rewriting no values. v22 added the required `host_instances_per_host` to every `platform: hosts` data generator, written as `1` so an upgraded config starts the processes it started before. v21 added an optional `message_brokers` section, rewriting no values. v20 made `platform` required on every `data_generators` entry, derived from its infrastructure, and split the entry into `K8s` and `Host` variants. v19 did the same for `monitors` and moved the Kubernetes-only fields of a `prometheus-grafana` monitor into its platform branch. v18 added `hosts`/`distributions` and did the same for `clusters`). Breaking config changes bump it + add a `MigrateVNtoVN+1` in `ConfigMigration.kt`'s runner list + update JSONSchema + add a `ConfigMigrationTest` case. Configs auto-migrate forward before validation.

⚠️ **Migration rewrites the user's config file in place through SnakeYAML, which discards every comment in it.** Back the file up before running any task against a config below `CURRENT_SCHEMA_VERSION`, and be aware that a hand-maintained (especially gitignored) config loses its entire rationale on first migration. Hand-bumping `schema_version` is equivalent *only* when the config already states everything the migration would inject.

`deployment.yaml` (runtime state) has its own `schemaVersion` with **no** migration — mismatch means tear down + redeploy. It is at **12**: v12 made a host data generator span every machine its infrastructure owns, so `HostDataGeneratorBase.host` (one `HostSpec`) became `hosts: List<HostSpec>` and gained `instancesPerHost` — and `DeployedHostDataGenerator` embeds the spec, so a record written at 11 cannot deserialize at all. ⚠️ **Upgrading the plugin past this therefore requires a tear-down and redeploy of any live host demo.** v11 moved the pod and node-pool fields into `K8sDataGeneratorBaseSpec`, which changes `GkeDataGeneratorSpec`'s persisted shape non-additively (the fields are required and non-null, so a record written at 10 fails partway through loading). v10 did the same for a Prometheus & Grafana monitor's node counts. The gate fires with its tear-down message rather than letting a stale record fail deserialization with a generic error.

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
- **Two Kafka addresses, deliberately different — for the *literal* form only.** An ops v9
  `broker: { kind: address, … }` is the *generator's* vantage point and `uiKafkaBootstrap` is the
  *UI's*; never derive one from the other, because an in-cluster generator's address is
  cluster-internal DNS a laptop cannot dial. **A `broker: { kind: element, name: … }` reference is
  not an address at all**, so this rule does not apply to it: each side resolves the name from its
  own vantage point, and for a hosts broker — the only kind there is — both land on the same
  advertised address. Prefer the reference; it is the form that needs no second setting.
- **`control:` needs ops schema_version 5.** A generator archive built before v5 rejects it outright,
  so the rate slider requires a redeployed dist; `metrics:` alone is a v4 feature.
- **A deployed broker publishes its address to `broker-endpoints.yaml`**, under
  `<demoOutputDirectory>/client/`, beside `client-endpoints.yaml` and with the same contract shape:
  the plugin is the sole writer, the schema (`schema/broker-endpoints.schema.json`, version 1) is
  the only agreement with its reader, and the reader duplicates the version constant rather than
  depending on the plugin. The address written is the one **recorded in `deployment.yaml`**, not one
  re-derived from the spec, so the two files cannot disagree. The file is deleted when the last
  broker is torn down, so an unresolvable name reads as "no broker is deployed". No ConfigMap is
  emitted — a broker is hosts-only, so there is nothing to apply one to.
- **Usable as an assembly element** (`kind: message_broker`, takes `name`). Put it **before** any
  `data_generator` that publishes to it. Nothing validates that order: assemblies deploy in declared
  order and `AssemblyValidator` has no cross-element ordering rules for any kind. It only bites a
  Kubernetes generator with `replicas > 0`, whose pods publish at deploy time; a host generator
  installs an archive and starts nothing until `dataGenerate`.
- **`disabled: true` is honoured** by the deploy-all fan-out and by validation — it was parsed and
  ignored until 2026-09-19, so a broker switched off was still deployed. `hasMessageBroker` stays
  unfiltered on purpose, matching every sibling `has*`: a disabled name should report as disabled,
  not as missing. ⚠️ A `disabled: true` block that also drops `platform:` still fails to
  deserialize — Jackson needs the type id before anything reads `disabled`. Same for
  `data_generators`, `clusters` and `monitors`; it is a workspace-wide idiom clash, not broker-specific.
- **`validateDemoConfiguration` now exercises brokers**, so a machine outside the named
  infrastructure, a missing JDK, colliding listen/controller ports or an unresolvable archive all
  surface before any deploy. They used to fire first at `deployMessageBroker`.
- **Teardown asymmetry, pre-existing:** `deployMessageBroker` fans out over every enabled broker
  when `-PmessageBrokerName` is omitted; `teardownMessageBroker` requires the name.
- **`teardownInfrastructure` refuses while a broker is deployed on it**, the way it already refuses
  for clusters — teardown removes the install root, data root and service user out from under a
  live `gridgain-kafka-*` unit. `forceDestroyInfrastructure` instead cascades the broker's record
  and its endpoints entry away, because that path is for wreckage.
- **This change bumps neither schema version.** demo-config stays **23** (widening the assembly
  `kind` enum invalidates no document) and `deployment.yaml` stays **12**. Do not "fix" that: a
  deployment bump has no migration path and forces every live host demo to tear down. In
  particular, never add a non-defaulted field to anything reachable from `DeployedHostMessageBroker`
  — it embeds the whole `HostMessageBrokerSpec`.

## The `hosts` platform

Deploys **GG8 or GG9** to pre-existing Linux machines over ssh, supervised by systemd. First target is
IBM Power (ppc64le, RHEL family), but nothing is hardcoded to it — architecture and OS family are
**declared per host and verified against what the machine reports**, so the same path runs on any
architecture.

**The version is chosen by the distribution, not by a separate key.** `host_gridgain_distribution`
names a `distributions` entry, and that entry's `gridgain_major_version` selects
`HostGridGainV8ClusterPlugin` or `HostGridGainV9ClusterPlugin`. One spec type serves both: the version
does not change what a host cluster *is* — same machines, identity, directory tree, storage roots,
timeouts — only what is installed and how it is started. See **GG9 on hosts** below for what differs.

**Ownership split.** The infrastructure owns the machine: service identity, directory tree, OS tuning,
firewall ports, and the **JDK**. The cluster owns the **GridGain distribution** (a per-cluster choice),
its config, licence, env file, systemd unit and start.

⚠️ **One cluster per host infrastructure**, enforced by `HostGridGainClusterSpecAssembler` and
deliberately kept — two clusters on one machine set would collide on ports, install directories and
unit names. The split above describes *which layer owns what*, **not** a licence to co-tenant: the
directory tree and unit names are separated by `host_instance_name`, but nothing separates the ports,
so the guard refuses outright rather than checking disjointness. To compare two clusters (two GridGain
versions, say) on the same hardware, **swap which one is enabled** rather than running both; to run
them at once, give each its own infrastructure over a different set of machines.

**"Deployed" means prepared, not reachable.** Machines always answer a ping; preparation does not. So
`deployInfrastructure` reports the infrastructure absent until a marker written *last* by the creation
stage is present on every machine, and `assessClusterAdequacy` is the real gate — it compares observed
architecture, free disk and installed JDK against the configuration and reports every mismatch at once.

**On-machine layout** (every root config-supplied):
`<installRoot>/{jdk/current→<version>, <cluster>/dist/current→<version>, <cluster>/conf, <cluster>/state}`,
`<dataRoot>/<cluster>/{work,storage,wal,walarchive}`, `<logRoot>/<cluster>`. Versioned directory plus a
`current` symlink, so an upgrade is a swap and a restart with no re-download.

**Readiness ladder, GG8** (ordering is load-bearing): systemd `ActiveState`/`NRestarts` (liveness +
crash-loop — `Type=simple` reports active on fork, so this alone is insufficient) → `control.sh --state`
run **on the machine against the host's bind address** (sidesteps every firewall question a
controller-side probe would face; not loopback, because `localHost` pins every port to that interface)
→ topology count via the REST endpoint → **then** activation, and only with persistence enabled.
Activation must come last because the first activation of a persistent cluster fixes the baseline to the
topology present at that moment; a node joining later runs outside it, degraded and silent.

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
`host_otel_endpoint` on the **cluster template** — `http://<advertised>:<grpc_listen_port>` with
`host_otel_protocol: GRPC` for GG8, and `http://<advertised>:<http_listen_port>` with
`host_otel_protocol: HTTP` for GG9, which cannot use gRPC (see **GG9 on hosts**). `deployMonitor`
prints the correct pair for each version.

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
`type: data-generator` archive and a systemd template unit on **every** machine its infrastructure owns,
and one `dataGenerate` starts `host_instances_per_host` processes on each of them — a fleet, with the
plugin assigning every process a disjoint key-space slice. No pods, no replicas, no autoscaler. Until
v22 it was exactly one machine and one process, because nothing outside Kubernetes divided the key
space; `GeneratorFleet` does that now. It is the one host element that is a JVM application
rather than a Go binary, so its infrastructure needs a `host_jdk_distribution` even when it hosts no
cluster. Put it on a machine that is *not* a data node: it is a client, and co-locating it has it
competing with the thing it is meant to load. `host_distribution` sits on the generator rather than the
infrastructure (unlike `host_jdk_distribution`) because a JDK is shared by everything on a machine set
whereas a generator archive is pinned to one GridGain major version — an infrastructure hosting a GG8 and
a GG9 generator would need two. See **Generator dispatch** below for the deploy/run/teardown split.

**Both GridGain versions are drivable**, and this needed no toolkit code: the unit's `ExecStart` is
the distribution's `launcher_name`, so a GG9 element is a GG8 element with a `data-generator-gg9`
archive and `gridgain_major_version: 9`. `HostDataGenerateAction` refuses a mismatch between the
archive's major version and the target cluster's, because the two thin clients pull incompatible
Ignite runtimes. ⚠️ The **scenario files are not equally portable**: `ops.yaml` is version-neutral,
but `data.yaml`'s `backups` and `write_synchronization_mode` are GG8 cache settings that GG9
silently ignores — it provisions with SQL, where replication is a zone property. The same file
therefore yields two replicas on GG8 and one on GG9. See the generator skill's **GridGain 9**
section before comparing throughput across versions.

**Host metrics (v23+).** `host_metrics_distribution` on a `platform: hosts` infrastructure template
installs a `node-exporter` agent as a systemd unit (`gg-node-exporter-<infrastructure>`) on **every**
machine that infrastructure owns, listening on `host_metrics_port` (9100 by default). Empty means no
agent — the same empty-means-absent idiom `host_jdk_distribution` uses. A monitor collects them by
listing `host:port` in its `host_prometheus.scrape_targets`, which becomes a `host-metrics` scrape
job; addresses rather than a cross-reference, because the monitor may sit on an infrastructure that
knows nothing about theirs, and **nothing cross-checks the port against `host_metrics_port`**.

⚠️ **Without this a load test cannot answer its own question.** A GridGain node exports JVM and cache
metrics over OTel and none of them describe the machine, so throughput can plateau with no way to
tell a saturated server from a saturated client. Put the agent on *both* ends — the server machines
and the load-client machines — or the sweep is still ambiguous.

### GG9 on hosts

Same infrastructure, same delivery, same teardown. Five things differ, and each one is a place the GG8
shape looks right and is wrong.

**The distribution ships no launcher.** GG8 has `bin/ignite.sh`. The GG9 distribution has **no `bin/`
directory at all** — the container image starts its node from `docker-entrypoint.sh`, which sources
`lib/bootstrap-functions.sh` and assembles a `java` command line. That command line is the launch
contract, and `templates/hosts/cluster/v9/gridgain9-start.sh` reproduces it: the mandatory `--add-opens`
list, `-classpath "<lib>/ignite-runner-*.jar:<lib>/*"`, `org.apache.ignite.internal.app.IgniteRunner`,
then `--config-path --work-dir --node-name`. ⚠️ Its GC flags are **deliberately not** reproduced —
the distribution emits `-XX:+UseG1GC`, which **Semeru/OpenJ9 rejects outright**, and Semeru is the JDK
on ppc64le. Heap and GC come from `host_jvm_opts`, exactly as on the GG8 host path.

**The node rewrites its own configuration.** GG9 persists local config changes back to the file it was
started with, so the node is started on a **writable copy** under the data root (`<dataDir>/conf/`),
refreshed from the placed `conf/` artifact on every start. Pointing `--config-path` at the placed copy
would have the node mutating an artifact the deployment owns and compares against — and that copy is
mode 0640.

**Initialisation is mandatory, and lands mid-ladder.** A GG9 cluster does not exist until
`cluster init`: nodes sit in `STARTING` and every cluster-scoped endpoint answers `409`. The ladder is
therefore systemd → `node/state` answers *with any state* → `topology/physical` (all N nodes) →
**init** → `topology/logical` (all N nodes). ⚠️ **Do not gate on `STARTED` before init** — it only
arrives afterwards, so that wait deadlocks against the thing it is waiting to enable. `physical` is the
only cluster endpoint that answers pre-init, and it is the real precondition for init, because init
names the metastorage members by node name and they must be visible to be named.

**Init is over REST, idempotent, and carries the licence inline.**
`POST /management/v1/cluster/init` with
`{metaStorageNodes, cmgNodes: [], clusterName, clusterConfiguration: "", license}` — the field is
`license` (US spelling) and holds the **file's contents**, not a path. It is mandatory: omitting it is
`400 "License must not be empty."` `gg9-cluster-init.sh` checks `cluster/state` first (409 → initialise,
200 → no-op) and needs **python3** on the machine to escape the licence into the body, which the V9
plugin asserts as a cluster-level prerequisite. No GG9 CLI is installed; REST does the whole job.

**Keys that do not apply.** `host_modules` must be `[]` — GG9 has one `lib/` directory and no
optional-module layout, and its REST endpoint is built in. The assembler **rejects** a non-empty
`host_modules`, a non-zero `host_thread_pools` and a non-empty `host_control_center_url` rather than
ignoring them. `host_connector_port`, `host_jmx_port`, `host_communication_port[_range]` and
`multicast` are still **required fields** with no GG9 meaning — carried unused and documented as
GG8-only in the schema, because forcing a second template shape would mean a migration for no gain.

**Metric export works, and reaches the cluster differently.** `host_otel_endpoint` means the same
thing on both versions, but GG8 wires its exporter into each node's configuration at startup while
GG9 holds it in the **cluster** configuration — which does not exist until `cluster init`. So the V9
plugin applies it *after* initialisation, as the last step of `initCommands`, with
`gg9-metrics-config.sh`:

`PATCH /management/v1/configuration/cluster`, `Content-Type: text/plain`, HOCON body
`ignite.metrics.exporters=[{name=otel_exporter,exporterName=otlp,endpoint=…,protocol=…,compression=…,periodMillis=…}]`.
It is a **named map**: a PATCH merges by `name`, and `ignite.metrics.exporters.<name>=null` removes
one. Applying it to a running cluster starts the exporter within one export period — **no restart**.
All 34 metric sources are enabled by default, so there is nothing else to turn on.

⚠️⚠️ **A 400 from that endpoint is NOT a rejection.** The value is written to the metastorage and
replicated *before* it is validated on application; every node then fails to apply it,
`WatchProcessor` calls that a critical system error, and `StopNodeFailureHandler` **stops the node**.
Sending `compression="NONE"` instead of `"none"` took both Power lab nodes down on 2026-09-23 — the
REST call returned 400 with a perfectly clear message, and the cluster died anyway. So values are
translated and validated on the controller (`HostClusterTemplateModel.v9OtelProtocol` /
`v9OtelCompression`) **and** again in the script. Neither check is redundant.

⚠️ **GG9 must use `host_otel_protocol: HTTP`.** Over gRPC its exporter logs
`Failed to export metrics … Socket is closed` against the collector and delivers nothing; over
`http/protobuf` it works. That also changes the port — the collector's `http_listen_port` (4318), not
`grpc_listen_port` (4317) — and the toolkit appends OTLP's signal path `/v1/metrics`, which HTTP
requires and gRPC does not. `deployMonitor` prints the correct pair for each version.

**Metric names differ completely between the versions**, so the two dashboards cannot stand in for
each other and do not collide: GG8 exports prefixed names (`cacheGroups_*`, `io_discovery_*`), GG9
exports bare ones (`SessionsActive`, `AvailableProcessors`, `LoadAverage`). A host
`prometheus-grafana` monitor provisions **both** overview dashboards, because it has no cluster
context at provisioning time; the unused one simply has no series. GG9's `job` and `service_name`
labels are the **cluster ID**, not a friendly name — `instance` is the node name.

**Every metric carries a `metric_source` label**, added by the collector (`transform` processor, in
both `templates/hosts/monitor/otelcol.yaml` and `templates/k8s/otel-collector/config-map.yaml`). For
GG9 this is load-bearing, not a convenience: its OTLP exporter emits **bare** metric names and
**zero** datapoint attributes, so a name exposed by several sources collapses onto one series and
the writers race. Measured on 9.1.21: 38 sources exposed **307 (source, metric) pairs under 225
names** — 82 measurements unreachable, and **eight sources entirely invisible** (all seven thread
pools, plus per-table `storage.aipersist.tables.*`). The label restores them: on the Power lab the
cluster went from 908 series / 225 distinct names to **1072 series / 329 (source, name) pairs**,
with no GG9 series left unlabelled. Values are the source names you see in
`GET /management/v1/metric/node/set` (`sql.plan.cache`, `thread.pools.sql-executor`).

⚠️ **`transform` requires a contrib (or k8s) collector build**, not core `otelcol`. The hosts deploy
runs `otelcol validate` against the rendered config before starting the unit, so a core build fails
immediately and says so instead of timing out a readiness probe.

### Bundled dashboards

A host `prometheus-grafana` monitor provisions **four**: both cluster overviews (it has no cluster
context at provisioning time, and the unused one simply has no series), `data-generator-overview`,
and `infrastructure-nodes-overview`. `demo-combined-overview-v8` stays out — it is built around the
Kubernetes GG8 demo's generator and nothing on this platform fills it.

**`infrastructure-nodes-overview` is close to the point of having a monitor on this platform.** A
GridGain node's own telemetry reports the JVM's view, so without node_exporter a saturation run
shows throughput falling and cannot show whether a *server* ran out of CPU, disk or memory. It is
deliberately **not** provisioned on Kubernetes, where nothing installs a node exporter.

⚠️ **An infrastructure declaring `host_metrics_distribution` now opens the agent's port itself** when
`host_manage_firewall` is true. It did not before, and the gap was invisible on machines running no
firewalld: on the first firewalled host the exporter was active and answering on `127.0.0.1:9100`
while firewalld held every other service's port open and not that one — Prometheus scraped nothing
and the panels were empty exactly the way an idle machine is empty. ⚠️ The step is part of *creation*,
so an already-prepared machine will not get it until its `state/.gg-infra-prepared` marker is removed.

⚠️ `node_exporter`'s archive root carries the architecture (`node_exporter-<v>.linux-<arch>`) and
`unpack.expected_root_entry` is declared per distribution, not per artifact — so a mixed-architecture
estate needs one `distributions` entry per architecture.

⚠️ Node metrics label `instance` as `<address>:<port>`, while a GridGain 9 cluster labels it with the
**node name**. Lining a host's CPU up against its cluster's metrics is therefore a manual step.

### The metrics catalogue (`catalogMetrics`)

Writes an inventory of every metric reaching Prometheus to `<demoOutputDirectory>/metrics/` — an
`index.yaml` plus one file per producer. Read-only: it queries Prometheus, and each GridGain 9
cluster's management REST API. A **committed snapshot** lives at `src/main/resources/metrics/`;
refresh it by passing `-PmetricsSnapshotDir=<this checkout>`, never by hand.

**The four producers can be interrogated to very different depths, and the artefact says so.** Every
file carries an `enrichment` block naming which probes answered, so a blank `help` is never
ambiguous between "no description exists" and "we could not ask":

| Producer | Names | Source of each metric | Description |
|---|---|---|---|
| GridGain 9 | Prometheus | **yes** — joined against `/management/v1/metric/node/set` | **yes**, same call |
| GridGain 8 | Prometheus | encoded into the name (`cache_<name>_CachePuts`) | none available |
| node_exporter | Prometheus | n/a | **yes** — scraped, so Prometheus holds TYPE/HELP |
| data generator | Prometheus | n/a | none available |

⚠️ **Prometheus holds no TYPE/HELP for anything pushed over OTLP** — GridGain 8, GridGain 9 and the
generator all return `{}` from `/api/v1/metadata`. Only scraped targets have it. That is why the GG9
REST join is necessary rather than merely richer.

⚠️ **`-PmetricsWindowDays` bounds every query, and the default is 15 to match the shipped Prometheus
retention.** The inventory of a **torn-down** cluster is often the valuable part — those series
outlive the cluster — and a window shorter than the gap since teardown returns nothing while looking
like a quiet estate.

⚠️ **A torn-down element cannot be attributed to its configuration.** `disabled: true` entries are
pruned during parsing, so a cluster left disabled has no name, infrastructure or GridGain version to
match against. Its metrics are still catalogued, as `UNCLASSIFIED`, with a `note` explaining the
shape of its job name. The version is not guessed.

⚠️ Two GridGain 9 exporter defects to know about, both observed on 9.1.21:
- **Disabling a metric source does not stop its export.** `MetricReporter.removeMetricSet` compares
  the *metric* name against the *set* name, so it removes nothing until the exporter is rebuilt.
  `partition.states.zone.*.table.*` reports `enabled: false` and keeps publishing.
- **String and UUID gauges are silently dropped.** The whole `upgrade.rolling` source
  (`InitialVersion`, `TargetVersion`, `State`, `UpgradedNodes`, `NotUpgradedNodes`) is strings, so it
  never reaches Prometheus and the GG9 dashboard's rolling-upgrade panel cannot populate over OTLP.

**Ports.** GG9 uses `discovery_port: 3344` (one port; there is no separate communication SPI),
`management_port: 10300`, `client_port: 10800`. A GG9 cluster cannot run beside a GG8 one on the same
machines anyway — see the one-cluster-per-infrastructure rule above — but give the two templates
distinct ports regardless if they take turns on one machine set, so that a half-finished teardown
cannot have the incoming cluster bind to the outgoing one's port.

**Proven on hardware 2026-09-23**: a two-node GridGain 9 cluster on the Power lab's ppc64le LPARs —
deploy, init, both nodes `STARTED`, and a redeploy that left both PIDs untouched with `NRestarts=0`.

**Endpoints.** `client-endpoints.yaml` is at `schema_version: 2` with a required `deployment_kind`
(`k8s`|`hosts`). A hosts entry has **no** `namespace` and no `in_cluster` context — its addresses go under
`local`, built from each host's `advertised_address`. `host_rest_address` is declared, never derived from
the host list. This file is the contract with `gridgain-demo-client-utils`, versioned in lock-step — and
the consumer is concretely `client-finder-common`'s `ClientEndpointsLoader` (which holds
`EXPECTED_SCHEMA_VERSION = 2` and throws `SchemaVersionMismatchException` on anything else) feeding
`AddressResolution`. Named here because confirming it once cost a whole session: the published jar can lag
the source by days, so when a contract spans repos, **check the artifact, not just the code**.

## The `docker` platform

Containers on **one** Docker daemon, reached over a local socket. **GridGain 9 clusters only** —
a GG8 image is refused by name when the plugin is selected, rather than assembled and then failed at
deploy. No monitors, no data generators, no databases; those route to the shared "not supported on
this platform" failure naming both ways out.

Like `hosts`, it **prepares rather than provisions**: the daemon is the operator's and is never
created or destroyed. A deploy creates the shared bridge network; a teardown removes it.

### Addressing — three names, three questions

| Concept | Value |
|---|---|
| peer-to-peer | the **container name**, resolved by the user-defined bridge's embedded DNS |
| bind | every interface inside the container — a container is single-homed, so unlike a lab machine there is no wrong one to pick |
| client-facing | `127.0.0.1:<published port>` on the machine running the toolkit |

The network must be **user-defined**, never Docker's default bridge: only a user-defined network
runs the embedded DNS server, and name resolution is the whole addressing model. Each node takes a
block of `docker_host_port_base` (management, then client), published to **loopback only** — a demo
cluster has no business being reachable from the local network.

### Minimum configuration

```yaml
infrastructure_accounts:
  local-docker: { disabled: false, provider: docker, docker_context: desktop-linux }
infrastructure_templates:
  local-daemon:
    disabled: false
    platform: docker
    docker_network_name: gg-demo-net
    docker_host_port_base: 20300
cluster_templates:
  docker-gg9:
    platform: docker
    docker_image: gridgain9          # an `images` entry
    docker_jvm_max_mem: 2g           # required — see below
    docker_jvm_min_mem: 1g
    docker_work_dir: /opt/gridgain/work
clusters:
  gg9-local: { platform: docker, template: docker-gg9, infrastructure: local, docker_container_prefix: gg9-local }
```

### Two things that will bite

**`docker_jvm_max_mem` is required, and it matters.** The GridGain image sizes its heap from the
machine it can see, not from any limit on the container: measured on a 23 GiB Docker Desktop VM it
chose `-Xmx16g` unprompted, and the same image on Kubernetes reported a 16 GiB maximum inside a pod
limited to 10 GiB. Unset, several nodes on one laptop each believe they own the whole machine and the
first real workload ends in the OOM killer, which names nothing useful.

**`docker_work_dir` must be a path that already exists in the image**, and `/opt/gridgain/work` —
the image's own `GRIDGAIN_WORK_DIR` — is the right answer. Docker copies a mount point's ownership
into a fresh named volume **only when that path exists in the image**. A path invented for the
purpose arrives `root:root`, and the node, which runs as a non-root user, dies at
`Failed to create directory for partitions storage` before the grid starts.

### The wizard does not scaffold this platform

`-Pwizard.platform=docker` is refused by name. A Docker infrastructure has no cloud account, region,
node pool or disk class, so every question the interview asks has no answer for it — see
`WizardIntent.SCAFFOLDABLE_PLATFORMS`, which is deliberately the smaller set. Write the config by
hand; the block above is a complete working one.

### Readiness

Three rungs, because `docker run -d` succeeding means only that the daemon accepted the container:
the container stays **running** (polled — catches the node that dies on its config within seconds),
the management API **answers** (any HTTP status, including the `409` GridGain 9 returns before init
— demanding 200 would deadlock against the very step that fixes it), then the cluster is
**initialised** over the published loopback port. A readiness wait also watches container liveness
each cycle, so a node that exits mid-wait fails immediately with its status rather than running to
the timeout.

## The `ocp` platform

A GridGain 9 cluster on an OpenShift cluster **you already have**. The manifests are the ordinary
Kubernetes ones — the same `templates/k8s/cluster/v9/` files `gke` and `eks` render — and everything
that differs follows from not owning the cluster.

### Attach, never provision

Nothing creates, sizes or destroys the OpenShift cluster. `deployInfrastructure` checks that the
named kubeconfig context reaches a live API server and records which one; `teardownInfrastructure`
forgets the record and leaves the cluster running. Creating an OpenShift cluster is `rosa create
cluster`, `openshift-install` or `crc start` — three unrelated tools with three unrelated credential
models — and attaching is the one behaviour common to all three.

The toolkit also never runs `oc login`. Sign in yourself, then name the context that login created.

### Minimum configuration

```yaml
infrastructure_accounts:
  openshift-local:
    provider: ocp
    ocp_context: crc-admin          # `oc config get-contexts`, NAME column

infrastructure_templates:
  openshift:
    platform: ocp
    ocp_storage_class: crc-csi-hostpath-provisioner   # `oc get storageclass`; 'gp3-csi' on ROSA

infrastructures:
  openshift-primary:
    template: openshift
    account: openshift-local
    region: laptop                  # a locality label; nothing is looked up from it
    zones: [local]
    zone_spread: SINGLE
```

The cluster template is the `gke`/`eks` field set **minus `k8s_node_pool_template`**, and the cluster
entry is the ordinary `k8s_namespace`/`k8s_service_name` pair. A complete working file lives in the
dev workspace as `src/main/resources/demo-config-ocp.yaml` — every `demo-config*.yaml` is gitignored
(they may carry secrets), so that one is local rather than something to check out.

### `restricted-v2`, which is the whole of the difference

OpenShift's default SCC gives each pod an arbitrary UID and fsGroup from the project's own range and
**refuses any the manifest names**. Measured on 4.22.14:

| Manifest asks for | Verdict |
|---|---|
| `runAsUser: 0` | rejected — *"must be in the ranges: [1000660000, 1000669999]"* |
| `fsGroup: 1001` (what `gke`/`eks` correctly render) | rejected — *"1001 is not an allowed group"* |
| neither | admitted; runs as `uid=1000660000 gid=0(root)` |

The second line is the one that catches people: hard-coding the image's own GID is the obvious fix
for volume ownership, it is right on GKE and EKS, and OpenShift refuses it. So this platform renders
**no** `securityContext` at all, the kubelet chowns the PVC to the fsGroup it assigned
(`drwxrwsr-x root:1000660000`), and the GridGain 9 image is happy because its work directory is
group-writable.

Two consequences worth knowing:

- **Anything that needs to write must be given somewhere to write.** The init Job has no PVC, and
  the GridGain 9 CLI writes a logging lock file in its working directory and its own config under
  `$HOME` before it does any work. Under an arbitrary UID `$HOME` is `/`, and the job dies in
  Micronaut startup with `Couldn't create default config` — which names nothing about permissions.
  It is given an `emptyDir` home (mode 0777, so writable by whatever UID arrives).
- **Pod anti-affinity is `preferred`, not `required`.** An attached cluster may have fewer machines
  than your GridGain cluster has nodes — OpenShift Local is a single node — and a required rule
  leaves every replica after the first Pending forever.

### No StorageClass, no LoadBalancer, no node pool

`gke`/`eks` create a `gg-<cluster>` StorageClass naming their cloud's CSI provisioner. Here the class
is named in configuration and nothing creates it: the provisioner depends on how the cluster was
installed, and creating a cluster-scoped object usually needs a privilege an ordinary project user
has not got. **Nothing deletes it either** — it is very likely the cluster's default, and removing it
would unbind every other workload on that cluster.

`demo_access` has no counterpart: OpenShift's answer to external access is a Route, and a cluster
with no cloud load-balancer integration would leave a Service pending forever. Reach the cluster with
`oc port-forward` instead.

### Teardown leaves PVs behind if the class says `Retain`

`teardownCluster` deletes the PVCs it created (unless `retain_on_cluster_destroy`), and the PV
lifecycle then belongs to the storage class. A class with `reclaimPolicy: Retain` — which
OpenShift Local's is — leaves them `Released`, holding their data, for the cluster owner to reclaim
with `oc delete pv`. That is the class's policy, not the toolkit's.

### Both GridGain versions

GridGain 8 and 9 both deploy here. GridGain 8 brings what it brings everywhere — four PVCs per node,
namespaced RBAC for its Kubernetes IP finder, and an *activation* job instead of an init one, which
runs only when `persistence_enabled` (an in-memory cluster has no baseline topology to activate).

It was refused here until `gridgain/ultimate` had actually been run under `restricted-v2`, and what
that measured is worth repeating: the image runs happily as the assigned uid with gid 0 and
`HOME=/`, it ships `IGNITE_HOME=/opt/gridgain` with `/opt/gridgain/work` mode `drwxrwxrwx`, and
`control.sh` — which the activation job runs in a pod that mounts nothing at all — exits 0 under
that identity. The other three volumes mount at paths absent from the image, so the kubelet creates
them owned by the assigned fsGroup.

The RBAC is namespaced: a Role and RoleBinding in the demo's own project, which an ordinary project
admin may create. Nothing here asks for a cluster-scoped grant.

### Monitoring: Prometheus & Grafana, published as a Route

`prometheus-grafana` monitors deploy here, and a cluster binds to one exactly as it does on the
cloud platforms — through a `connector_templates` entry of type `otel-collector`, which rides beside
the cluster and forwards its metrics.

The monitor entry is the `gke`/`eks` field set **minus** `k8s_node_pool_template` and the
`num_nodes`/`min_nodes`/`max_nodes` trio; the connector template likewise drops its node pool. Both
absences are the same fact: this platform sizes no pools.

**Grafana is reached by a Route, not a LoadBalancer.** A LoadBalancer Service needs the cluster to
have cloud load-balancer integration, and an attached one may have none — OpenShift Local has none,
and a Service there stays `Pending` for ever — whereas every OpenShift cluster has an ingress router.
The manifest names no host, so the ingress operator generates
`grafana-<namespace>.<cluster ingress domain>`; `deployMonitor` reads it back and prints it. That
also gives a stable hostname across redeploys, which is what `proxies` provide on the cloud
platforms — and is why a proxy targeting an `ocp` monitor is refused rather than silently useless.

`deployClusterMonitoring -PclusterName=<c> -PmonitorName=<m>` deploys the collector; **both** names
are required.

**Control Center is not offered.** Its images have not been measured under `restricted-v2`, and the
tag the toolkit's own configuration names — `2024.4.0` — no longer exists on Docker Hub, whose
published tags now start at `2025.x`. Worth fixing on its own terms before it is offered anywhere.

### Out of scope in this release

Control Center, databases, CDC connectors, data generators, message brokers, proxies and DCR. Each
is refused **during validation** with a message naming the way out, not at deploy time.

The manifest-level blocker is gone: `prometheus-statefulset.yaml` and `kafka-statefulset.yaml` no
longer pin a UID, and both were measured under `restricted-v2`. What each image needs differs, and
the difference is worth knowing before anyone offers these elements here:

| Image | Under an arbitrary UID |
|---|---|
| `prom/prometheus` | works once the pin is gone — TSDB starts, volume group-writable |
| `grafana/grafana` | works, needed nothing |
| `apache/kafka` | needs **more** than the pin gone: it ships `/opt/kafka/config` and `/opt/kafka/logs` owned by uid 1000 rather than group-0-writable, and its entrypoint writes to both. An init container seeds the config into an emptyDir mounted over it, and a second emptyDir shadows the log directory |

That is the general shape of the remaining OpenShift work: the manifests are the easy half, and
whether a third-party image tolerates an arbitrary UID has to be measured image by image.

### The wizard does not scaffold this platform

`-Pwizard.platform=ocp` is refused by name. Unlike `docker`, this platform *has* an account, a region
and a disk class — they just belong to whoever built the cluster, and the one thing the interview
would need, the kubeconfig context, cannot be discovered or guessed. See
`WizardIntent.SCAFFOLDABLE_PLATFORMS`.

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

⚠️ **Four different spellings, and none is a typo.** `deployDataGenerator` / `teardownDataGenerator` / `warmupDataGeneratorPool` take the project property **`-PdataGeneratorName`** (`GridGainDemoPlugin.kt:410`); `dataGenerate` takes the Gradle option **`--dataGenerator`**; the cluster is **`--targetCluster`** as a Gradle option but reaches the generator as **`--target-cluster`**; and the key-space stripe is **`--instanceIndex` / `--instanceCount`** as Gradle options but reaches the generator as **`--instance-index` / `--instance-count`** (`--mode=local` only since v22 — on `hosts` the plugin derives the fleet's stripes and refuses the flags). The camelCase→kebab split in the last two is the same rule both times: the Gradle option is the toolkit's, the kebab flag is the generator's own CLI. `InstanceStripe` holds all four spellings as constants and is the only place that translates — do not restate either form at a launch site. `dataGeneratorTeardown` is keyed on the run, not the element: `--runId` / `-PrunId` only, and it takes **either the run group or any one instance id** — a host run is a fleet whose records are keyed per process (`<group>-i0`, `-i1`), and it tears down the whole group whichever you pass.

⚠️ **A multi-process host load test is now configuration, not repeated invocations.** Set
`host_instances_per_host` on the generator (and give its infrastructure more machines if you want the
load spread), then run `dataGenerate` **once**. The plugin derives the whole fleet — machines x
instances — and assigns every process a disjoint key-space slice, so the indices cannot be duplicated
by hand.

```yaml
data_generators:
  payments-load:
    platform: hosts
    infrastructure: power-gen        # every enabled machine on it runs the generator
    host_distribution: datagen-gg8
    host_instances_per_host: 4       # 4 processes on each machine
    host_timeouts: { unit_active: 120 }
```

```bash
# one invocation; starts 4 processes per machine, each with its own slice
./gradlew dataGenerate --scenario load --targetCluster=power-payments \
  --mode=hosts --dataGenerator=payments-load
```

- **Reach for the generator's own `concurrency` first** (ops.yaml, v8+): threads inside one JVM are far
  cheaper than whole JVMs, and until v8 a generator process was single-threaded and therefore capped by
  GG round-trip latency no matter how many you launched. Use `host_instances_per_host` when one process
  can no longer saturate its machine, or to spread load across machines.
- **`--instanceIndex` / `--instanceCount` are now refused on `--mode=hosts`**, at plan time. They were
  the old way to divide the key space by hand; the generator now derives it, and two sources of truth
  for the same thing is how a slice gets silently discarded. They remain valid for `--mode=local`. The
  message names `host_instances_per_host` as the replacement.
- **One run group, one run.** Every process of a run reports under the same run group, so a single
  `set_rate` or `stop` from the UI reaches all of it and `dataGeneratorTeardown -PrunId=<group>` stops
  the whole fleet. Each process still has its own runId (a systemd instance name and an output
  directory cannot be shared) and its own record in `deployment.yaml`, tied together by `runGroup`.
- **Refused for a distributed (`distribution:`) in-cluster run**, at plan time, before any manifest is
  written. That path runs under the generator's Coordinator, which partitions the key space from
  `partition_count`; a second answer would disagree.
- **The symptom of getting striping wrong is not an error.** Measured on real hardware: 32 unstriped host
  processes against a 2-node GG8 cluster settled at 93 ops/s and 498 ms with **zero errors**, idle CPU
  on both hosts, server pools at `active=0, qSize=0` — and 50M+ operations left 383 MB of data. That is
  what the plugin-assigned stripes exist to make unreachable. See the generator skill's gotcha 11.
- ⚠️ **`--mode=hosts` needs the unit re-installed after upgrading the plugin.** The unit reads
  `--run-group ${RUN_GROUP}` from the per-run `run.env`; it used to read `%i`, the systemd instance
  name. A unit installed by an older `deployDataGenerator` therefore makes every process its own run
  group of one, so a `set_rate` re-paces a single JVM and a `stop` ends one process — both accepted,
  neither reported. The stripe rides in the same file as `INSTANCE_ARGS`, read unbraced so systemd
  word-splits it into two flags or none. The unit also gained `--instance-id %i`, without which the
  generator mints an id the plugin has never heard of. `teardownDataGenerator` + `deployDataGenerator`
  every element in the same pass as the plugin upgrade.

### Splitting one machine between a cluster and its generator

A `data_generators` entry may name the **same infrastructure as a cluster** — nothing forbids it.
`HostReferenceValidator` rejects two `hosts:` entries sharing an `ssh_address`, which is a
different thing; a generator opens no ports, installs under `$installRoot/<its own name>`, uses
unit `gridgain-datagen-<name>@<runId>`, and reuses the infrastructure's JDK and script library.
So co-locating load with the servers is a configuration change, not a code change.

Pinning the two apart is the part that needed a feature:

```yaml
clusters:
  power-demo:      { host_cpus_per_node: 32 }   # takes cores 0-3 -> CPUAffinity=0-31
data_generators:
  power-gen-load:  { host_cpus_per_host: 32 }   # takes cores 4-7 -> CPUAffinity=32-63
```

- ⚠️ **`CPUAffinity` restricts, it does not reserve.** Pinning only the cluster leaves generator
  threads scheduled onto the server's CPUs anyway. Both sides must be pinned.
- **Whole physical cores, not disjoint CPUs.** Handing the generator the SMT threads the cluster
  did not take would satisfy a set-intersection check while putting a generator thread on *every*
  server core, competing for its L1, L2 and issue slots. So a cluster that shares its machines
  switches from the spread allocation to whole cores — `coLocatedGeneratorCpus` on its spec,
  resolved at assembly from any pinned generator on the same infrastructure.
- **The generator's offset is derived, never typed.** The assembler finds the co-located capped
  cluster and records `reservedCpus`; the generator's mask starts after those cores. A typed
  offset would be a third number that must agree with the other two, with nothing checking it.
- `host_cpus_per_host` is **per machine and shared by every `host_instances_per_host` instance** —
  one template unit renders one mask and all `@<runId>` instances inherit it.
- ⚠️ **Two capped clusters on one infrastructure** already overlap each other (both start at the
  first core). A pinned generator there is refused at validation, naming both.
- `deployDataGenerator` warns when the cluster is capped and the generator is not (the state every
  config is in after upgrading), when the generator is pinned and the cluster is not, and when the
  two together ask for more CPUs than a machine has.
- The mask reaches the JVM: `Runtime.availableProcessors()` follows it, so the generator's pool
  sizing and `ops.yaml` `concurrency` are measured against the pinned set.

### Capping a host cluster's CPUs (`host_cpus_per_node`)

Optional, on a `platform: hosts` **cluster** (not its template — how much of a machine *this
deployment* may use is a property of the deployment). Rendered as the unit's `CPUAffinity`.

- ⚠️ **PER NODE.** The mask is applied on every machine, so 3 machines × 16 presents **48** to the
  licence. The licence counts the cluster, not the machine.
- **This is a licence control, measured not assumed.** GG8's `GridEntLicenseProcessor` counts
  `Runtime.availableProcessors()` summed across the topology, and `sched_setaffinity` moves it.
  Verified on the Power lab 2026-09-20 by capping a two-node cluster one node at a time and
  reading its own log line: `Maximum number of CPUs (128/64) is exceeded` → `(96/64)` → no
  violation. `deployCluster`'s over-capacity warning now names the key and works out the value.
- **The CPUs are chosen spread across cores, not as `0-(n-1)`.** On ppc64le at SMT=8 a core's
  eight threads are numbered consecutively, so a contiguous range of 32 is four whole cores with
  four idle; x86 generally numbers the other way. Each machine's CPU→core map is recorded by
  preflight (`cpu_topology`) and `CpuAffinity` picks round-robin by core.
- ⚠️ **A machine prepared before that fact existed has no map**, and a capped cluster then refuses
  to render rather than guessing. Re-run `deployInfrastructure` for the cluster's infrastructure.
- A cap above a machine's CPU count is **warned about, not refused** — one cap covers every
  machine and an infrastructure may be uneven. The node runs on the whole machine there, and
  `coreDemandOf` counts `min(observed, cap)` so the licence figure never credits an inert cap.
- ⚠️ **A hand-made systemd drop-in overrides what the plugin renders, silently.** If you capped a
  cluster by hand while testing, delete
  `/etc/systemd/system/gridgain-<instance>.service.d/*.conf` before relying on this key.

**Every mode names its cluster.** Since ops schema v7 removed `ops.yaml`'s `targets:` block, `--targetCluster` is required in all three modes and is the only thing that says which cluster a run writes to. The GridGain flavour is derived from it (`TargetResolution.resolveTarget`, which reads `ConfigurationQueries`, **not** ops.yaml), so the classpath, image or archive follows the cluster you name rather than a field in the ops file. A host run additionally needs *which machine* and *which installed archive*, which only the `data_generators` entry says — hence `--dataGenerator` on top.

**Deploy installs, the run starts** — and that split is what makes the deploy idempotent. `deployDataGenerator` puts the archive and a systemd **template** unit in place; `dataGenerate` starts an instance; `dataGeneratorTeardown` stops it. Consequences worth knowing:

- **The unit is `gridgain-datagen-<name>@`, not `gridgain-datagen@`.** The element name is in the filename deliberately: two generators on one machine would otherwise install the same template unit at the same path with different rendered contents, and the second deploy would silently overwrite the first.
- **Deploy readiness is `systemctl cat`, not `systemctl is-active`.** A template unit has no instance until a run starts one, so `is-active` reports `inactive` on a perfectly good install — and the generator binds no socket anywhere, so there is nothing to probe either.
- **Host run state is three distinct variants** — `HostRunning`/`HostFailed`/`HostCompleted` — not the k8s records with nullables. A host run has no namespace, replica count or image; those are questions that do not apply. A `DataGeneratorRunRecord` interface carries what all six share. (The UI's run card renders them already but still shows namespace/replicas; host name and unit instance are what it should show.)
- **The run's choices arrive in a per-run `run.env`, not in the unit.** `ExecStart` is rendered at *deploy* time and `%i` (the runId) is its only run-time variable, so `--target-cluster` and `--scenario` could not be baked in. `dataGenerate` writes `<runs_root>/<runId>/run.env` carrying `TARGET_CLUSTER=`, `SCENARIO=`, `RUN_GROUP=`, `INSTANCE_ARGS=`, `BROKER_ARGS=` and `OTEL_RESOURCE_ATTRIBUTES=`, and the unit reads it with `EnvironmentFile=` — deliberately **without** a leading `-`, so a missing file fails the start rather than launching with an empty cluster. Ordering is load-bearing: the file is pushed after the run-directory script and before `systemctl start`, because systemd opens it at start.
  - **`OTEL_RESOURCE_ATTRIBUTES` is read by the generator, not by systemd** — it is never interpolated into `ExecStart`, it just reaches the JVM's environment, so it needs no unit change and works on a unit of any age. It carries `service.instance.id` (the runId), `service.namespace` (the infrastructure name, which is what the GG8 node also sets, so both land in one namespace), `host.name`, `gridgain.demo.cluster` and `gridgain.demo.scenario`. Without it every process on the platform exported one identity — `service.name` alone — so the instances of a fleet **overwrote each other's series** and the gauges flapped between them. `service.name` is deliberately not set: the generator applies this variable over its own built-in, so naming it would split one dashboard into one series per run.
  - ⚠️ **An attribute Prometheus does not promote is dropped in silence.** `templates/hosts/monitor/prometheus.yml` lists all five in `promote_resource_attributes`, but a **monitor deployed before that change keeps its own copy** — `service.instance.id` and `service.namespace` were already promoted for the node's sake, the other three were not. `dataGenerate` prints which ones need a monitor redeploy on every host run; there is no drift detection, deliberately (it would be an ssh round trip on the happy path to print a shorter sentence).
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
- **Every launch path passes `--run-group`** (required by the generator). The plugin's runId is the group for a `dataGenerate` run — single-pod Job, distributed Deployment, local fork and the systemd unit all use it, so a fleet's live metrics aggregate correctly and one control command reaches all of it. The long-lived **element** Deployment is the exception: it has no runId, so its group is `element-<name>`, stable across scaling.
- **Every launch path except the local fork also passes `--instance-id`**, the *per-process* id: `%i` in the hosts unit (where the systemd instance name genuinely is this process's identity — the opposite of the `--run-group %i` bug above, which asked a per-process name to stand for the fleet) and `$(POD_NAME)` on both Kubernetes paths, the same string those manifests give `service.instance.id`. Without it the generator minted its own `RunId`, so the process the plugin started as `…-i0` reported itself as `20260919-203407-wiftm5` and the Load page row, the systemd unit, the run directory and the Grafana series were four names for one thing with nothing joining them. The local fork keeps the minted id: there is no launcher-side identity worth imposing.

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

## ⚠️ `host_cpus_per_node` is a throughput knob, not just a licence knob

Capping a GG8 cluster's CPUs moves `Runtime.availableProcessors()`, and Ignite
derives **every** default pool size from that number — `pubPoolSize`,
`sysPoolSize`, `stripedPoolSize`, `qryPoolSize`, and critically
`ClientConnectorConfiguration.threadPoolSize`, which backs
`GridThinClientExecutor` and is `max(8, availableProcessors)`. The node logs all
of them in its `IgniteConfiguration [...]` startup line.

That pool is the cluster's throughput ceiling, because **each thin-client
request holds one of its threads for the whole request**, including the time
spent waiting on a synchronous replica round trip. So:

- maximum throughput ≈ **(CPUs × nodes) ÷ per-request latency**, and the
  measured knee lands exactly on `CPUs × nodes` — 128 operations in flight for
  two uncapped 64-CPU nodes, 64 when the same pair was capped to 32.
- the CPU looks idle at the ceiling (~12 of 64 busy) because those threads are
  *waiting*, not computing. Idle CPU is not spare capacity here.
- **capping costs throughput directly.** Measured on the Power lab: halving the
  servers to 32 CPUs took peak throughput from 219,388 to 168,265 ops/s (−23%),
  while the capped servers used only 27% of the CPUs they were still allowed.

Use it to fit a licence (§licence gotcha) or to isolate a co-located generator —
not in the expectation that the freed CPU buys anything elsewhere.

**To move the pool without touching the cores, use `host_thread_pools`** on the
hosts cluster template (v27+). Every key is optional; omitting one leaves
Ignite's default. `client_connector` is the one that sets the ceiling:

```yaml
cluster_templates:
  power-gg8:
    host_thread_pools:
      client_connector: 256   # ClientConnectorConfiguration.threadPoolSize
      striped: 128            # IgniteConfiguration.stripedPoolSize
```

Also accepts `public`, `system`, `query`, `data_streamer`, `rebalance`. Each has
`minimum: 1` so 0 is unreachable from a file and can only mean absent — a
literal 0 configures a pool with **no threads** rather than falling through to
the default, and `additionalProperties: false` rejects a mistyped pool name that
would otherwise tune nothing in silence. `client_connector` renders inside the
`ClientConnectorConfiguration` bean and the rest on `IgniteConfiguration`; both
beans have a property called `threadPoolSize`, and Spring accepts it on either.

⚠️ These are **not** reachable through `host_jvm_opts` — they are Spring bean
properties with no `IGNITE_*` system-property equivalent, which is why they
needed a config surface of their own.

## Config-drift detection on redeploy

Each per-element `Deploy*Action` records a SHA-256 fingerprint of its
`demo-config.yaml` block (the YAML node at `<kind>.<name>`, canonicalised so
key order/whitespace/comments are ignored) into the matching `Deployed*`
record's `config_hash` field. On the next deploy, the action compares the
current fingerprint to the recorded one:

- **Match** (or no recorded hash yet) → action proceeds normally and stamps
  the current hash on success.
- **Mismatch** → action logs a warning and **skips the element**. The
  deployment.yaml record stays as-is. ⚠️ **The task still SUCCEEDS** — the
  warning is printed and the build reports BUILD SUCCESSFUL, so a script that
  checks the exit code sees nothing wrong and goes on to measure, or deploy
  against, a stale element. Verify the rendered artefact (or read the value
  back off the machine), never the return code. This cost a benchmark run that
  reported a whole configuration's worth of numbers for a generator whose
  systemd unit had never been updated. The walker (`deployAssembly`) appends
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
  GG9 needs no equivalent care: its exporter already sends undotted names, so they arrive bare
  (`AvailableProcessors`, `LoadAverage`) and the same settings serve both versions. What GG9 *does*
  leave odd is identity — `job` and `service_name` are the cluster's UUID, because that is what it
  puts in `service.name`; `instance` is still the node name, which is what the dashboards group by.
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
- **Setting `host_otel_endpoint` changes the delivered archive — on GG8.** It derives
  `ignite-opentelemetry` into the module list, and that list decides what is shipped, so the next
  cluster deploy reinstalls the distribution. A *running* GG8 node does not pick the exporter up at
  all: it is wired into `ignite-node-cfg.xml` at node start, so this needs `teardownCluster` +
  `deployCluster`. **None of that applies to GG9**, which has no module list and takes the exporter
  as a live cluster-configuration update — see **GG9 on hosts**.
- A generator run at the ops.yaml default rate on a single pod barely taxes GG — scale **pods** (`distribution.replicas`) to saturate, and divide the rate accordingly.
- `transaction_scope: business_event` against the default ATOMIC SQL caches rolls back every write (GG8 8.9+) — see the generator skill.
- CDC connector names are `<cdc_connectors-entry>-<connectors[].name>` (e.g. entry `mainframe-to-gg` + `cdc-sink` → `mainframe-to-gg-cdc-sink`), not the bare inner name.
- **`hosts`: `OPTION_LIBS` does not exist.** It is a feature of the GridGain *Docker image's* entrypoint. In a tarball an optional module must be physically copied out of `libs/optional/<module>` into `libs/`, which is what `host_modules` drives. A module the config forgets shows up as a `ClassNotFoundException` at node start.
- **GKE needs three GCP APIs enabled, and enabling them is itself a permission.** `container`, `compute` and `iam` `.googleapis.com` — all three; `container` alone gets a project far enough to look right and not far enough to build anything. Beware `containeranalysis.googleapis.com`, which is a different service and reads almost identically. `gcloud services enable <api> --project=<p>` answering `PERMISSION_DENIED ... serviceusage.services.enable` means the account can list services but not enable them: that needs `roles/serviceusage.serviceUsageAdmin` (or Owner/Editor) from an administrator. The wizard checks all three on the project before the interview ends; `GcpRequiredApis` is the one list both it and the deploy-time step read.
- **k8s GG8: metric export is gated on the image tag, at 8.9.33.** The exporter bean's class lives in `ignite-opentelemetry`, which first ships in that version. The node configuration renders the `metricExporterSpi` bean *and* names the module in `OPTION_LIBS` only when the cluster image is 8.9.33 or later, so an older pin costs metrics rather than the cluster — naming a module the image does not carry used to kill every node before the grid started, on any monitor choice including none. Binding such a cluster to a `prometheus-grafana` monitor is still refused at validation, with both versions in the message. `standard-images.yaml` defaults above the floor and `StandardImagesTest` holds it there.
- **EKS: eksctl-created IAM resources do not inherit the demo's `Owner` tag, so the toolkit adds it itself.** eksctl stamps `alpha.eksctl.io/cluster-name` and `alpha.eksctl.io/eksctl-version` on what it creates and nothing else. The EBS CSI driver's role now gets `--tags` on `eksctl create iamserviceaccount`, and the **IAM OIDC provider** — whose `associate-iam-oidc-provider` has no tag flag at all — is tagged afterwards with `aws iam tag-open-id-connect-provider`, which merges, so eksctl's tags survive. Both stages are **best-effort**: they warn with the by-hand commands rather than failing a cluster that is already up. Two things follow. The provider is an *account-level* resource that no CloudFormation stack owns, so it outlives a cluster deleted around the toolkit — five such orphans were found in the shared account. And a cluster built before this change keeps eksctl's tags alone, so a sweep looking only for `Owner` will miss it: search `alpha.eksctl.io/cluster-name` too.
- **A licence caps CPUs, counts *logical* ones, and a cluster over the cap dies quietly about two hours in.** GridGain licences carry `<max-cpus>` (GG8) / `limits.maxCores` (GG9), where `0` means unlimited, plus a `<grace-period>` in minutes. A cluster over the cap **starts and works**, runs the grace/burst period, then shuts nodes down until it fits — *cleanly*: exit 0, systemd recording success, while `deployment.yaml` still says every node is ACTIVE. So it reads as a deliberate stop, not a licence ceiling. Measured on the Power lab: three LPARs, each **8 dedicated Power11 cores at SMT=8 → 64 logical CPUs**, against a `max-cpus: 64` licence — 192 against 64, and the cluster was found on one node at `Grid uptime: 02:01:00`. **The counting unit is the trap**: one 8-core partition consumes a 64-CPU licence, because `nproc`, `availableProcessors()` and the licence checker all see SMT threads. `deployCluster` on `hosts` now warns before installing anything, counting the machines' own CPU counts from the preflight `cpus` fact (`LicenceLimits` + `HostGridGainV8ClusterPlugin.coreDemandOf`); a warning, not a refusal, since a demo shorter than the grace period is unaffected. Two untested mitigations, cheaper than a new licence: lower SMT (`ppc64_cpu --smt=2` → 16 per LPAR, 48 for three) or cap the JVM (`-XX:ActiveProcessorCount=8` in `host_jvm_opts`; OpenJ9 honours it). **Not yet checked on Kubernetes** — what a containerised node reports under a cgroup quota is unverified, and a warning from an unverified model is worse than none. If a hosts cluster shrinks for no apparent reason: `journalctl -u gridgain-<cluster>.service | grep -i licen`, and look for `GridEntLicenseProcessor`.
- **`hosts`: do not copy the k8s JVM options.** The Kubernetes path sets `-XX:+UseG1GC`; IBM Semeru runs OpenJ9, which rejects it outright and refuses to start. `host_jvm_opts` deliberately specifies no GC flag. Deployment log diagnostics recognise `Unrecognized VM option` and say so.
- **`hosts`: a two-site DCR demo needs two infrastructures.** `nodes` must equal the enabled-host count exactly and at most one enabled cluster may occupy an infrastructure, so six machines become two infrastructures of three rather than one of six.
- **`hosts`: an `image` source needs a container runtime on the *controller*, never on the machines.** The toolkit pulls and extracts locally, then pushes — the machines are never given a runtime. **Either `docker` or `podman`** satisfies it (podman is argument-compatible for the pull-and-extract calls; the candidates and their preference order live in `tooling/hosts_tool_requirements.yaml` under `any_of_commands`, and `ContainerRuntimes.preferred()` picks whichever works). A demo whose distributions are all files or URLs needs none at all. **Every hosts configuration the wizard writes does need one**, because it sources the JDK and GridGain archives from images rather than inventing download URLs and checksums — so the interview now has its own prerequisite page for it, beside the `tools-hosts` one. It is separate from that page because this requirement is satisfied by *any* of the candidates, where the tools page checks version-ranged commands one at a time.
- **`hosts`: `host_access.auth.kind: key` wants the *private* half, and it must be passphraseless.** Two ways this goes wrong for someone who is not a system administrator, both now checked during the interview and worth knowing outside it. A `.pub` looks like the obvious file and fails at deploy time as `Permission denied (publickey)` — which reads as *the server has not authorised my key* and sends you to edit `authorized_keys` on machines that were never the problem. And a passphrase cannot be supplied: the deploy runs inside a Gradle daemon with no terminal, and there is nowhere in the configuration to keep one (`ssh-keygen -p -f <key>` removes it). `ssh-keygen -y -P "" -f <key>` is the one command that separates all of it — but read its output carefully, because it reports *permissions* before *format*, so a `.pub` at its normal 0644 is answered "Permissions 0644 … are too open", advice that gets you no closer. A leading `~` in the path is fine; ssh expands it itself. The wizard's hosts credentials step now carries the command for making a suitable key and authorising it (`SshKeyAdvice` is the single definition, shared with the check's remediations so the two cannot name different keys); the toolkit does **not** generate key material itself. It **does** authorise an existing key across the machines for you — the reachability page offers it, taking the machines' password once and never storing it, over `ssh-copy-id` (`HostKeyAuthoriser`). Two things about that tool worth knowing if you ever drive it by hand: it is idempotent **only without `-f`**, because the remote snippet appends unconditionally and what prevents a duplicate is the local pre-check; and it runs `restorecon` itself, which is not optional on RHEL — measured under SELinux Enforcing, `/root/.ssh` is `ssh_home_t` while a `mkdir`ed `.ssh` inherits `admin_home_t`, and sshd cannot read `authorized_keys` through the wrong label, so a hand-rolled installer that skips it reports success and leaves key login silently broken.
- **`hosts`: the login user and the user the demo runs as are different, and only the first is asked for.** `host_user` is the SSH *installer* identity; `host_service_user` (default `gridgain`) is what every workload actually runs as — `ensure-identity.sh` creates it with `useradd --system --shell /sbin/nologin --no-create-home`, and the GridGain, Prometheus, Grafana, OTel-collector, Kafka and data-generator units all set `User=`/`Group=` from it. So logging in as root does **not** run GridGain as root. The one unit that is genuinely root is `gridgain-thp.service`, a oneshot writing to `/sys/kernel/mm/transparent_hugepage`. Worth knowing before redesigning anything around root: a non-root login needs NOPASSWD sudo covering `useradd`, the install/data/log trees, systemd units and sysctl drop-ins — and because the privileged work is pushed scripts under the staging root that the login user can write, a *bounded* sudoers rule is escalatable by rewriting the script, so it cannot be made meaningfully weaker than root.
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

- **`docker`: a named volume inherits the image path's ownership, but only if that path exists in
  the image.** Mount a node's work directory at a path invented for the purpose and it arrives
  `root:root`; the node runs as a non-root user and dies at `Failed to create directory for
  partitions storage` before the grid starts — which reads like a disk problem and is a permission
  one. Use `/opt/gridgain/work`, the image's own `GRIDGAIN_WORK_DIR`. Reasoning about this the other
  way round is easy and was in fact how the first version shipped.
- **The GridGain 9 image hard-codes a 16 GiB heap, on every platform.** `JVM_MAX_MEM=16g` and
  `JVM_MIN_MEM=16g` are Dockerfile `ENV` defaults, and the entrypoint turns them into an explicit
  `-Xmx`/`-Xms` — which beats the JVM's own container awareness, so no memory limit corrects it. A
  pod limited to 10Gi still reported a 16 GiB maximum heap on GKE. `docker_jvm_max_mem` exists for
  this reason and is required. Every platform now sets it: `hosts` via `host_jvm_opts`, Docker via
  `docker_jvm_max_mem`, and Kubernetes via `k8s_jvm_max_mem` (v29 — consumed by GridGain 9 only,
  since GridGain 8's image defaults to a harmless `-Xmx1g`). `ClusterSpecAssembler` warns when the
  heap meets the container limit, or takes more than 75% of it.
- **A heap is `5g`, never `5Gi` — and the two sit four lines apart in a cluster template.** The
  value becomes the JVM's `-Xmx` argument verbatim, and the JVM does not speak Kubernetes
  quantities: a node handed `-Xmx5Gi` exits with `Invalid maximum heap size` before it logs
  anything a reader could trace back to a config line, so what you see is a crash-looping pod and
  no cause. `resources.limits.memory` *is* a Kubernetes quantity and `5Gi` is right there. The
  schema now constrains every `*_jvm_max_mem`/`*_jvm_min_mem` to `^[1-9][0-9]*[kKmMgG]?$`, so this
  is a validation error rather than a crash loop. (`2G` is accepted: the JVM reads it as 2 GiB.)
- **`data_storage.size` means different things per platform.** On `hosts` it sizes GridGain 9's
  off-heap data region; on Kubernetes it sizes the **PVC**, and the v9 region sizes are hard-coded
  constants in `templates/k8s/cluster/v9/gridgain-config.conf`. A memory check that added the k8s
  value to the heap would be adding a disk quantity to a memory budget.

## Sources of truth (verify here when exact)

- tasks + options: `src/main/kotlin/com/gridgain/demo/plugin/tasks/*Task.kt`
- schema version + migrations: `…/core/configuration/ConfiguredState.kt`, `ConfigMigration.kt`
- element DTOs + assemblers: `…/core/configuration/Configured*.kt`, `*SpecAssembler.kt`
- JSONSchema: `src/main/resources/schema/*.schema.json`
- host monitor: `…/core/infrastructure/HostPrometheusGrafanaPlugin.kt`, `…/core/specs/MonitorSpec.kt` (`HostPrometheusGrafanaMonitorSpec`), `…/core/configuration/MonitorSpecAssembler.kt` (`HostPrometheusGrafanaSpecAssembler`), `…/core/recording/HostMonitorTemplateModel.kt`, `src/main/resources/templates/hosts/monitor/**`
- JDK provision: `…/core/specs/HostJdkProvision.kt`
- `hosts` platform: `…/core/infrastructure/HostInfrastructurePlugin.kt`, `HostGridGainV8ClusterPlugin.kt`, `HostStepBuilder.kt`, `HostResolvers.kt`, `…/core/deployment/HostClusterDeployer.kt`, `HostClusterDestroyer.kt`, `HostInfrastructureForceDestroyer.kt`, `HostLogDiagnostics.kt`, `…/core/command/SshCliExecutor.kt`, `src/main/resources/templates/hosts/**`
- `docker` platform: `…/core/infrastructure/DockerInfrastructurePlugin.kt`, `DockerGridGainV9ClusterPlugin.kt`, `DockerStepBuilder.kt`, `DockerResolvers.kt`, `…/core/effect/DockerEffect.kt`, `…/core/recording/DockerClusterTemplateModel.kt`, `…/core/specs/InfrastructureSpec.kt` (`ContainerBase`, `DockerInfrastructureSpec`), `…/core/specs/ClusterSpec.kt` (`ContainerClusterBase`, `DockerGridGainClusterSpec`), `…/core/state/DeployedDockerInfrastructure` + `DeployedDockerCluster`, `src/main/resources/templates/docker/**`, `src/main/resources/tooling/docker_tool_requirements.yaml`
- `ocp` platform: `…/core/infrastructure/OcpInfrastructurePlugin.kt`, `OcpGridGainV9ClusterPlugin.kt`, `OcpResolvers.kt`, `K8sStepBuilder.kt` (the `oc` binary and the `--context` flag are its two constructor seams), `…/core/specs/InfrastructureSpec.kt` (`OcpInfrastructureSpec`), `…/core/specs/ClusterSpec.kt` (`K8sApiClusterSpec`, `OcpClusterSpec`), `…/core/configuration/InfrastructureSpecAssembler.kt` (`OcpInfrastructureSpecAssembler`), `ClusterSpecAssembler.kt` (`OcpClusterSpecAssembler`), `…/core/recording/ClusterTemplateModel.kt` (`Platform.OPENSHIFT` renders no fsGroup), `…/core/state/DeployedOcpInfrastructure` + `DeployedOcpCluster`, `src/main/resources/tooling/ocp_tool_requirements.yaml`
- endpoints contract: `src/main/resources/schema/client-endpoints.schema.json`, `…/core/infrastructure/ClientEndpointsWriter.kt`, `…/core/actions/ClusterEndpointPublisher.kt`
- message broker: `…/core/configuration/MessageBrokerSpecAssembler.kt`, `…/core/specs/MessageBrokerSpec.kt`, `…/core/infrastructure/HostMessageBrokerPlugin.kt`, `…/core/deployment/HostMessageBrokerDeployer.kt` + `HostMessageBrokerDestroyer.kt`, `…/core/state/DeployedMessageBrokerState.kt`, `src/main/resources/schema/message-broker.schema.json`
- broker endpoints contract: `src/main/resources/schema/broker-endpoints.schema.json`, `…/core/infrastructure/BrokerEndpointsWriter.kt`, `…/core/actions/MessageBrokerEndpointPublisher.kt` (shared atomic write: `…/core/infrastructure/AtomicEndpointsFileWrite.kt`)
- generator dispatch: `…/core/datagen/InClusterDataGenerateAction.kt`, `DataGeneratorJobManifestWriter.kt`, `DistributedDataGeneratorManifestWriter.kt`, `LocalDataGenerateAction.kt`, `HostDataGenerateAction.kt`, `plugin/tasks/DataGenerateTask.kt`, `DataGeneratorTeardownTask.kt`
- key-space striping: `…/core/datagen/InstanceStripe.kt` (the four spellings, the both-or-neither rule, and `generatorArgs()` — every launch path forwards through it), plus the four forwarding sites: `LocalDataGenerateAction.execute`, `DataGeneratorJobManifestWriter.buildJob`, `HostDataGenerateAction.renderEnvFile` + `templates/hosts/data-generator/gridgain-datagen.service`, and the plan-time refusal in `InClusterDataGenerateAction.planDistributed`
- run records + delete: `…/core/state/DeployedDataGeneratorRun.kt` (incl. `DataGeneratorRunStats`), `DeploymentManager.kt`, `plugin/tasks/DeleteDataGeneratorRunTask.kt`

## Maintenance

This skill documents a moving target. **When you change a Gradle task's options, an element-type schema (incl. a `CURRENT_SCHEMA_VERSION` bump), or how the plugin dispatches the generator, update this file in the same change and bump *Last updated*.** Generator *config* facts belong in the `gridgain-demo-data-generator` skill, not here (keep the plugin→generator direction). Prefer citing a source file over duplicating volatile detail. This rule is also in this repo's `CLAUDE.md`.
