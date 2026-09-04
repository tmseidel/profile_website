---
layout: article.njk
title: "Upgrading the Local LLM Stack: From Qwen3.6-35B-A3B to Qwen3.8-27B"
description: "How a model generation jump changed our Ansible-managed vLLM deployment on 2× RTX 5060 Ti — trading a fast 3B-active MoE for a dense 27B model, quadrupling the served context to the full 262K, and what it means for agent harnesses like Hermes."
date: 2026-08-15
tags:
  - articles
  - AI
  - LLM
  - vLLM
  - Self-Hosting
  - Infrastructure
---

# Upgrading the Local LLM Stack: From Qwen3.6-35B-A3B to Qwen3.8-27B

*How a model generation jump changed our Ansible-managed vLLM deployment on 2× RTX 5060 Ti — and what it means for agent harnesses like Hermes.*

---

## 1. What Changed

Our home-lab inference server (2× NVIDIA RTX 5060 Ti 16 GB = 32 GB VRAM, Ryzen 9 9950X, 64 GB DDR5) runs a single Ansible-managed vLLM instance behind an OpenAI-compatible API. Since July 2026 it served **cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit** — a hybrid MoE model: 35B total parameters but only ~3B active per token, mixing Gated DeltaNet linear attention with full attention, 262K native context (git tag `vllm_Qwen3.6-35B-A3B-AWQ-4bit`, commit `66ed291`).

The new configuration serves **Qwen3.8-27B** via the community quant **philbert440/Qwen3.8-27B-W4A16-AWQ**. This is not a routine model bump — the serving economics of the machine changed, and in one important way *against* us:

| Aspect | Old: Qwen3.6-35B-A3B (AWQ) | New: Qwen3.8-27B (W4A16) |
|---|---|---|
| Architecture | Hybrid MoE: 40 layers (30 GDN linear + 10 full attn), 256 experts | Hybrid dense: 64 layers (48 GDN linear + 16 full attn) |
| Parameters | 35B total, **~3B active** per token | **27B — all active** per token |
| Active KV heads | 2 KV heads × 10 full-attn layers | 4 KV heads × 16 full-attn layers |
| Native context (model) | 262,144 | 262,144 — same on paper |
| Context actually served | **65,536** — KV didn't fit for more (see §2) | **262,144 — the full native window** |
| Multimodal | Vision-language (native) | Vision-language (native) — unchanged |
| Speculative decoding | MTP head (multi-token prediction) | MTP head — unchanged |
| Quantization | AWQ INT4 (`awq_marlin` flag) | compressed-tensors W4A16 (auto-detected) |
| Weights on disk | ~20 GB | ~19.5 GB |
| vLLM minimum | any 2026 release | **≥ 0.17** (Qwen3_5 architecture support) |
| Tool-call parser | `qwen3_coder` | `qwen3_coder` — unchanged |

The Ansible changes were small in line count but each one load-bearing: model repo, `vllm_quantization: "none"` (W4A16 compressed-tensors is auto-detected — passing `awq_marlin` would break loading), `vllm_max_num_seqs: 8 → 4`, a vLLM ≥ 0.17 version floor, and a new optional `vllm_speculative_config` for MTP.

## 2. The Real Trade: Speed for Intelligence — and 4× the Usable Context

The honest framing of this upgrade has two halves, and the second one is easy to miss if you only read model cards: yes, both models *natively support* 262K — but the old deployment could never serve it. So the real story is: **we trade raw speed for substantially better answers, and we finally unlock the context window both models always advertised.**

**The context unlock (what actually changed for users).** The old config served `vllm_max_model_len: 65536` — a quarter of the model's native window. Not from lack of ambition: the old MoE's ~20 GB weights left only ~12 GB of KV headroom, and at 64K per sequence with fp8 KV that meant 1–2 full-length sequences before preemption. Raising the limit on paper would have bought nothing the KV pool couldn't back. The new setup changes both sides of the equation: weights shrink slightly (~19.5 GB), and — decisive — the max_num_batched_tokens/block_size constraint and Mamba-cache behavior that capped the old hybrid model are handled cleanly in vLLM ≥ 0.22 with the W4A16 checkpoint. Result: the served window quadruples to the full 262,144 tokens, with KV for **four** saturated 262K sequences (~2.1 GiB each at fp8) in a pool of over a million tokens.

**What got more expensive.** Compute per token scales with *active* parameters, and that number went up ~9× (3B → 27B). Decode speed will drop correspondingly — the old MoE was one of the fastest things you could run on this hardware; the new dense model is mid-pack. KV cost per token also rose ~3.2× (2 KV heads × 10 layers → 4 × 16), though from such a low base that it barely matters at these pool sizes.

**What we get for it.** The largest capability jump this machine has seen — see the benchmark table below. Dense 27B at INT4 simply out-reasons a 3B-active MoE, and the 3.8 generation's gains land exactly on agentic work.

**What stays the same.** Hybrid GDN attention, MTP speculative decoding, native vision, the `qwen3_coder` tool parser, fp8 KV cache, and — on paper — the native context length. Only the paper became reality.

**The VRAM story inverts — in our favor.** The old MoE's routing forces *all* 35B parameters (~20 GB quantized) into VRAM even though only 3B run per token — MoE saves compute, not memory. The dense model needs less VRAM for weights (~19.5 GB), and because we keep `gpu_memory_utilization: 0.95`, the KV pool (~9–10 GiB) backs the full window at **four** parallel saturated sequences — versus one to two at 64K before. Capacity per gigabyte of VRAM went up roughly 8×.

vLLM's recipe measurements on 2× RTX 5090 (same sm_120 Blackwell generation as our 5060 Ti) confirm the class: 377K–920K KV-token pools depending on precision, with the in-checkpoint MTP head reaching 0.75–0.90 draft acceptance. The checkpoint we use was independently validated end-to-end on 2× V100-32GB: 55–59 tok/s single-stream with MTP K=2, ~165 tok/s aggregate at 4-way concurrency, 92.5% draft acceptance. MTP (shipped disabled, one variable away) is the lever that wins back a good chunk of the dense-model decode penalty — 2–3× speedup at ~92% acceptance, quality-neutral.

## 3. Benchmark Comparison

Cross-model-card comparisons need care: Qwen re-evaluates baselines each generation on refined benchmarks, so the two cards' numbers are not produced in one run — treat the deltas as indicative, not exact. The old deployment ran the 35B-A3B MoE; its card compares against its own generation's peers, so we place the two official columns side by side and add Qwen3.6-27B (same-size predecessor on the 3.8 card) as the connecting reference.

| Benchmark | New: Qwen3.8-27B (dense) | Qwen3.6-27B (dense, 3.8 card) | Old: Qwen3.6-35B-A3B (MoE, 3.6 card) |
|---|---|---|---|
| Terminal coding | **73.0** (Terminal Bench 2.1) | 63.4 (TB 2.1) | 51.5 (Terminal-Bench 2.0) |
| SWE-bench Pro (agentic coding) | **61.7** | 53.5 | 49.5 |
| Repo-level codegen | **42.3** (NL2Repo-Bench) | 36.2 (NL2Repo-Bench) | 29.4 (NL2Repo) |
| Agentic SWE (in-house) | **79.0** (QwenSWEBench) | 49.3 | — |
| DeepSWE 1.1 | **42.2** | 13.3 | — |
| Long-horizon work | **70.7** (CoWorkBench) | 61.0 | — |
| Instruction following | **79.5** (IFBench) | 69.1 | — |
| Scientific reasoning | **89.2** (GPQA Diamond) | 87.8 | 86.0 (GPQA) |
| Multidisciplinary reasoning | **30.8** (HLE) | 24.0 | 21.4 (HLE) |
| Competitive coding | **90.3** (LiveCodeBench v6) | 83.9 | 80.4 (LCB v6) |
| Tool/agent use | **68.7**-class gains across the board | — | 68.7 (Claw-Eval Avg) |

Sources: [Qwen3.8-27B model card](https://huggingface.co/Qwen/Qwen3.8-27B) (August 2026, Claude Code harness, temp=1.0, top_p=0.95, 256K context) and [Qwen3.6-35B-A3B model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) (internal agent scaffold, temp=1.0, top_p=0.95, 200–256K context). "—" = benchmark not reported on that card.

On vision-language tasks the old model was no slouch (RealWorldQA 84.1–85.3, OmniDocBench 89.3–89.9 on its card) — vision is *not* new in this upgrade. What is new is agentic vision: Qwen3.8-27B scores **84.3 on OSWorld-Verified** (computer use) vs 63.9 for Qwen3.6-27B, **64.8 WebArena-Verified** (browser use) vs 48.8, and **81.9 AndroidWorld** vs 70.3 — the ability to *act* on screenshots, not just describe them (3.8 card, "VL Performance"; 3.6 card, vision tables).

The pattern: knowledge benchmarks barely move (GPQA 86.0 → 89.2), but everything an agent harness touches jumps by 10–30 points — terminal work, repo-level coding, long-horizon tasks, and computer/browser use. This model was built for doing, not reciting.

## 4. Implications for Agent Harnesses

This is where the upgrade stops being a benchmark story and becomes an operational one. We run Hermes Agent against this server; the same points apply to any OpenAI-compatible harness (OpenCode, Aider, Claude-Code-style loops, LangChain).

**a) Fewer derailments per long task.** Terminal Bench 51.5 → 73.0-class and repo-codegen 29.4 → 42.3 mean the practical thing: agent loops that used to wander off after step N now hold together longer. Expect to raise — not lower — the autonomy you grant the harness (longer unstopped runs, bigger multi-file tasks).

**b) Full 262K context is now actually usable — before, it wasn't.** The old deployment capped sessions at 64K: its KV budget allowed only 1–2 full-length sequences, and every longer agent conversation silently relied on truncation and summarization to survive. The new KV pool holds four saturated 262K sequences. Harness patterns built around scarcity — aggressive history truncation, summarization checkpoints, retrieval stitching — can be relaxed. And it's native context on both models, so no YaRN quality tax anywhere.

**c) Hermes-side config must move with the window.** If your harness has a `context_length`-style setting (Hermes: `model.context_length`, which also drives its compression triggers), raise it from 64K to 262144 to match the server — otherwise the harness will keep compressing conversations at one quarter of what the server could hold. Set the compression trigger high (e.g. 0.75) so the window is actually used before the lossy summary pass fires.

**d) Budget more latency per token.** Dense 27B decodes roughly like a classic 27B — noticeably slower than the 3B-active MoE. Interactive chat feels this most. Two mitigations, both already in the config: enable MTP (`vllm_speculative_config`) when a workload is decode-bound, and keep thinking-mode control per request (below) so trivial calls don't pay full reasoning price.

**e) Tool calling stays on `qwen3_coder` — and the reasoning parser stays mandatory.** Both models speak the Qwen3.5+ tool format, so no parser change was needed this time (the `hermes` parser belongs to the even older Qwen3 dense generation). `--reasoning-parser qwen3` remains non-optional: Qwen3.8 opens every assistant turn with `<think>`; without the parser, the entire reasoning block lands in `message.content`, where it pollutes downstream parsing and can burn a whole token budget before the answer starts. With it, reasoning lands cleanly in `reasoning_content`.

**f) Thinking control is per-request, and harnesses should use it.** Thinking is on by default. `chat_template_kwargs: {"enable_thinking": false}` gives fast direct answers for trivial calls (classification, formatting); `{"reasoning_effort": "low|medium|xhigh"}` tunes depth; `preserve_thinking` retains reasoning across turns for multi-step tasks — Qwen notes this can *reduce* total token consumption in agent loops by avoiding redundant re-reasoning. A harness that hardcodes one mode leaves capability on the table. Official sampling: thinking = temp 1.0 / top_p 0.95 / top_k 20; non-thinking = temp 0.7 / top_p 0.80 / presence_penalty 1.5.

**g) Vision moves from "can read" to "can operate".** Both models see; the new one acts — OSWorld 84.3 is computer-use territory. Screenshot-driven debugging, UI automation, and PDF/diagram workflows through the same endpoint become realistic harness tools. Caveat: the vision tower (BF16) shares the VRAM budget, and vLLM's recipe notes `--language-model-only` as a lever to reclaim it if vision isn't needed.

**h) MTP speculative decoding: same lever, new calculus.** Both models ship an MTP head, but it matters more now — it's the cheapest way to offset the dense decode penalty (~2–3× at ~92% acceptance, quality-neutral since verification is against the full model). We still ship it **disabled by default**: its BF16 head costs ~0.85 GiB VRAM, and at maximum-context-plus-concurrency the KV pool is worth more. Flip one Ansible variable when decode speed matters more than concurrent long contexts. It needs no CUDA graphs, so it composes fine with `enforce_eager`.

**i) Watch your served-model name.** vLLM's `--served-model-name` is the repo basename (`Qwen3.8-27B-W4A16-AWQ`), so harness configs must reference that string — the Hermes hint is documented in the README (`provider: openai-api`, `api_base: http://<host>:8001/v1`, `api_key: EMPTY`).

**j) The honest cost, amplified: prefill latency at long context.** A 200K-token prompt streams through chunked prefill at 4,096 tokens per chunk on two consumer GPUs — expect minutes of TTFT before the first token, on either model. That's physics, not misconfiguration. What changed is that the KV budget now lets those long prompts actually finish instead of being preempted — but every giant prompt now costs real wall-clock time. Harnesses should still avoid pointless prompt bloat; the difference is that *useful* bloat (whole repos, full histories) is now viable.

## 5. Deployment Notes (Blackwell sm_120 specifics)

The upgrade inherits several hard-won workarounds, all preserved in the Ansible role:

- **TRITON_ATTN**: FLASH_ATTN is broken on sm_120 (undefined symbol); FlashInfer's JIT arch check fails on Blackwell — the role actively uninstalls it so vLLM falls back to Triton attention and the native sampler. (vLLM 0.22 logs the old `VLLM_ATTENTION_BACKEND` env var as unknown but still honors the resulting selection — cosmetic.)
- **`enforce_eager`**: CUDA graphs + hybrid attention + tensor parallelism over PCIe (GeForce has no NVLink/P2P) deadlocked workers after long generations. Eager mode costs some decode speed but is stable; MTP is the sanctioned way to win it back.
- **`NCCL_P2P_DISABLE=1`**: no working PCIe P2P on GeForce pairs; transfers go over shared memory. vLLM 0.22 confirms by falling back to the PYNCCL all-reduce backend on its own.
- **vLLM ≥ 0.17** is now enforced at install time — the Qwen3_5 architecture doesn't exist in older releases.
- **Prefix caching + Mamba 'align' mode**: vLLM warns this combination is experimental for the GatedDeltaNet layers. If repeated-prefix requests ever return wrong outputs, disabling prefix caching is the workaround; so far it behaves.

## 6. Verdict

This upgrade is a deliberate speed-for-intelligence trade, not a free lunch — plus one genuinely free win. The old MoE was the faster chatbot; the new dense model is the better colleague. We give up roughly a 9× compute-efficiency advantage per token and get back benchmark gains of 10–30 points concentrated exactly where an agent harness lives: terminal work, repo-level coding, long-horizon tasks, and acting on what it sees. Vision, MTP, and the tool-calling stack carry over untouched. And the free win: the context window both models always advertised finally became real — the old deployment capped at 64K because its KV pool couldn't back more, while the new one serves the full 262K with four saturated long contexts in flight, roughly an 8× capacity gain per gigabyte of VRAM. The infrastructure changes were modest because the Ansible role was already parameterized — but the defaults now encode real lessons: auto-detected quantization, a vLLM version floor, and MTP as an explicit speed-vs-memory toggle.

---

## Glossary

AI- and serving-specific terms used in this article, in order of appearance. Where a term affects what you actually see as output, a *→ In practice* note describes the impact on an agent run or a simple chat.

**MoE (Mixture-of-Experts) / active parameters** — An MoE model contains many parallel "expert" sub-networks (Qwen3.6-35B-A3B: 256) but routes each token through only a few (8 routed + 1 shared ≈ 3B of 35B parameters). This makes each token cheap to compute while the full knowledge of all 35B stays available.
→ *In practice:* MoE = fast tokens, sometimes uneven quality on unusual prompts where routing misfires. Crucially for self-hosters: MoE saves *compute, not VRAM* — all experts must be resident, so a "35B-A3B" needs the memory of a 35B model while performing like a much smaller one per token.

**Dense model** — A transformer where every parameter participates in every token prediction. Qwen3.8-27B is dense: all 27B parameters work on every token, which makes VRAM requirements predictable and per-token quality uniform.
→ *In practice:* slower per token than an MoE of similar total size, but more consistent answers — and it's why this upgrade trades speed for reasoning depth.

**Transformer / attention** — The standard LLM architecture. "Attention" lets each token look back at all previous tokens; the data it stores per past token is the KV cache (below). "Full attention" = every layer does this over the whole context.
→ *In practice:* this is why the model can reference something you said 100 messages ago — and why that ability costs VRAM.

**Hybrid attention / Gated DeltaNet / linear attention** — The backbone both models share. Instead of full attention in every layer, most layers use *Gated DeltaNet*, a linear-attention variant that compresses the entire past into a fixed-size recurrent state (like an RNN with a memory slot) instead of storing every past token. Result: near-constant memory per token for those layers. Only a minority of layers keep classic full attention for precise long-range recall.
→ *In practice:* you get a 262K window on consumer hardware. Trade-off: exact recall of one specific line buried 200K tokens deep is slightly less reliable than with all-full-attention models — the few full-attention layers carry that load. For agents reading whole repos, recall is still strong, but quote-critical tasks benefit from re-including the relevant snippet in the prompt.

**GQA (Grouped-Query Attention)** — A memory optimization where multiple query heads share the same key/value heads. Qwen3.8-27B uses 24 query heads but only 4 KV heads (the old MoE: 16 Q / 2 KV), cutting KV-cache size severalfold versus classic multi-head attention.
→ *In practice:* invisible in output quality (measurable but negligible quality delta); visible in your bill of materials — it's a big part of why 262K context fits at all.

**KV cache** — The stored keys and values of all previous tokens, required so the model doesn't recompute the whole conversation for every new token. It lives in VRAM during generation and is usually the dominant memory cost of long contexts. Measured in MiB per token.
→ *In practice:* when the KV pool is exhausted, vLLM preempts or rejects requests — visible as stalled generations or errors under load, never as degraded text. Chat quality does not fade with a full cache; throughput does.

**Context length / context window** — The maximum number of tokens (input + output) the model can consider at once. *Native* context is what the model was trained for; anything beyond it requires position-encoding tricks (see YaRN). Both models here: 262,144 native — but note the difference between what a *model* supports and what a *deployment* serves: the old config capped at 65,536 because its KV pool couldn't back more.
→ *In practice:* everything inside the window can influence the answer; anything outside effectively never happened. For an agent, a bigger window means fewer "it forgot the earlier error message" loops; for chat, fewer mid-conversation amnesia moments. Exceeding the limit is a hard API error (400), not a silent truncation. And check your *server's* limit, not the model card's — they routinely differ.

**Token** — The model's unit of text: roughly ¾ of an English word, or 3–4 characters. 262K tokens ≈ a 600+ page book or a mid-size codebase.
→ *In practice:* the unit your latency, memory, and truncation bugs are made of. `max_tokens` limits output length — too tight and thinking models burn it all on reasoning and return an empty-looking answer.

**RoPE / YaRN / RoPE scaling** — Rotary Position Embeddings encode token positions. *YaRN* is a scaling method that stretches a model beyond its trained context length by rescaling those positions. It works, but applying a static stretch factor also slightly degrades quality at short contexts — which is why a natively long model is preferable. Neither model in this article needs it below 262K.
→ *In practice:* if you ever enable YaRN (e.g. toward 1M tokens), expect short everyday questions to get subtly worse in exchange for the extra range. Below the native limit, leave it off.

**Quantization (AWQ, W4A16, INT4, FP8)** — Storing model weights in fewer bits to save VRAM. *AWQ* (Activation-aware Weight Quantization) compresses weights to 4-bit integers while keeping accuracy. *W4A16* = 4-bit weights, 16-bit activations (compute stays high-precision). *compressed-tensors* is vLLM's native container format for such quants. *FP8* = 8-bit floating point, natively fast on Blackwell GPUs. Quality loss from a good 4-bit weight quant is small; it is the standard way to fit a 27B model into 2×16 GB.
→ *In practice:* a well-made W4A16 quant answers within ~1% of the full model on benchmarks — you won't notice in chat. A *badly calibrated* quant shows up as broken think-tags, repetition loops, or odd refusals; that's why the calibration story on the model card matters. The fp8 KV cache variant is even safer: it affects memory, not weights.

**Marlin kernel (`awq_marlin`)** — The GPU compute kernel vLLM uses to run 4-bit quantized matrix multiplications fast on NVIDIA cards. "Kernel" here means the low-level math routine, not the OS kernel. (The startup log confirms: "Using MarlinLinearKernel for CompressedTensorsWNA16".)
→ *In practice:* pure speed, no quality impact. Wrong kernel choice = slower tokens, not wrong tokens.

**vLLM / PagedAttention / continuous batching** — vLLM is the inference server. Its two core tricks: *PagedAttention* manages the KV cache in small blocks (like OS virtual memory) to avoid waste, and *continuous batching* mixes prefill and decode steps of many requests so the GPUs stay busy.
→ *In practice:* multiple agent sessions share the server without each waiting for the other to finish; individual answers are identical to single-user mode, they just arrive concurrently.

**TP / PP (tensor / pipeline parallelism)** — Ways to split one model across multiple GPUs. *Tensor parallelism (TP)* shards every layer across both cards — both always busy, but they exchange data each layer (needs fast interconnect). *Pipeline parallelism (PP)* assigns half the layers to each card — less chatter, but one card idles between stages at low request counts. We use TP=2.
→ *In practice:* no effect on answer content — outputs are bit-comparable either way. It only decides your tokens/sec, and at 1–4 concurrent requests (typical agent use) TP=2 is the faster choice.

**NVLink / P2P / NCCL / PYNCCL** — NVLink is NVIDIA's fast GPU-to-GPU interconnect (absent on GeForce cards). *P2P* = direct GPU-to-GPU memory transfer over PCIe, also broken on GeForce. *NCCL* is NVIDIA's multi-GPU communication library; `NCCL_P2P_DISABLE=1` forces it to route transfers through host RAM instead — vLLM 0.22 then selects the PYNCCL fallback backend by itself.
→ *In practice:* with P2P wrongly enabled on this hardware, multi-GPU runs hang mid-generation or crawl ~4× slower — an agent that mysteriously stalls after several minutes. With the flag set, output is correct and speed is normal.

**Prefill / decode / TTFT** — The two phases of a request. *Prefill* processes your whole prompt at once (parallel, compute-heavy). *Decode* generates the answer one token at a time (sequential, bandwidth-bound). *TTFT* = time to first token, dominated by prefill on long prompts.
→ *In practice:* a 200K-token agent prompt can sit silent for minutes before the first token appears — the answer will be fine, the wait is the cost. Short chats see sub-second TTFT. Streaming doesn't shorten prefill; it only makes the wait visible earlier.

**Chunked prefill** — Splitting a long prompt's prefill into smaller chunks (here 4,096 tokens) so ongoing decode requests of other users aren't blocked behind one huge prompt.
→ *In practice:* your chat stays responsive while an agent chews through a giant prompt in the background; without it, one big request freezes everyone else until its prefill completes.

**Prefix caching** — Reusing the KV cache of a previously-seen prompt prefix (system prompt, tool definitions) instead of recomputing it. Nearly free TTFT savings for agent workloads that resend the same header every turn. On hybrid (Mamba/GDN) models vLLM enables it in an experimental "align" mode.
→ *In practice:* the second and subsequent turns of an agent loop start answering noticeably faster. Identical output — this is a cache, not a shortcut in reasoning. (If outputs ever go wrong specifically on repeated prefixes, this experimental mode is the first suspect.)

**Speculative decoding / MTP / draft head / acceptance rate** — A speed trick: a small "draft" mechanism proposes several tokens ahead, and the full model verifies them in one parallel pass — accepted tokens cost a fraction of normal decode. *MTP* (Multi-Token Prediction) means the draft capability is trained into the model itself as an extra head, so draft quality is high. *Acceptance rate* = fraction of drafted tokens the full model agrees with; ~92% at K=2 means most speculation succeeds, giving 2–3× decode speedup with zero quality change (verification is against the full model).
→ *In practice:* enabling MTP changes speed only, never content — rejected drafts are simply regenerated by the full model. For chat, answers stream 2–3× faster; for agents, long code edits complete proportionally sooner. The cost is the VRAM the draft head occupies, which is why it's off in our max-context config.

**CUDA graphs / enforce-eager** — CUDA graphs record a sequence of GPU operations once and replay them with near-zero CPU overhead — faster decode. *Enforce-eager* disables this, running every op individually: slower but more robust. Required here because CUDA graphs + hybrid attention + PCIe tensor-parallelism deadlocked on Blackwell.
→ *In practice:* eager mode costs maybe 10–20% decode speed; the alternative on this stack was generations dying mid-answer after long runs. Slower-and-finished beats faster-and-hung.

**Attention backend (TRITON_ATTN, FLASH_ATTN, FlashInfer)** — The software implementation of the attention math. FlashAttention is the famous fast one but is broken for LLM attention on RTX 50-series (sm_120); FlashInfer needs a JIT toolchain that also fails there. *Triton* (OpenAI's GPU programming language) compiles working kernels on the fly — our fallback. (The vision tower uses its own FLASH_ATTN path, which is fine — the sm_120 breakage concerns the LLM attention.)
→ *In practice:* the backend changes speed and whether the server starts at all, never what the model says. A broken backend here means a dead service, not a degraded one.

**sm_120 / Blackwell** — NVIDIA's RTX 50-series GPU generation (2025) and its compute-capability number. New silicon often breaks older GPU kernels, which is why backend choice matters.
→ *In practice:* explains most "it worked on the old card" mysteries: failures manifest as startup crashes or hangs, not subtly wrong answers.

**Tool calling / function calling / tool-call parser** — The model emitting structured JSON requests ("call get_weather with city=Berlin") instead of plain text, so a harness can execute real actions. Each model family formats these differently; the *parser* converts raw output into structured `tool_calls`. Wrong parser = calls silently arrive as text and never execute. Qwen3.5+ (including 3.6 and 3.8) needs `qwen3_coder`.
→ *In practice:* this is the difference between an agent that *does* things and one that *narrates* things. With the wrong parser, the model's reply looks like a tool call in the chat text but nothing executes — the classic "agent talks about editing the file but the file never changes" bug. Simple chat without tools is unaffected.

**Reasoning parser / thinking mode / `<think>` / `reasoning_content` / `preserve_thinking`** — Qwen3.8 "thinks" before answering, writing its chain-of-thought inside `<think>…</think>` tags. The reasoning parser splits that into a separate API field (`reasoning_content`), keeping the actual answer (`content`) clean. `preserve_thinking` keeps prior turns' reasoning in the conversation, which Qwen notes can *reduce* total token use in agent loops by avoiding redundant re-reasoning.
→ *In practice:* without the parser, a `max_tokens=2048` request can return 2048 tokens of reasoning and zero answer — and downstream JSON parsers choke on the `<think>` text. With it, you get a clean answer plus optional visibility into the reasoning. Disabling thinking per request makes trivial chats much faster and cheaper at some cost to hard-problem accuracy; leaving it on for agentic work is usually right.

**Vision-language model (VLM) / vision tower** — A model that accepts images/video as input, not just text. The *vision tower* is the encoder sub-network that converts pixels into tokens the language model can reason over. Both models in this article are VLMs; the 3.8 generation adds strong *agentic* vision (acting on screenshots, not just describing them).
→ *In practice:* "what's wrong in this screenshot", "click the button in this UI", "read this scanned PDF" — through the same chat endpoint. High-resolution images consume many tokens each, so image-heavy chats eat the context window faster than text alone.

**Harness** — The agent framework that drives the model: sends prompts, parses tool calls, executes actions, feeds results back (Hermes Agent, Claude Code, OpenCode, Aider). The model cards' agentic benchmarks were measured with specific harnesses (Claude Code for 3.8; an internal scaffold for 3.6) — same model, different harness, different score.
→ *In practice:* the same model can feel brilliant in one harness and mediocre in another — system prompts, tool schemas, and retry logic shape outcomes as much as weights do. When comparing your local results to published benchmarks, match the harness and settings before blaming the quant.

**Benchmarks named in the tables** — *Terminal Bench*: completing real tasks in a Linux terminal (2.0 vs 2.1 are different editions — scores not directly comparable). *SWE-bench (Verified/Pro/Multilingual)*: fixing real GitHub issues. *GPQA (Diamond)*: PhD-level science questions. *HLE*: "Humanity's Last Exam", deliberately frontier-hard. *LiveCodeBench*: competitive programming, contamination-free. *IFBench*: instruction following. *OSWorld / WebArena / AndroidWorld*: operating real desktops, browsers, and phones via screenshots + actions. *Claw-Eval / MCPMark / Tool Decathlon / TAU3-Bench*: tool-use and agent suites. *NL2Repo(-Bench)*: generating code at whole-repository scale. *GSM8K*: grade-school math (sanity check). *CoWorkBench / JobBench / DeepSWE / QwenSWEBench / Agents' Last Exam / SWE-MM / RealWorldQA / OmniDocBench*: agentic, work, and vision suites — see the linked model cards for definitions.
→ *In practice:* read benchmarks as predictors, not guarantees: high Terminal Bench/SWE-bench scores predict an agent that completes multi-step coding tasks without derailing; GPQA/HLE predict answer quality on hard science Q&A; IFBench predicts whether your formatting instructions ("respond in JSON only") are obeyed — the one simple-chat users notice most. And never compare scores across different benchmark editions (Terminal Bench 2.0 ≠ 2.1) as if they were one scale.

**VRAM headroom / gpu_memory_utilization** — vLLM pre-allocates a fixed fraction of each GPU (here 95%) for weights + KV cache. Whatever remains after weights is the *KV pool* — its size in tokens is printed at startup and is the real ceiling on concurrent long contexts.
→ *In practice:* set too low, long agent contexts get preempted (visible as retries/stalls under load); set too high, the server OOMs at startup or during CUDA graph capture. It tunes capacity, never answer quality.

**CPU offload** — Moving some model weights into system RAM (the 64 GB DDR5) to free VRAM. Works, but weights then stream over PCIe on every forward pass — noticeably slower. A fallback lever, not a default.
→ *In practice:* identical answers at a fraction of the speed — an emergency lever to make an oversized model run at all, not a tuning knob for daily use.

---

### Sources

1. [Qwen/Qwen3.8-27B — Hugging Face model card](https://huggingface.co/Qwen/Qwen3.8-27B) — architecture (64 layers, 48 GDN + 16 full attn, 4 KV heads, dense 27B), benchmark tables (text + VL), thinking control (`preserve_thinking`, `reasoning_effort`), sampling recommendations.
2. [Qwen/Qwen3.6-35B-A3B — Hugging Face model card](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) — previous model: 35B total / 3B active MoE (256 experts, 8+1 active), 40 layers (30 GDN + 10 full attn, 2 KV heads), 262K native context, benchmark tables, harness/eval conditions.
3. [philbert440/Qwen3.8-27B-W4A16-AWQ — Hugging Face](https://huggingface.co/philbert440/Qwen3.8-27B-W4A16-AWQ) — quantization details (W4A16 g128, 19.5 GB, vision/MTP intact), measured throughput and MTP acceptance on 2×V100-32GB, validation results.
4. [Qwen/Qwen3.8-27B — vLLM Recipes](https://recipes.vllm.ai/Qwen/Qwen3.8-27B) — verified serving configs on consumer Blackwell (2× RTX 5090, sm_120), KV pool measurements per precision, MTP acceptance figures, `--reasoning-parser qwen3` and `qwen3_coder` parser guidance, vLLM ≥ 0.17 requirement, 1M-context YaRN override.
5. Local git history + Ansible configuration: commit `66ed291` "feat: switch to Qwen3.6-35B-A3B-AWQ-4bit", tags `vllm_Qwen3-32B-AWQ` / `vllm_Qwen3.6-35B-A3B-AWQ-4bit`, `ansible/group_vars/all.yml`, `ansible/roles/vllm/` — deployed parameters, Blackwell workarounds, KV sizing math, startup log (vLLM 0.22.0: MarlinLinearKernel, TRITON_ATTN, PYNCCL fallback).
