---
layout: article.njk
title: "Meet AI-Git-Bot 1.7 — the teammate that reviews, tests and ships your PRs"
description: "AI-Git-Bot 1.7 is here, transforming from 'the PR review bot' to the AI teammate your repo has been waiting for — reviewing your code, writing your tests, deploying your previews, cleaning up after itself. The chores that always get cut under deadline pressure? Wire one bot. They get done. Every PR. Forever."
date: 2026-05-21
tags:
  - articles
  - software-development
  - AI
  - DevOps
  - Git
  - CI/CD
image: /articles/meet-ai-git-bot-the-teammate-that-review-ships-test-prs/dashboard_ai_git_bot.PNG
imageAlt: "AI-Git-Bot dashboard showing review, test and deployment workflows"
---

> Imagine opening a pull request and, two minutes later, a bot has reviewed your diff, deployed a fresh preview, written a Playwright test for the feature you just added, run it against that preview, and pasted the report back into the PR — all inside the Git tool you already use.
>
> That's not a roadmap. That's **AI-Git-Bot 1.7**, shipping today. 🚀

![AI-Git-Bot dashboard](dashboard_ai_git_bot.PNG)

---

## First time here? 30-second intro 👋

**AI-Git-Bot is the open-source AI teammate that lives inside your Git tool** — Gitea, GitHub, GitHub Enterprise, GitLab, Bitbucket Cloud. No new dashboard to log into, no Chrome extension, no Slack bot to babysit. You assign it work the same way you'd assign it to a colleague: request it as a PR reviewer, assign it an issue, or `@mention` it in a comment.

It takes over the **necessary-but-uncomfortable** chores that quietly rot every codebase:

- 📝 Writing a *proper* issue with acceptance criteria — before any code is written
- 🔍 Reviewing PRs **consistently**, even when the human reviewer is drowning
- 🧪 Adding the regression test for the bug you just fixed (the one we always say "we'll add later")
- 🛠️ Implementing the boring follow-up tickets (renames, bumps, small refactors)
- 🧹 Tearing down the preview environment nobody remembers spinning up

You pick which chores hurt most this quarter, wire one bot, done. The rest stays exactly as it was.

> 👉 Want the long-form pitch? Read **[`doc/pitch/PITCH.md`](https://github.com/tmseidel/ai-git-bot/blob/main/doc/pitch/PITCH.md)** — it's the fastest way to decide whether AI-Git-Bot is for your team.

---

## What's new in 1.7 — the highlights

### 🎬 1. PRs that test themselves

This is the headline. Tag your bot with the new **Full-stack QA** workflow + tell it where to deploy your PRs, and every pull request now gets:

1. A short **plan** of which user journeys to cover
2. A fresh **Playwright test suite**, generated for *this* PR
3. A **deploy** of your PR to a real preview
4. The suite **run live against that preview**
5. A **report comment** on the PR — pass/fail, screenshots, suite source included
6. Automatic **teardown** when the PR closes

Don't like the suite? Drop a comment: `@bot regenerate-tests focus on the checkout flow`. The bot replans with your feedback. Just need a quick rerun? `@bot rerun-tests`. That's it.

![PR with a Playwright report posted by the bot](gitea-pr-with-e2e-test-run.png )

**Why you'll love it:** the test debt that always slips to "next sprint" finally gets paid down — automatically, per PR.

### 🔌 2. It plays nice with your pipeline (whatever it is)

We added four ways for the bot to deploy your PR — pick the one you already have:

| You're using… | The bot uses strategy… |
|---|---|
| Jenkins / TeamCity / a bash script behind a webhook | `WEBHOOK` |
| Vercel, Netlify, Render, Cloudflare Pages | `STATIC` |
| GitHub Actions, Gitea Actions, GitLab CI, Bitbucket Pipelines | `CI_ACTION` |
| An internal platform team exposing deploys via MCP | `MCP` |

**No need to migrate anything.** The bot adapts to your stack, not the other way around.

### 🧩 3. Workflows you can mix, match and extend

Reviewing PRs and running E2E tests are now just two examples of a bigger idea: **PR Workflows**. Each one is a named, configurable bundle ("Default review", "Full-stack QA", or your own) that you can assign to any bot from the admin UI.

![Workflow configurations admin UI](ai-bot-workflow-settings.png )

Want a custom one — say a license-header check, an SBOM-diff comment, or a "ping the on-call channel on every hotfix PR" workflow? It's a clean extension point now. Your platform team can ship it without forking the project.

### 🗣️ 4. New slash commands, less back-and-forth

Two more commands in the bot's vocabulary:

- `@bot rerun-tests` — re-run the existing suite, no replanning
- `@bot regenerate-tests <your feedback>` — replan the suite, your feedback goes straight into the planner

Combined with the existing `@bot fix …` and `@bot write …`, your PR comments become the remote control.

### 🛟 5. Test suites that can outlive the PR — if you want them to

By default, generated suites are **ephemeral**: they live with the PR, vanish on close, nothing leaks. Safe and boring — exactly what most teams want.

But if you'd love to **keep** the suites the bot writes, flip one setting and pick:

- *commit-to-pr* — committed straight to the PR branch
- *offer-as-pr* — the bot opens a follow-up PR with the suite
- *promote-on-merge* — auto-promoted when the original PR merges

A nightly cleanup job keeps the test folder from turning into a swamp.

### 🔒 6. Tighter, safer, friendlier

A handful of quality-of-life upgrades that you'll feel without noticing:

- **Per-bot tool whitelisting** — give your writer-bot read-only access, your coding-bot the full toolbox
- **Async callbacks** with single-use, HMAC-signed secrets — no shared tokens in your CI runners
- **Force-push safe** — re-pushing three times in a minute no longer confuses the bot
- **Better LLM compatibility** — Gemini 3.x, sanitised tool names across providers, more robust agent loops

---

## What to try first — pick one 👇

You don't need to adopt everything. Start with the one that hooks you:

1. **🚀 The 15-minute upgrade test.** Pull `tmseidel/ai-git-bot:1.7.0`, point at your existing database, watch it migrate cleanly. Your current bots behave exactly like in 1.6. Zero risk, great way to validate.
2. **🎬 The "wow" demo.** Spin up the bundled sample stack — `docker compose -f systemtest/docker-compose-e2e-sample.yml up` — open a PR, sit back, watch the bot plan, deploy, test, report. **This is the one to show your team on Monday morning.**
3. **🔌 Wire it to your real CI.** If you live in GitHub/GitLab/Gitea/Bitbucket pipelines, [`PR_WORKFLOWS_CI_ACTIONS.md`](https://github.com/tmseidel/ai-git-bot/blob/main/doc/PR_WORKFLOWS_CI_ACTIONS.md) is the shortest path to "the bot just tested my PR against a real preview environment."
4. **🧩 Build your own workflow.** Got a chore you keep nagging humans about on every PR? Ship it as a workflow — your team will thank you forever.

---

## Brand new? Start here 🧭

| If you are… | Start with… |
|---|---|
| 👀 **Curious** | [The pitch](https://github.com/tmseidel/ai-git-bot/blob/main/doc/pitch/PITCH.md) — why this exists, what it actually does, how it compares to Copilot Workspace / GitLab Duo / Qodo / Aider |
| 🧑‍💻 **A developer** who wants to play | [Local development guide](https://github.com/tmseidel/ai-git-bot/blob/main/doc/LOCAL_DEVELOPMENT.md) — up and running in ~10 min |
| 🏗️ **An architect** evaluating it | [Architecture overview](https://github.com/tmseidel/ai-git-bot/blob/main/doc/ARCHITECTURE.md) and [agentic workflows internals](https://github.com/tmseidel/ai-git-bot/tree/main/doc/agentic-workflows) |
| 🛠️ **DevOps / Platform** | [Deployment guide](https://github.com/tmseidel/ai-git-bot/blob/main/doc/DEPLOYMENT.md) + [CI action recipes](https://github.com/tmseidel/ai-git-bot/blob/main/doc/PR_WORKFLOWS_CI_ACTIONS.md) |
| 🆙 **Already running 1.6** | [Migration guide 1.6 → 1.7](https://github.com/tmseidel/ai-git-bot/blob/main/doc/MIGRATION_1.6_TO_1.7.md) — short version: drop in, done |

![Bot configuration form](ai-bot-bot-configuration.png )

---

## Get it now

```bash
docker pull tmseidel/ai-git-bot:1.7.0
```

- ⭐ **Star us on GitHub:** <https://github.com/tmseidel/ai-git-bot>
- 🐛 **Found something?** [Open an issue](https://github.com/tmseidel/ai-git-bot/issues) — we read every one.
- 💬 **Just want to say hi?** Drop a discussion on the repo, we love hearing how teams are wiring this up.

---

**The bottom line:** in 1.7, AI-Git-Bot stops being "the PR review bot" and starts being **the AI teammate your repo has been waiting for** — reviewing your code, writing your tests, deploying your previews, cleaning up after itself.

The chores that always get cut under deadline pressure? Wire one bot. They get done. Every PR. Forever.

Happy shipping. 🚀

