# MCP Quickstart

How to let an AI agent drive this demo toolkit — start the server, register it, and know what it can
and cannot do on its own.

`QUICKSTART.md` is the fast path to a running demo. `README.md` is the reference. This page is only
the MCP server, and assumes you already have a demo configuration.

---

## What this is

The toolkit exposes an **MCP (Model Context Protocol) server** so an agent can inspect your demo and
run toolkit tasks — the same tasks you run with `./gradlew`.

It is **not a separate process**. It is an endpoint on the demo UI's web server: one process, one
port, one lifecycle. That matters for more than tidiness. Some tool calls need a human to approve
them, and the approval surface is the UI — so the server that refuses the call is the server that
shows you the button.

## 1. Start it

```bash
./gradlew launchPluginUi
```

That is the whole step. The MCP endpoint comes up with the UI; there is no separate task, flag or
config file for it.

On a port other than the default 8080:

```bash
./gradlew launchPluginUi -PuiPort=8099
```

## 2. Register it with your agent

**Read the startup output.** The server prints the exact command, already filled in with your
generated token:

```
MCP endpoint: http://127.0.0.1:8080/mcp (loopback only)
  Register it with:
    claude mcp add --transport http gridgain-demo http://127.0.0.1:8080/mcp \
      --header "Authorization: Bearer <your-token>"
  The token is stored as 'mcp-auth-token' in <runtime directory> and survives restarts.
```

Copy that command and run it in another terminal. Don't type the URL from this page — if you changed
the port, the printed one is right and this one is not.

For a client other than Claude Code, the three things it needs are:

| | |
|---|---|
| Transport | Streamable HTTP |
| URL | `http://127.0.0.1:<port>/mcp` |
| Header | `Authorization: Bearer <token>` |

## 3. Check it works

Ask the agent to run **`toolkit_status`**. It reports which demo configuration the server is bound
to. If that comes back naming your config, everything downstream will work.

---

## The token

- **Generated on first start** and stored as `mcp-auth-token` in the demo's runtime directory. It
  survives restarts, so you register once rather than after every launch.
- **Override it** with `-Dmcp.auth.token=<token>` if you need a known value, for example to commit a
  client configuration that several people share.
- **A missing or wrong token** returns `401` with a message telling you where the real one lives.
  If an agent reports being unauthorised, it is this and not a protocol problem.

## Loopback only

The endpoint binds `127.0.0.1` and refuses anything else. An agent on your machine can reach it; a
machine on your network cannot. This is deliberate: the tools below deploy and destroy real
infrastructure, and the token is the only thing between a caller and your cloud account.

If you need an agent elsewhere to use it, tunnel to loopback (`ssh -L`) rather than changing the
bind address.

---

## What the agent can do

**Read-only — safe to let an agent call freely:**

| tool | what it answers |
|---|---|
| `toolkit_status` | which demo configuration this server is bound to |
| `list_demo_elements` | the elements declared in the configuration, by kind |
| `get_deployment_state` | what is *actually* deployed, from the deployment record |
| `validate_demo_config` | does the configuration pass the schemas and cross-element rules |
| `list_task_types` | every task this toolkit can run, with its parameters |
| `get_run_status` | status, warnings and new log lines for a run |
| `request_approval_status` | what happened to a request a human had to approve |
| `read_toolkit_knowledge` | platform specifics and known failure modes |
| `list_config_starters` | starting configurations available here, and what each costs to run |

**Changes things — `deploy_element`, `deploy_assembly`, `create_config_from_starter`.**

**Destructive — `teardown_element`, `teardown_assembly`, `cancel_run`.** Note that `cancel_run` stops
a run in flight but does **not** roll back what it has already done.

## Work is asynchronous, and that is on purpose

`deploy_element` and friends return a **`run_id` immediately** — they do not block until the deploy
finishes, because a cluster deploy takes minutes and an agent waiting on one call is an agent that
has timed out.

The agent polls **`get_run_status`** with that `run_id` for progress and new log lines. If you are
watching an agent work and it looks idle, it is usually between polls.

## Cost and blast radius

These tools create cloud resources that cost money and delete resources that may hold data. The
token and the loopback binding are the controls; the approval prompts in the UI are the stop.

Before pointing an agent at a configuration that deploys to a cloud account, it is worth asking it
for `list_config_starters` first — that reports what each starting configuration costs to run.
