# Quickstart

The shortest path from nothing to a running setup wizard, and the cloud permissions to ask for
before you start.

`README.md` is the reference — every option, every task, every configuration section. This page is
only the fast path, and deliberately repeats as little of it as possible.

---

## 1. What you need on your machine

Two things:

- **A Java 17 JDK.** [Adoptium](https://adoptium.net/) if you have none.
- **git.**

**You do not need to install Gradle.** This project carries the Gradle wrapper, so `./gradlew`
downloads the exact Gradle it was built against on first use. Installing Gradle yourself is not
harmful, but it is not used — `./gradlew` ignores it.

You do not need the cloud CLIs yet either. The wizard checks for them and tells you which ones your
answers require, so you can install only what your demo actually needs rather than all of them. See
[section 4](#4-cloud-permissions-ask-for-these-in-one-go) for what to line up in advance, because
the permissions are the part with a lead time.

## 2. Clone and start the wizard

```bash
git clone https://github.com/GridGain-Demos/gridgain-demo-template
cp -r gridgain-demo-template my-demo      # your project, not a checkout of ours
cd my-demo

./gradlew launchPluginUi
```

Open **http://localhost:8080**. Use `-PuiPort=9090` for a different port.

There is no configuration file yet, and that is the expected starting state — the landing page
offers to create one. The wizard is an interview: it asks what you intend to build, works out which
requirements follow from that, checks the ones it can check, and writes a
`src/main/resources/demo-config.yaml` annotated with what each entry is for.

Nothing is recorded until you finish, so you can walk through it to see what a given set of choices
would require, and start again.

### If you would rather not use a browser

The same interview runs non-interactively. `./gradlew initDemoConfig` with no arguments reports
every value it needs and the property that supplies it, so you do not have to know the list in
advance. README.md's *Primary path — wizard-driven* section has the worked example.

## 3. Secrets

Anything that is a genuine secret is kept in a SOPS-encrypted file rather than in open text in your
configuration yaml file. Two tools do it: **sops** encrypts and decrypts the file, and **age** holds
the key it uses. The wizard will check for and help you install these tools

Worth knowing before you start: **most demos put nothing in that file.** A licence is a path to a
file, a cloud credential is an account or profile *name* that the CLI you already logged in with
resolves, and a registry token is the *name* of an environment variable. The one thing the toolkit
actually reads out of the secrets file is an SSH password for the `hosts` platform. So a GKE or EKS
demo needs no entries at all — the file still has to exist and be encryptable, which is what the
wizard checks, and the wizard's secrets page names any entries your own answers do require.

This project (i.e. the Toolkit Template) has a `scripts` directory containing the one command that sets it up after the wizard
prompts you to install the tools:

```bash
./scripts/bootstrap-secrets.sh          # from the project root; idempotent
```

This script creates an age key if you have none, writes `.sops.yaml` with your public key, and
creates the encrypted secrets file by encrypting `demo-secrets.yaml.example` directly — so the real
file is born encrypted and never exists as plaintext. That example's entries are commented out on
purpose: they are worked examples of the shape, not requirements. Uncomment what your demo
references and delete the rest.

`README.md`'s *Secrets* section explains the file naming, which is load-bearing: `.sops.` in a
filename means encrypted, and `.gitignore` is built around that so a plaintext secrets file cannot
be committed by accident.

---

## 4. Cloud permissions — ask for these in one go

The toolkit **never** creates cloud accounts, installs CLIs, enables APIs, grants roles or logs you in. Those are
your credentials and your organisation's policy. What it does do is validates access and fail early and say what is
missing — but a permission request that goes to an administrator has a lead time measured in days,
so it is worth sending one complete request before you start rather than one per failure.

Copy the relevant block below into a ticket.

### Google Cloud (GKE)

Two separate things are needed, and the first is easy to miss because it is not an IAM role.

**a. Three APIs enabled on the project.** All three, not just the first:

```
container.googleapis.com
compute.googleapis.com
iam.googleapis.com
```

Check which are already on:

```bash
gcloud services list --enabled --project=<PROJECT> --format='value(config.name)'
```

Beware `containeranalysis.googleapis.com` — it is a different service and reads almost identically
to the one you need.

Enable the missing ones:

```bash
gcloud services enable container.googleapis.com --project=<PROJECT>
```

**Enabling an API is itself a permission.** If that command returns

```
ERROR: (gcloud.services.enable) PERMISSION_DENIED: Permission denied to enable service
permission: serviceusage.services.enable
```

then you hold `serviceusage.services.list` but not `serviceusage.services.enable`. Ask an
administrator either to run the command for you, or to grant you **Service Usage Admin**
(`roles/serviceusage.serviceUsageAdmin`). Owner and Editor also include it.

**b. Roles on the project**, because enabling the APIs unblocks the check and not the deploy. The
toolkit creates and deletes GKE clusters and node pools, creates a Cloud Router and Cloud NAT, and
updates the subnet's Private Google Access:

| What the toolkit does | Role |
|---|---|
| create and delete GKE clusters and node pools | `roles/container.admin` |
| create a Cloud Router and Cloud NAT; update a subnet | `roles/compute.networkAdmin` |
| create a cluster whose node pools run as a service account | `roles/iam.serviceAccountUser` |

Reference: [GKE IAM](https://cloud.google.com/kubernetes-engine/docs/how-to/iam),
[predefined roles](https://cloud.google.com/iam/docs/understanding-roles).

Then, on your own machine:

```bash
gcloud auth login
gcloud config set project <PROJECT>
gcloud components install gke-gcloud-auth-plugin gcloud-crc32c kubectl
```

### AWS (EKS)

The toolkit drives `eksctl`, which builds everything through CloudFormation — so the permissions are
broad by nature, and are eksctl's requirements rather than the toolkit's. `README.md`'s
*Prerequisites* section carries the full worked setup, including creating the IAM user and the
access key; this is the permission set from it, so it can go in a ticket on its own:

| Managed policy |
|---|
| `AmazonEC2FullAccess` |
| `AmazonVPCFullAccess` |
| `AWSCloudFormationFullAccess` |
| `IAMFullAccess` |
| `AutoScalingFullAccess` |
| `ElasticLoadBalancingFullAccess` |

Plus an inline policy allowing `eks:*` on `*`, since no managed policy covers EKS fully.
`IAMFullAccess` is on that list because eksctl creates the cluster and node roles, the instance
profiles, and an OIDC provider for the EBS CSI driver's service account — an EKS cluster cannot be
created without it. If your organisation will not grant it, eksctl's
[minimum IAM policies](https://eksctl.io/usage/minimum-iam-policies/) is the narrower set to
negotiate from.

Then, on your own machine:

```bash
aws configure --profile <my-demo-profile>    # access key, secret, default region, json
aws sts get-caller-identity                  # confirms the profile works
```

Have your **12-digit account ID** to hand — the wizard asks for it, and for the profile name.

### GridGain licences

A GKE or EKS demo needs a GridGain licence file, and Control Center needs its own. If you do not
have them, request access via the [Support Portal](https://it.gridgain.com/portal/22) — also a lead
time, so ask alongside the cloud permissions rather than after.

---

## 5. What good looks like

```bash
./gradlew validateRequirements          # the CLI form of the wizard's prerequisite checks
./gradlew validateDemoConfiguration     # the generated config is valid
```

`validateRequirements` names every missing tool at once, each with where to get it. On a fresh
clone with no configuration it exits cleanly and says so, rather than failing — `check` runs before
you have a config, and a clone you cannot build would be a poor start.

## 6. Using Claude

This project ships two skills for [Claude Code](https://claude.com/claude-code), under
`.claude/skills/`. They load themselves when you run Claude Code from the project root:

```bash
cd my-demo
claude
```

Nothing to fetch, nothing to configure. `/context` will list them if you want to confirm.

| Skill | What it covers |
|---|---|
| `gridgain-demo-toolkit` | Every Gradle task and its parameters, the `demo-config.yaml` element types and how they reference each other, the `gke`/`eks`/`hosts` platforms, schema versioning, and a long list of gotchas |
| `gridgain-demo-data-generator` | The generator's `ops.yaml` / `data.yaml` surface — rate kinds, `transaction_scope`, distribution |

They are worth having because most of what they contain is not guessable. A few examples of the
kind of thing they settle, each of which has cost somebody an afternoon:

- A multi-pod generator's rate is **per pod**, so the fleet total is roughly rate × pods.
- `OPTION_LIBS` does not exist on the `hosts` platform — it is a feature of the GridGain *Docker
  image's* entrypoint, and a tarball install needs `host_modules` instead.
- Do not copy the Kubernetes JVM options to a host: they set `-XX:+UseG1GC`, and IBM Semeru runs
  OpenJ9, which rejects it and refuses to start.

### Asking for the right thing

The skills describe the toolkit, not your demo. Useful openings:

- *"Read the toolkit skill, then add a second GridGain 9 cluster to demo-config.yaml in the same
  infrastructure as the first."*
- *"This deploy failed with ⟨paste the error⟩. What does the toolkit skill say about it?"*
- *"Which tasks do I need to run, in order, to get from this configuration to a cluster with data
  in it?"*

### If you edit them

Don't. Each skill is authored in the repo it documents — the toolkit skill in
`gridgain-demo-gradle-plugin`, the generator skill in `gridgain-demo-data-generator` — and the copy
here is refreshed from there at release time. An edit made here is what the next refresh discards.
If something in one is wrong, that is worth reporting rather than patching locally, because
everyone else has the same copy.

---

## Where to go next

| Question | Where |
|---|---|
| Every task, element type and configuration section | `README.md` |
| Editing the configuration by hand | `README.md` — *Editing the configuration by hand* |
| Adding the toolkit to an existing Gradle project | `README.md` — *Adding the toolkit to an existing gradle project* |
| The data generator's scenarios | `README.md` — *The data generator's scenarios file* |
| Renaming this project | `./rename-demo.sh`, or `README.md` — *Manual rename* |
| What a Gradle task does, in detail | the `gridgain-demo-toolkit` skill — see [section 6](#6-using-claude) |
