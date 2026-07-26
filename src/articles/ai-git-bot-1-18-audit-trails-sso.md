---
layout: article.njk
title: "AI-Git-Bot 1.18 — Audit trails, SSO and the road into your organization"
description: "AI-Git-Bot 1.18 is the release where the bot grows up: OAuth2/OIDC login, a tamper-evident audit trail, outgoing webhooks for your SIEM, Prometheus metrics, deterministic review gates — and a one-command docker run to try it all. Not new AI tricks, but the features that let an AI teammate live inside a real company."
date: 2026-07-26
tags:
  - articles
  - software-development
  - AI
  - DevOps
  - news
  - Git
image: https://raw.githubusercontent.com/tmseidel/ai-git-bot/main/doc/screenshots/webhooks/outgoing-webhooks-overview.png
imageAlt: "AI-Git-Bot admin UI showing the new outgoing webhooks configuration"
---

> Imagine your CISO asking: *"This AI bot that reviews our code — who can administer it, what exactly did it do last Tuesday, and can we prove the record wasn't touched?"*
>
> With **AI-Git-Bot 1.18**, you have an answer. Shipping today. 🚀

---

## First time here? 30-second intro 👋

**AI-Git-Bot is the open-source AI teammate that lives inside your Git tool** — Gitea, GitHub, GitHub Enterprise, GitLab, Bitbucket Cloud. It reviews PRs, writes tests, turns issues into pull requests, keeps docs and translations in sync, and runs E2E suites against preview deployments. Self-hosted, provider-independent (OpenAI, Claude, Gemini, or local Ollama models), and MIT-licensed.

You assign it work the same way you'd assign it to a colleague: request it as a PR reviewer, assign it an issue, or `@mention` it in a comment.

> 👉 Want the long-form pitch? Read **[`doc/pitch/PITCH.md`](https://github.com/tmseidel/ai-git-bot/blob/main/doc/pitch/PITCH.md)** — it's the fastest way to decide whether AI-Git-Bot is for your team.

---

## What's new in 1.18 — the highlights

This release is different. Not one feature makes the AI smarter. Instead, 1.18 answers the questions organizations ask *before* they let software anywhere near their source code. Let's walk through them.

### 🔐 1. OAuth2/OIDC login — meet your identity provider

The admin UI used to have its own little user database with username/password login. Fine for a homelab — a non-starter where credentials must come from a central IdP.

Now the login method is a configuration switch:

- `GITEABOT_SECURITY_LOGIN_METHOD=native` — the existing database login, unchanged. Current installations keep working exactly as before.
- `GITEABOT_SECURITY_LOGIN_METHOD=oauth` — the entire UI authenticates via **OAuth 2.0 Authorization Code flow** against your provider.

OIDC issuer discovery is built in, so **Microsoft Entra ID** and **Keycloak** work by pointing at a single issuer URL — no manual endpoint wiring.

**Why your org will love it:** the bot joins your existing SSO landscape. Admin onboarding and offboarding happen in your IdP, access follows your central policies, and there is no shadow user database left to audit.

### 📜 2. Tamper-evident audit trail — "what exactly happened?"

This is the headline. AI in the development workflow raises a legitimate question from security and compliance teams: *what did the bot actually do — and can we prove it later?*

1.18 introduces a structured, **append-only audit trail** for every PR workflow execution:

- **Full lifecycle coverage** — run started, every step, run completed/failed/cancelled, every review decision
- **Agent tool-call tracing** — every tool the LLM invokes, with sanitized arguments, result summary and duration. You can reconstruct the agent's decision path step by step
- **Cost correlation** — events carry token usage and link to AI usage sessions, connecting *what happened* to *what it cost*
- **Tamper evidence** — every event is chained to its predecessor with a per-run **SHA-256 hash chain**. Insert, alter or delete a record and the chain breaks. The history isn't just stored; it's *provably intact*
- **Configurable retention** — a nightly garbage collector prunes events older than your window (default 90 days, e.g. `AUDIT_RETENTION=P180D`) to match your data-retention policies

And it never gets in the way: auditing is fire-and-forget, it cannot block or fail the workflow it observes.

**Why your org will love it:** this turns "we use an AI bot" into "we can *govern* an AI bot." Internal audits, ISO 27001 / SOC 2 style assessments, post-incident reviews — they all start with *show us the record*. Now there is one, and it's tamper-evident by construction.

### 📡 3. Outgoing webhooks — the bot talks to *your* systems

Until now, AI-Git-Bot only *received* webhooks from Git platforms. It now also **emits** them. Admins configure endpoints under *System settings → Outgoing webhooks* and subscribe each one to the events that matter — workflow started/completed/failed, agent-review findings with their severity, issue-assignment lifecycles for the CodingBot and WriterBot.

![Outgoing webhooks overview](https://raw.githubusercontent.com/tmseidel/ai-git-bot/main/doc/screenshots/webhooks/outgoing-webhooks-overview.png)

Built for enterprise plumbing:

- **Durable, at-least-once delivery** — persisted before dispatch, retries with exponential backoff, survives restarts
- **HMAC-SHA256 signing** per endpoint (GitHub-style), plus optional Authorization and custom headers
- **Scoped subscriptions** — global, per-bot, or per-repository
- **Encrypted secrets at rest** with the same AES-GCM encryption that protects AI provider keys
- **Delivery log with manual retry** in the admin UI

**Why your org will love it:** forward findings to your **SIEM**, open a **ticket** on blocker-severity findings, post to **Slack/Teams** when a workflow fails, feed a custom compliance archive — in real time, without polling. This is the integration point your platform team has been asking for.

### 📊 4. Prometheus metrics — operational visibility

Observability is table stakes for production. The bot now exposes a standard scrape endpoint at **`/actuator/prometheus`**: review and finding counts, workflow run counts and durations, LLM statistics (tool rounds, tool calls, token usage), errors and failures — all with deliberately low-cardinality labels so they behave in real Prometheus deployments.

**Why your org will love it:** the bot shows up in your existing **Grafana dashboards and alert rules** next to everything else you operate. Token-spend anomalies and workflow failure spikes become visible before users report them.

### ⚖️ 5. Deterministic review gates — the LLM advises, the system decides

When the agentic PR review was allowed to submit formal decisions (approve / request changes), the LLM made the final call itself. For a merge gate, a probabilistic decider isn't good enough.

The decision logic has been inverted:

1. The LLM only **classifies findings by severity** — `BLOCKER`, `MEDIUM`, `LOW` — and reports counts
2. The **application** computes the review action deterministically against **thresholds you configure** (e.g. *approve only if `BLOCKER ≤ 0`*)
3. No thresholds configured? The bot posts its review and leaves the review state untouched

Same model, same findings — but the approve/reject decision is now a **reproducible function of explicit policy**, not of model mood.

**Why your org will love it:** you can put an AI review in the merge-blocking path and explain the decision rule to an auditor in one sentence. Policy lives in configuration, not in a prompt.

### 🐳 6. One-command evaluation — curious to running in seconds

Finally, we removed the last evaluation friction. No checkout, no Docker Compose needed for a first look:

```bash
docker run -p 8080:8080 tmseidel/ai-git-bot:latest
```

The container starts with sensible defaults and an embedded H2 database. Docker Compose with PostgreSQL remains the production path — but the first five minutes with the product should never be harder than one command.

---

## The bigger picture: maturity is a feature

Look at the shape of this release:

- *Who can administer it?* — your IdP says so (OAuth2/OIDC)
- *What did it do?* — a tamper-evident audit trail says so
- *How do our systems learn about it?* — outgoing webhooks say so
- *How do we operate it?* — Prometheus metrics say so
- *Can we trust its gates?* — deterministic thresholds say so

Building auditing is a deliberate statement. AI-Git-Bot is not an experiment that happens to run in a company — it is a platform designed to be **integrated into one**. Self-hosted and provider-independent from day one, and now auditable, observable and SSO-enabled, it fits environments where compliance and security aren't afterthoughts but entry requirements.

And since evaluation is a single `docker run` away, the distance between *"interesting project"* and *"running under our own policies"* has never been shorter.

---

## Get it now

```bash
docker run -p 8080:8080 tmseidel/ai-git-bot:latest
```

- ⭐ **Star us on GitHub:** [https://github.com/tmseidel/ai-git-bot](https://github.com/tmseidel/ai-git-bot)
- 📖 **Docs:** [User Guide](https://github.com/tmseidel/ai-git-bot/blob/main/doc/USER_GUIDE.md) · [Audit Trail & PR Workflows](https://github.com/tmseidel/ai-git-bot/blob/main/doc/PR_WORKFLOWS.md) · [Outgoing Webhooks](https://github.com/tmseidel/ai-git-bot/blob/main/doc/OUTGOING_WEBHOOKS.md) · [Deployment](https://github.com/tmseidel/ai-git-bot/blob/main/doc/DEPLOYMENT.md)
- 🐛 **Found something?** [Open an issue](https://github.com/tmseidel/ai-git-bot/issues) — we read every one.

---

**The bottom line:** in 1.18, AI-Git-Bot stops being just the helpful AI teammate and becomes one your security, compliance and platform teams can sign off on. The chores still get done — every PR, forever — but now with SSO, an audit trail, real integrations and deterministic gates around them.

Happy shipping. 🚀
