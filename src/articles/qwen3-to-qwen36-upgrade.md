---
layout: article.njk
title: "From Qwen3-32B to Qwen3.6-35B-A3B: Upgrading a Local Inference Stack on 2× RTX 5060 Ti"
description: "A dense-to-sparse model swap that nearly doubled token throughput, improved output quality, and taught us a few things about vLLM with MoE and Mamba architectures."
date: 2026-06-13
tags:
  - articles
  - AI
  - LLM
  - vLLM
  - Self-Hosting
  - Infrastructure
---

# From Qwen3-32B to Qwen3.6-35B-A3B: Upgrading a Local Inference Stack on 2× RTX 5060 Ti

*A dense-to-sparse model swap that nearly doubled our token throughput, made the outputs noticeably better, and taught us a few things about vLLM along the way.*

---

## The Setup

We run a local inference server with two NVIDIA RTX 5060 Ti GPUs — 16 GB VRAM each, Blackwell architecture, connected over PCIe (no NVLink, unfortunately). The whole stack is managed through Ansible playbooks so nothing is done manually and everything is reproducible. vLLM handles inference, Ollama sits on standby for lighter stuff.

Before diving into the models, here's the VRAM math that governs everything we do on this hardware:

```
=== Model Weight VRAM ===

Formula:  params (billions) × bytes_per_param = weight VRAM

fp16 (no quantization):  2 bytes/param
  → 32B model:  32 × 2 = 64 GB  ❌ way too big
  → 35B model:  35 × 2 = 70 GB  ❌ way too big

INT4 quantization (AWQ/GPTQ):  0.5 bytes/param (4 bits = 0.5 bytes)
  → 32B model:  32 × 0.5 = 16 GB  ✓ fits
  → 35B model:  35 × 0.5 = 17.5 GB  ✓ fits

INT8 quantization:  1 byte/param
  → 32B model:  32 × 1 = 32 GB  ⚠️ tight (no room for KV cache)
  → 35B model:  35 × 1 = 35 GB  ❌ doesn't fit

FP8 quantization:  1 byte/param
  → 32B model:  32 × 1 = 32 GB  ⚠️ same as INT8
  → 35B model:  35 × 1 = 35 GB  ❌ doesn't fit


=== KV Cache VRAM (per active sequence) ===

Formula:  context_tokens × bytes_per_token

The KV cache stores attention keys + values for every token in the context.
Size depends on model architecture (num_layers, num_heads, head_dim) and
the KV dtype:

  fp16 KV cache:  ~0.25 MiB per token (model-dependent)
  fp8 KV cache:   ~0.125 MiB per token (half of fp16)

  For our 35B model at 65K context:
    fp16:  65,536 × 0.25 MiB ≈ 16 GB  ❌ eats half our VRAM
    fp8:   65,536 × 0.125 MiB ≈ 8 GB  ✓ manageable
```

With AWQ 4-bit weights (~18-20 GB) + fp8 KV cache (~8 GB for a full 65K sequence) + overhead (~2 GB), we land at roughly 28-30 GB — just under our 32 GB ceiling. That's the budget we're working with.

Our workhorse for months was **Qwen3-32B-AWQ** — a dense 32-billion-parameter model quantized to 4-bit. It did code reviews, general chat, and agent tool-calling just fine inside a 65K-token context window. Reliable, predictable, no complaints.

Then we switched to **Qwen3.6-35B-A3B-AWQ-4bit**. On paper the numbers look similar (35B vs 32B), but under the hood it's a completely different beast. The upgrade turned out to be worth it — but it wasn't exactly a drop-in replacement.

---

## What Changed Under the Hood

### Dense vs. Mixture of Experts

Here's the big one. Qwen3-32B is a **dense** model — all 32 billion parameters fire for every single token. Every forward pass uses the entire brain, so to speak.

Qwen3.6-35B-A3B is a **Mixture of Experts** (MoE) model. It has 35 billion parameters in total, but only about **3 billion are active** per token. The model has a bunch of "expert" sub-networks and a router that picks which experts handle each input. Picture a company with 35 specialists where only 3 get pulled into any given meeting.

The upshot: way less compute per token, even though the model weights take up roughly the same VRAM. That's where the speed bump comes from.

### Hybrid Mamba-Transformer Architecture

Qwen3-32B is a pure Transformer — standard attention, quadratic cost, you know the drill.

Qwen3.6 mixes things up with a **hybrid architecture** that alternates between Transformer layers and **Mamba** (State Space Model) layers. Mamba processes sequences with linear complexity instead of quadratic attention, which is a big deal for long contexts. You get precise token-to-token attention from the Transformer layers where it matters, and efficient sequential processing from Mamba everywhere else.

This hybrid design is also the reason we had to change a bunch of vLLM settings — more on that below.

---

## The vLLM Config Changes (and Why They Mattered)

The architecture shift meant several vLLM parameters needed adjusting. Some were obvious, some were not. Here's the rundown.

### 1. Tool Call Parser: `hermes` → `qwen3_coder`

**What this is:** vLLM needs a parser to translate the model's raw text output into structured tool calls (function names + JSON arguments) that match the OpenAI API format. Different models format their tool calls differently, so the parser has to match.

**What tripped us up:** Qwen3.5 and 3.6 completely changed their tool-calling format. The `hermes` parser that worked perfectly with Qwen3-32B just doesn't understand the new format. The correct one is `qwen3_coder` — yes, confusingly named, but it's the right parser for *all* Qwen3.5/3.6 models, not just the ones with "Coder" in the name.

**What happens if you get this wrong:** This is the nasty part. Tool calls don't break outright — they just get parsed wrong. The model outputs structured calls in the new format, the `hermes` parser mangles them, and tool results get injected back in a format the model doesn't recognize. The result looks like the model suddenly got stupid. It didn't — it's a format mismatch. We spent a while scratching our heads before figuring this one out.

### 2. `max_num_batched_tokens`: New Parameter, Set to 4096

**What this is:** Controls the maximum number of tokens vLLM processes in a single prefill batch — basically how much work it tries to chew on at once when processing input tokens.

**Why we needed it:** The Mamba layers in Qwen3.6 require a memory alignment block size of **2096 tokens**. vLLM's default is 2048. That's less than 2096. You can probably guess what happens:

```
AssertionError: In Mamba cache align mode, block_size (2096)
must be <= max_num_batched_tokens (2048)
```

Server crashes on startup. Not a tuning issue — a hard compatibility floor. Setting it to 4096 gives comfortable headroom and solved it immediately. This is a must-have for any Mamba-based model.

### 3. RoPE Scaling: Just Removed It

**What this is:** RoPE (Rotary Position Embedding) scaling tricks like YaRN let a model handle context windows longer than what it was trained for. Qwen3-32B only natively supports 32K tokens, so we needed YaRN to stretch it to 65K.

**What changed:** Qwen3.6 natively supports up to **262,144 tokens**. Our 65K fits easily. So we just... removed the scaling. Done.

**Bonus:** Without RoPE extrapolation, the model operates inside its trained context range. No more positional confusion in long documents, no artifacts from stretching embeddings beyond their design. This alone improved quality on long-context tasks.

### 4. `max_num_seqs`: 32 → 8

**What this is:** How many concurrent requests the engine keeps alive in GPU memory at once. Each active request needs its own KV cache — the memory structure that stores all the previous tokens' attention data.

**Why we had to lower it:** Here's the VRAM budget math:

```
Total VRAM (2 GPUs):                          32 GB
- Model weights (AWQ 4-bit, TP=2):           ~20 GB
- Overhead (activations, CUDA, etc.):         ~2 GB
----------------------------------------------
Available for KV cache:                       ~10 GB

KV cache per full-length sequence (65K tokens, fp8):
  65,536 tokens × ~0.125 MiB/token ≈ 8 GB

Max concurrent full-length sequences:
  10 GB available ÷ 8 GB per sequence ≈ 1.25
```

So with full 65K contexts, you can barely fit one sequence. But most requests are way shorter than 65K — a typical agent conversation might use 10-20K tokens, which needs only 1-2 GB of KV cache. That's why `max_num_seqs: 8` works: it assumes a realistic mix of context lengths, not everyone maxing out the window at once.

The old value of 32 would have risked OOM errors. For our agent workload (typically 1-3 concurrent requests), 8 is more than enough. If you're running a high-traffic service though, this could be a real constraint.

---

## What Didn't Change

A few settings carried over and are still doing heavy lifting:

- **fp8 KV cache**: Cuts KV memory in half compared to fp16. The single most important setting for squeezing long contexts into 32 GB.
- **AWQ 4-bit with Marlin kernel**: Model weights at 4-bit precision, ~20 GB instead of ~70 GB. The Marlin kernel is optimized for our Blackwell GPUs.
- **Tensor Parallelism (TP=2)**: Each layer is split across both GPUs. Better than pipeline parallelism for our low-concurrency agent workload.
- **Triton attention backend**: Flash Attention is broken on sm_120 consumer GPUs. Triton works fine with the hybrid architecture.
- **Prefix caching**: Reuses KV cache for repeated prompt prefixes (system prompts, tool definitions). Free 50-80% improvement in time-to-first-token for agent workloads.

---

## So, Did It Actually Get Better?

Short answer: yes, noticeably.

### Token Throughput Nearly Doubled

The MoE architecture is doing the heavy lifting here. Only 3B parameters active per token means way less compute per generated token compared to the dense 32B. The Mamba layers add more efficiency on the prefill side since they dodge the quadratic cost of full attention.

In practice: responses come back roughly twice as fast. For interactive use and multi-step agent loops, that's a very welcome improvement.

### Output Quality Stepped Up

- **Code reviews** worked fine with both models — the old 32B was already good at spotting bugs, suggesting improvements, explaining logic. The new model keeps that bar.
- **Minor code refactorings** are where Qwen3.6 pulls ahead. Renaming variables for clarity, extracting helper functions, simplifying conditionals, restructuring imports — these need a nuanced feel for code intent and scope. Qwen3-32B would often over-engineer or miss the point. Qwen3.6 handles these cleanly and stays focused.
- **Tool-calling** is more accurate and consistent now that the right parser is in place. Fewer malformed JSON arguments, cleaner structured output.

### No More Context Weirdness

With Qwen3-32B at 65K, the YaRN scaling would sometimes cause positional confusion — the model would lose track of where information appeared in long documents, especially past the 32K boundary. Qwen3.6, running within its native context range, doesn't have this problem. References to earlier parts of long conversations are just more reliable.

---

## What We Learned

1. **Architecture changes aren't drop-in.** MoE and Mamba need different vLLM settings than dense Transformers. The `max_num_batched_tokens` crash wasn't well-documented — we had to dig into vLLM source to figure it out.

2. **Tool call parsers are model-specific.** Always check this when upgrading between Qwen generations. A mismatch doesn't throw an error — it just makes the model look dumb, which sends you debugging in the wrong direction for a while.

3. **MoE punches way above its weight.** 35B total params, 3B active, quality comparable to dense models many times its active size. For constrained hardware, MoE is the move.

4. **Native context beats stretched context.** Running within the model's native range beats extrapolation every time. When picking models, check the native context window first.

5. **Ansible-managed infra saves your bacon during upgrades.** Every config change — parser swap, new parameter, removed scaling — went through playbooks. The whole migration is reproducible, reversible, and self-documenting. Doing this manually on the server would have made the Mamba crash way harder to debug and rollbacks way riskier.

---

## Quick Comparison

| | Qwen3-32B-AWQ (Before) | Qwen3.6-35B-A3B-AWQ-4bit (After) |
|---|---|---|
| Architecture | Dense Transformer | Hybrid Mamba-Transformer (MoE) |
| Active Params | 32B (all of them) | ~3B (of 35B total) |
| Native Context | 32K | 262K |
| RoPE Scaling | YaRN (to reach 65K) | None needed |
| Tool Call Parser | `hermes` | `qwen3_coder` |
| max_num_batched_tokens | 2048 (default) | 4096 (must be ≥ 2096) |
| max_num_seqs | 32 | 8 |
| KV Cache | fp8 | fp8 |
| Quantization | AWQ (awq_marlin) | AWQ (awq_marlin) |
| Tensor Parallelism | 2 | 2 |
| Attention Backend | TRITON_ATTN | TRITON_ATTN |

---

*Hardware: 2× NVIDIA RTX 5060 Ti 16 GB (Blackwell, PCIe, no NVLink). Inference: vLLM. Infrastructure: Ansible.*
