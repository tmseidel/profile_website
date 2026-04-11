---
layout: article.njk
title: "Building an AI Agent for Code Generation: Lessons from 9 Iterations"
description: "Practical lessons learned from developing an agentic AI system that generates source code — from naive prompting to a robust, tool-using agent with diff-based updates and dynamic context management."
date: 2026-04-07
tags:
  - articles
  - AI
  - LLM
  - Agents
  - Java
  - Software Architecture
---

Building software with an AI agent at its core is fundamentally different from traditional application development. Over the course of nine iterations, I developed an AI agent that reads GitHub issues, generates implementation code, validates it, and commits the result — all autonomously. This article distils the key lessons learned along the way.

## The Paradigm Shift: Inversion of Control

The single biggest mental shift when building agentic systems is the **inversion of control flow**. In traditional software, the application owns the business logic and orchestrates every step. In an agentic system, a significant portion of that decision-making shifts to the AI — the surrounding program increasingly acts as a communication partner, executing commands on the agent's behalf.

```mermaid
graph LR
    subgraph Traditional
        App[Application] -->|calls| Lib[Library / API]
        App -->|orchestrates| DB[(Database)]
    end
```

```mermaid
graph LR
    subgraph Agentic
        Agent[AI Agent] -->|requests action| Host[Host Program]
        Host -->|returns result| Agent
        Agent -->|requests tool| Host
        Host -->|executes & returns| Agent
    end
```

Your application becomes, to a large degree, an **execution environment** for the agent. It provides tools, fetches context, applies file changes, and reports results — while the agent takes on much of the reasoning about *what* to do. In practice, the split is not black and white — which is exactly what the next section explores.

## Designing the Agent Flow: What to Keep, What to Delegate

Once you accept the inversion of control, the next critical question is: **which actions belong in your application, and which do you delegate to the LLM?** This is not an all-or-nothing decision — it's a spectrum, and every point on it has trade-offs.

### Keeping Logic in the Application

Deterministic steps — file I/O, git operations, API calls, JSON parsing, diff application — are natural candidates for application-side logic.

**Advantages:**
- **Predictable and fast.** Same input, same output, every time. No API latency, no token cost.
- **Testable.** You can write unit tests with clear assertions.
- **Debuggable.** Stack traces, breakpoints, and logging work exactly as expected.

**Disadvantages:**
- **Rigid.** You must anticipate every edge case upfront. An unexpected file format or an unusual error message breaks the flow.
- **More code to maintain.** Every special case becomes an `if` branch or a new parser.

### Delegating Logic to the LLM

Reasoning tasks — deciding *what* to change, interpreting error messages, choosing a fix strategy, analysing code structure — are where the LLM excels.

**Advantages:**
- **Flexible and adaptive.** The model handles novel situations without explicit programming.
- **Reduces code complexity.** A single prompt can replace hundreds of lines of hand-coded decision trees.
- **Understands intent.** The AI can reason about *why* something should change, not just *what* the syntax rules say.

**Disadvantages:**
- **Non-deterministic.** The same input can produce different outputs on each run.
- **Slower.** Each LLM call adds 5–30 seconds of latency depending on the model and input size.
- **Token cost.** Every delegation costs money and consumes context window space.
- **Hallucination risk.** The model may confidently produce incorrect results.
- **Harder to test.** Assertions on LLM output are inherently fuzzy.

### Finding the Right Split

In practice, the division that worked best for our code generation agent was:

```mermaid
flowchart LR
    subgraph "Application (deterministic)"
        A[File I/O]
        B[Git operations]
        C[Diff application]
        D[JSON parsing]
        E[Tool execution]
    end
    subgraph "LLM (reasoning)"
        F[Code generation]
        G[Error analysis]
        H[Fix strategy]
        I[Choosing validation tools]
        J[Context requests]
    end
    E -->|results| G
    G -->|decisions| A
```

The guiding principle: **if a step requires understanding intent or adapting to ambiguity, delegate it. If it requires reliability and speed, keep it in the application.** As you will see throughout the iterations below, we gradually moved *more* logic to the AI side — not because we wanted to, but because the deterministic alternatives kept failing on edge cases.

## The Tightrope Walk: Context Window vs. Output Quality

One of the most persistent challenges is balancing the context window. Too little context, and the AI hallucinates imports, invents method signatures, or misses existing patterns. Too much context, and the model loses focus, produces lower-quality output, or exceeds token limits.

> The sweet spot shifts with every model generation, but the tension never goes away.

This interplay shaped almost every iteration of the agent.

## The Iteration Dilemma: How Many Loops?

Closely related to the context problem is the question of **how many iterations to allow** between your application and the LLM. LLMs have a remarkable ability to improve their output when given feedback — a compilation error sent back to the model often results in a correct fix on the second attempt. This makes iterative correction loops very attractive.

But iteration comes at a price:

- **Time.** Each round-trip adds 10–30 seconds of latency. Three retry loops turn a 15-second task into a two-minute task.
- **Context bloat.** Every iteration appends messages to the conversation — the error report, the AI's response, the next error report. The context window fills up fast, which degrades output quality (see above).
- **Hallucination drift.** Counter-intuitively, too many iterations can make things *worse*. After three or four failed attempts, the AI tends to "drift" — introducing new errors while fixing old ones, inventing methods that don't exist, or producing solutions that look plausible but are semantically wrong. The model starts optimising for *passing the immediate check* rather than *being correct*.
- **Cost.** Each iteration consumes tokens. With large context windows, a single retry can cost as much as the original request.

### Practical Guards

Through experimentation, we arrived at the following guidelines:

- **Hard caps on every loop.** No open-ended retries. We used 3 rounds for file requests, 5 rounds for code validation loops, and 3 rounds for diff recovery attempts.
- **Progress monitoring.** If the error count isn't decreasing between iterations, abort early. An AI that produces *more* errors after a fix attempt is unlikely to recover.
- **Compaction between rounds.** Summarise earlier turns aggressively to keep the context lean (see Iteration 3).
- **Escalation, not repetition.** If simple "fix this error" prompts fail twice, escalate to a richer strategy — provide more context, rephrase the problem, or fall back to a full file regeneration instead of incremental fixes.

> **Rule of thumb:** If your agent hasn't solved the problem in three iterations, throwing more iterations at it is unlikely to help — you need a different strategy, not more attempts.

## Core Principles

Before diving into the iterations, here are the overarching lessons:

1. **Always give the AI the ability to request more information.** Never assume your initial context is sufficient. Let the agent ask for files, type definitions, or documentation on demand.
2. **Define a protocol in the system prompt for structured output** — but build your application to be resilient against protocol violations. The AI will *sometimes* deviate from the agreed JSON schema, return partial responses, or mix formats. Your parser must handle this gracefully.
3. **The agent drives the reasoning** — your code provides the infrastructure and guardrails.

## Iteration 1 — Naive Generate-and-Validate Loop

The first version was straightforward: send the issue description to the AI, receive generated code, then validate it.

```mermaid
flowchart TD
    A[Issue Description] --> B[AI generates code]
    B --> C[CodeValidationService validates all files]
    C --> D{Errors found?}
    D -->|Yes| E[Build error report]
    E --> F["Send to AI: 'Fix these syntax errors'"]
    F --> B
    D -->|No| G[Commit code]
    D -->|Max retries reached| H[Post warning in issue & commit anyway]
```

**What worked:** The basic loop caught obvious syntax errors and gave the AI a chance to self-correct.

**What didn't work:** The AI frequently generated code that referenced classes, methods, or interfaces it had never seen. Without sufficient context about the existing codebase, the output was often structurally correct but semantically wrong.

## Iteration 2 — Smarter Context Gathering

The root cause from Iteration 1 was clear: the AI didn't know enough about the existing codebase. The `fetchRelevantFileContents()` method was significantly improved:

- **Package awareness:** When a file is mentioned, all files in the same package are loaded.
- **Partial name matching:** The word "Task" in an issue matches `Task.java`, `TaskService.java`, `TaskRepository.java`, etc.
- **Domain structure recognition:** Files in `/domain/`, `/model/`, `/entity/`, `/config/`, `/dto/`, `/repository/`, `/service/`, and `/controller/` directories are included when they relate to the issue.
- **Increased file limit:** From 15 to 30 files.

This gave the AI visibility into existing method signatures, interface definitions, inheritance hierarchies, and repository methods — drastically reducing hallucinated references.

**Lesson:** Context quality matters more than prompt engineering. A perfectly worded prompt with missing context will always lose to a mediocre prompt with complete context.

## Iteration 3 — Conversation Compaction

With richer context and multi-turn code review conversations, the context window filled up fast. After several rounds of back-and-forth, the conversation could easily exceed 100 KB of tokens.

The solution: **automatic compaction** after every code review interaction. The system retains only the last four messages plus a short summary of the earlier conversation.

```mermaid
flowchart LR
    A["100 KB+ conversation"] --> B[Compaction]
    B --> C["Summary + last 4 messages"]
    C --> D["~10 KB context"]
```

**Lesson:** LLMs work best with focused context. Aggressively summarise historical turns — the AI doesn't need the full transcript, just the current state and a brief recap.

## Iteration 4 — Prompt Deduplication

A careful audit of all prompts revealed massive redundancy:

- Instructions already present in the system prompt were repeated in every user prompt.
- The full repository tree was sent with every continuation, even though the AI already had it from the previous turn.
- Verbose formatting instructions (Markdown headers, extra blank lines) were duplicated.

**Changes made:**
- `"Output your response as a JSON object with the structure described in the system prompt"` → `"Output JSON per system prompt format"`
- `treeContext` removed from `buildContinuationPrompt` — the AI retains it from the conversation history.
- Repeated formatting directives eliminated.

**Lesson:** Treat your prompts like production code. Audit them for duplication, dead instructions, and unnecessary verbosity. Every wasted token is context the AI could have used for actual reasoning.

## Iteration 5 — Diff-Based Updates and Dynamic File Requests

This was the most impactful single iteration. Two major features were introduced:

### Diff-Based Changes

Instead of returning entire files for every small change, the AI now returns **SEARCH/REPLACE diffs**:

```json
{
  "fileChanges": [
    {
      "path": "src/main/java/com/example/Task.java",
      "operation": "UPDATE",
      "diff": "<<<<<<< SEARCH\nprivate String name;\n=======\nprivate String name;\nprivate String description;\n>>>>>>> REPLACE"
    }
  ]
}
```

A new `DiffApplyService` applies these blocks to the actual file content.

### Dynamic File Requests

The AI can now respond with a **file request** instead of code changes:

```json
{
  "summary": "Need more context about the repository interface",
  "requestFiles": ["src/main/java/com/example/TaskRepository.java", "pom.xml"]
}
```

The host program fetches the requested files and continues the conversation.

**Token savings were dramatic:**

| Scenario | Before | After | Saving |
|---|---|---|---|
| Small change in a 500-line file | ~500 lines | ~10 lines (diff) | ~98% |
| Follow-up without new files | Tree + file list | Only comment | ~90% |
| Iterative requests | All files again | Only requested files | ~70% |

**Lesson:** Give the AI the tools to be efficient. Diff-based output and on-demand file requests transform a chatty, wasteful interaction into a focused, surgical one.

## Iteration 6 — Robust Diff Application

Real-world diffs from the AI are messy. The `DiffApplyService` had to handle numerous edge cases:

- **Empty SEARCH blocks** — content is appended to the file.
- **Placeholder comments** like `/* Add existing... */` — treated as append operations.
- **Append patterns** — when the REPLACE block starts with the SEARCH content and adds more, only the new part is appended.
- **Trailing whitespace differences** — a fuzzy match is attempted before failing.

Additionally, the `IssueImplementationService` was ignoring AI responses that contained `requestFiles` but no `fileChanges`, returning `null` instead. The fix:

- Detect `requestFiles` even when `fileChanges` is empty.
- Fetch the requested files and continue the conversation.
- Allow a maximum of **three rounds** of file requests to prevent infinite loops.

**Lesson:** The interface between AI output and your application is inherently fuzzy. Build robust parsers, add fallback strategies, and always cap iteration counts.

## Iteration 7 — AI-Driven Validation with Tools

A fundamental architectural change: **remove built-in validators entirely** and let the AI decide how to validate its own output.

The agent prompt was updated to make tool usage mandatory:

> *"IMPORTANT: You MUST include `runTool` in every response that contains `fileChanges`. The bot does not have built-in validators — only you can determine how to validate the code by executing external tools."*

The AI now specifies a validation command (e.g., `mvn compile`, `npm run build`, `gradle check`) alongside its code changes. If it forgets, the host program sends it back with a reminder.

```mermaid
flowchart TD
    A[AI returns fileChanges + runTool] --> B[Host applies file changes]
    B --> C[Host executes specified tool]
    C --> D{Tool output}
    D -->|Success| E[Commit]
    D -->|Failure| F[Send tool output back to AI]
    F --> A
    G[AI returns fileChanges WITHOUT runTool] --> H["Host: 'Please specify a validation tool'"]
    H --> A
```

**Lesson:** The AI often knows better than a hardcoded validator what constitutes "correct" in a given context. A Java project needs `mvn compile`; a Node project needs `npm run build`; a Python project might need `pytest`. Let the agent choose.

### The Tool Selection Problem

Letting the AI choose *which* tool to run immediately raises a thorny question: **which tools do you allow it to execute at all?**

This is one of the hardest design decisions in an agentic system, and the answer should be conservative: **allow the absolute minimum set of tools needed to get the job done.** Every tool you expose is:

- **A security risk.** A build command like `mvn compile` is safe. An arbitrary shell command is not. The distance between "run my tests" and `rm -rf /` is one hallucinated token.
- **A source of complexity.** More tool types mean more parsing, more error handling, more edge cases in your host program.
- **A surface for misuse.** The AI might call tools in unexpected ways, with unexpected arguments, or in unexpected order. The more tools available, the larger the space of possible (and possibly harmful) interactions.

For our code generation agent, the minimal toolset was:

| Tool | Purpose |
|---|---|
| Read file | Fetch source code from the repository |
| Write file / apply diff | Modify source code |
| Execute build command | Validate changes (`mvn compile`, `npm run build`, etc.) |
| Request additional files | Ask for more context |

We deliberately did *not* expose: arbitrary shell access, database queries, network requests, or deployment commands. Each tool that didn't make this list was considered and rejected because it either wasn't strictly necessary or introduced unacceptable risk.

**Sandboxing is essential.** Even with a minimal toolset, run tool executions in an isolated environment. Restrict file system access to the project directory. Set timeouts on build commands. Log every tool invocation for audit. The AI is not malicious, but it is unpredictable — and unpredictable + powerful = dangerous.

> **Principle:** Start with zero tools and add them only when the agent demonstrably cannot complete its task without them. Resist the temptation to expose "just one more" convenience tool.

## Iteration 8 — Resilient JSON Parsing

With complex multi-turn conversations, the AI occasionally produced truncated or malformed JSON — especially near token limits. The `repairTruncatedJson` method was overhauled:

- **Check completeness first:** Verify whether brackets are balanced before attempting any repair.
- **Only truncate genuinely incomplete JSON** — previously, valid JSON was sometimes mangled by premature repair attempts.
- **Add `@NoArgsConstructor`** to all DTO classes to ensure Jackson can deserialize partial objects.
- **Parse `runTool`** as a proper typed object (`AiToolRequest`) instead of a raw map.

**Lesson:** When you define a structured protocol in the system prompt, the AI will follow it *most of the time* — perhaps 95%. Your application must handle the other 5% gracefully. Invest in resilient parsing, not stricter prompts.

## Iteration 9 — AI-Assisted Diff Recovery

Even with all the fuzzy matching from Iteration 6, diffs still sometimes failed to apply — typically because the file had been modified by a previous step in the same conversation, and the SEARCH block no longer matched.

The elegant solution: **ask the AI to resolve it**.

When a `DiffApplyException` occurs:

1. Fetch the current file content from the repository.
2. Send both the current content and the failed diff to the AI.
3. Ask it to produce the complete new file content.

```mermaid
flowchart TD
    A[Apply diff] --> B{DiffApplyException?}
    B -->|No| C[Success]
    B -->|Yes| D[Fetch current file from repo]
    D --> E["Send to AI:\n• Current file content\n• Failed diff\n• 'Produce complete new file'"]
    E --> F[AI returns full file content]
    F --> G[Use directly — no diff needed]
```

This is far more robust than implementing ever-more-complex matching strategies in the `DiffApplyService`. The AI sees the actual current state of the file and can produce the intended result directly.

**Lesson:** When your deterministic code fails, don't add more deterministic complexity — delegate back to the AI. It can reason about intent in ways that string matching never will.

## Summary of Key Takeaways

After nine iterations, these are the principles I'd carry into any agentic system:

| Principle | Detail |
|---|---|
| **Inversion of control** | The agent drives the logic; your app is the execution environment. |
| **Choose the split wisely** | Keep deterministic steps in the app; delegate reasoning to the LLM. Each side has clear trade-offs. |
| **Context is everything** | Invest heavily in smart, dynamic context gathering. |
| **Cap your iteration loops** | LLMs improve with feedback, but after 3 failed attempts, change your strategy — don't just retry. |
| **Let the agent ask for more** | Never assume you've provided enough information upfront. |
| **Define a protocol, but be resilient** | Structured output formats are essential, but the AI will violate them. Build robust parsers. |
| **Minimise token waste** | Use diffs, summaries, and deduplication to keep the context window focused. |
| **Delegate validation to the agent** | The AI knows the build system better than a hardcoded checker. |
| **Minimise the toolset** | Expose only the tools strictly needed. Every additional tool is a security risk and a source of complexity. |
| **Use the AI to fix AI failures** | When diff application or parsing fails, ask the AI to resolve it. |

Building agentic systems is an exercise in designing for uncertainty. The AI is powerful but imprecise. Your surrounding infrastructure must be resilient, adaptive, and willing to hand control back to the agent when deterministic approaches fail. The result is a system that is more capable than either part alone.

