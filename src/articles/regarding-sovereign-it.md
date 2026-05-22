---
layout: article.njk
title: "Sovereign AI Is Loud — But The Real Issue Is Sovereign IT"
description: "Why the debate about sovereign AI is really a broader discussion about sovereign IT — control over infrastructure, platforms, portability, and the long-term ability to make and reverse technical decisions."
date: 2026-05-22
tags:
  - articles
  - AI
  - Sovereignty
  - Cloud
  - Architecture
---

# Sovereign AI Is Loud — But The Real Issue Is Sovereign IT

Most articles here are focused on very concrete, technical problems: setups, architectures, and reproducible solutions. This one takes a step back. Still, at its core, it remains technical — because questions of “sovereignty” ultimately materialize in infrastructure, operations, and the ability to make and reverse decisions.

---

## The Current Narrative: Sovereign AI

The debate around **sovereign AI** has gained remarkable momentum. Across industry reports, policy discussions, and conference stages, there is a growing emphasis on regaining control over data, models, and infrastructure. Especially in Europe, the dependency on non-local providers has become a recurring concern, driven by both geopolitical tension and regulatory realities.

Conceptually, the idea is straightforward: build, run, and control AI systems within your own sphere of influence. In practice, however, this turns out to be significantly more demanding.

Operating a self-hosted LLM setup today requires assembling a stack from relatively young and still evolving components:

- inference engines such as **vLLM** or **Ollama**
- containerized deployments and orchestration, often via **Kubernetes**
- surrounding services like vector databases, authentication, observability, and networking
- and, perhaps most critically, access to and operation of suitable **GPU infrastructure**

There is no widely accepted, production-ready “standard stack” comparable to what exists for more traditional enterprise workloads. Instead, organizations are faced with a growing but fragmented ecosystem. While this provides flexibility, it also means that building such a platform still requires a considerable amount of in-house expertise and operational maturity.

---

## Infrastructure Is Scaling — But Not Necessarily Becoming Sovereign

At the same time, the physical backbone of digital infrastructure is expanding rapidly. Driven largely by AI workloads, Europe is experiencing a strong increase in data center construction and capacity.

### Key Data Points

| Topic | Data |
|------|------|
| Demand driver | AI is now the leading driver of data center demand in Europe [1](https://www.rlbinsights.com/reports/data-centre-trends-report-2025/ai-hits-europe) |
| Capacity growth | Avg. deployments: 16 MW → 33 MW → 47 MW (2023–2025) [1](https://www.rlbinsights.com/reports/data-centre-trends-report-2025/ai-hits-europe) |
| Investment scale | > €100B expected in European data centers by 2030 [2](https://www.eudca.org/state-of-european-data-centres-2025) |
| Pipeline size | ~14 GW planned capacity in EMEA by mid-2025 [3](https://www.allianz.com/content/dam/onemarketing/azcom/Allianz_com/economic-research/publications/specials/en/2025/october/2025-10-07-construction-AZ.pdf) |

This expansion is often interpreted as a positive signal for digital sovereignty: more infrastructure, closer to users, under European jurisdiction.

Yet the picture is more nuanced. Much of this newly built capacity is designed to support hyperscale cloud and AI platforms. Even when physically located in Europe, these systems often operate within technological, contractual, and operational frameworks defined elsewhere. In that sense, infrastructure alone does not automatically translate into control.

---

## The Overlooked Context: Sovereignty Decisions Were Made Earlier

Seen in this light, the current intensity of the AI sovereignty debate is somewhat surprising. Over the past decade, many organizations have already made fundamental decisions that reduced their control over IT systems — often quite deliberately.

The shift toward cloud-based and platform-centric architectures brought undeniable advantages: faster deployment, reduced operational overhead, and access to highly sophisticated tooling. At the same time, it gradually relocated critical capabilities:

- infrastructure to cloud providers
- development workflows to hosted platforms
- collaboration and communication to SaaS ecosystems
- customer-facing systems to externally operated services

None of this was irrational. In many cases, it was the most pragmatic choice available. However, it also meant that certain aspects of control — over data flows, system behavior, or long-term portability — became harder to maintain.

---

## Different Industries, Different Trade-offs

In my own experience, the way organizations approach these questions varies significantly by industry.

In **medical technology**, there remains a noticeable degree of caution when it comes to outsourcing critical IT systems. This is not simply a cultural preference but largely shaped by regulation. Requirements around data protection, auditability, and traceability leave relatively little room for ambiguity. As a result, questions about where data resides, who can access it, and how systems can be audited or replaced tend to be addressed early and in detail.

This does not necessarily mean that cloud usage is avoided altogether. Rather, it is approached more deliberately, and often with additional safeguards or hybrid models. In that sense, sovereignty is less an abstract concept and more an operational constraint that needs to be managed.

By contrast, in parts of the **automotive industry**, the shift toward external platforms was often more assertive. Internal infrastructure teams were frequently seen as cost-intensive and less flexible, while cloud providers offered scalability, speed, and a rich ecosystem of services. Over time, this led to a situation where a significant portion of the IT landscape — from development pipelines to collaboration tools — relies on a relatively small number of external vendors.

This approach brought clear benefits in terms of velocity and standardization. At the same time, it introduced new forms of dependency, some of which only become visible when trying to change direction. Migration paths, data portability, and operational independence tend to become more complex as systems are more deeply integrated into proprietary platforms.

---

## Why AI Changes the Tone of the Debate

Against this backdrop, it becomes clearer why AI has triggered a more pronounced reaction.

AI systems tend to sit very close to core value creation. They process sensitive data, encode domain knowledge, and increasingly influence decision-making processes. As a result, questions of control feel more immediate. Where earlier layers of abstraction — infrastructure, collaboration tools, or workflow systems — could be externalized with relatively limited visibility, AI makes dependencies more tangible.

At the same time, many of the underlying challenges are not new. Vendor lock-in, limited transparency, reliance on external roadmaps, or the gradual loss of internal expertise are all dynamics that have been present for years. AI does not introduce them so much as amplify their impact.

---

## A More Nuanced View on Sovereignty

It is also worth noting that sovereignty is rarely absolute. In practice, it tends to manifest as a spectrum rather than a binary choice.

### Levels of Sovereignty

| Level | Example |
|------|--------|
| Low | Full reliance on SaaS / hyperscalers |
| Medium | EU hosting with contractual safeguards |
| High | Open-source, portable architectures |
| Maximum | Fully self-hosted or air‑gapped systems |

For many organizations, a balanced approach is likely the most practical: retaining control where it matters most while leveraging external services where appropriate. What becomes increasingly important, however, is the ability to make these choices consciously — and to revisit them if needed.

---

## Early Signs of a Shift

There are indications that the broader conversation is evolving. In the public sector, for example, initiatives are emerging that explicitly frame digital sovereignty as a strategic objective.

Programs that move away from proprietary ecosystems toward open-source-based infrastructures — such as the adoption of LibreOffice, Linux, and open collaboration platforms — reflect a growing awareness of long-term dependencies and their implications. [4](https://www.schleswig-holstein.de/DE/landesregierung/ministerien-behoerden/I/Presse/PI/2024/CdS/241125_cds_open-source-strategie)

These efforts are not without friction. Migration, training, and organizational change can be challenging. Yet they also demonstrate that alternative approaches are possible, even at scale.

---

## Conclusion

The renewed focus on sovereign AI is both understandable and valuable. At the same time, it risks narrowing the perspective if it is treated in isolation.

Questions of control, dependency, and adaptability do not begin with AI — they extend across the entire IT landscape. In that sense, sovereign AI is less a starting point and more a visible manifestation of a broader theme.

A more comprehensive view would therefore consider not only AI systems, but the surrounding architecture, data flows, and operational capabilities. Ultimately, sovereignty is less about complete independence and more about maintaining the flexibility to respond, adapt, and make informed choices.

Or, put differently:  
it is not necessarily about building everything yourself —  
but about retaining the ability not to be entirely dependent on others.