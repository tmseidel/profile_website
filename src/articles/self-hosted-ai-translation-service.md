---
layout: article.njk
title: "Evaluating Self-Hosted AI Services: A Translation Service Case Study"
description: "A practical evaluation of replacing DeepL with a self-hosted translation service using open-source LLMs — comparing quality, performance, and cost."
date: 2026-02-02
tags:
  - articles
  - AI
  - LLM
  - Self-Hosting
  - DevOps
  - Spring Boot
  - Python
---

With freely available large language models now widely accessible, it has become straightforward to self-host software that was previously only available through commercial providers. The key question always comes down to the resulting costs and the effort involved.

In this case study, I examined whether the translation service DeepL can be replaced by a self-hosted solution. The goal was to provide a DeepL-compatible REST API that:

- achieves comparable translation quality,
- offers similar performance, and
- implements the same REST API specification[^1],

in order to then compare the one-time and ongoing costs. Using the DeepL API requires a paid subscription; while the pay-as-you-go model is transparent, it can become very expensive with heavy usage. Additionally, data leaves the corporate network, and the API's behaviour under heavy load is not fully transparent.

## Choosing a Suitable Local Model

The first question is which freely available models are suitable for translation tasks. Hugging Face offers a large selection of models that can be easily integrated into custom software[^2]. For this evaluation, Meta's **nllb-200-distilled** model was chosen, as it is widely used, easy to deploy, and available in three sizes (600M, 1.3B, and 3.3B parameters).

## Implementing the DeepL-Compatible REST API

A pragmatic approach was taken for the implementation: a Spring Boot application serves as the API frontend and delegates the actual translation request to a Python Flask component that controls the LLM.

For easy deployment, the system can be run either:

- in Docker containers, or
- natively on a Debian/Ubuntu server.

The goal was a straightforward deployment on various cloud hardware platforms to test quality and performance there. The complete implementation is available on GitHub[^3]. Ansible was used for automated native deployment.

## Test — Translation Quality

The following German reference sentence was used to evaluate translation quality:

> *"Sobald der Glasfaser-Ausbau abgeschlossen ist, erhalten Sie eine Mitteilung zum Schaltungstermin und eine Schnell-Start-Anleitung für die Einrichtung des Glasfaser-Anschlusses."*

DeepL produces the following translation:

> "Once the fiber optic expansion is complete, you will receive a notification of the activation date and a quick start guide for setting up your fiber optic connection."

This translation serves as the reference.

### Test with nllb-200-distilled-600M

The smallest model was first run on a development machine via Docker. Performance was not a concern at this stage. The generated translation was:

> "Once the glass-faser-Ausbau is closed, you receive a Mitteilung zum Schaltungstermin und eine Schnell-Start-Anleitung für die Einrichtung der Glasfaser-Anschlusses."

![Response of the small model](nllb-200-distilled-600M.png)

### Test with nllb-200-distilled-1.3B

The medium model produced the following output:

> "The Commission shall inform the Member States of the date of the entry into force of this Regulation."

### Test with nllb-200-distilled-3.3B

The largest model generated the following translation:

> "Once the glass fibre installation is completed, you will receive a notice on the date of installation and a quick start guide for the installation of the glass fibre connections."

![Response of the large model](nllb-200-distilled-3.3B.png)

### Translation Quality Conclusion

A comprehensive assessment is difficult after just a few tests. Nevertheless, it became clear that only the largest model is viable for production use. It was also notable that the models performed significantly more reliably when the source language was English. If translation is exclusively from English, the medium model might therefore be sufficient.

## Test — Performance

Once the suitable model was identified, the next step was to determine under which hardware conditions productive operation is feasible. As a benchmark, it was assumed that translating the reference sentence should take no longer than two seconds. Additionally, the difference between a traditional CPU-based server and a GPU-based system was to be determined.

### Test: Traditional Server

A Hetzner CX53 with 16 vCPUs and 32 GB RAM was used as the CPU server (cost: €17 per month).

**Response time: 12.93 seconds**

### Test: GPU Server

An Amazon g4dn.large with 16 GB GPU RAM (Nvidia) was used as the GPU server. The cost is €0.67 per hour, roughly €500 per month.

**Response time: 1.31 seconds** — GPU memory usage: approx. 13 GB

### Performance Conclusion

The difference between the two systems was significantly larger than expected. Even without deep knowledge of the internal workings of LLMs, it is clear that productive operation is practically only feasible with GPU-based hardware. Costs on AWS are currently high, but cheaper alternatives exist — for example at Hetzner[^4]. The achieved response time is fundamentally suitable for production use. Parallel requests had no significant impact on latency in the tests.

![nvidia-smi output showing GPU memory usage](nvidia-smi.png)

## Overall Conclusion

This evaluation clearly demonstrates that it is possible to self-host AI-based services like machine translation using freely available models and modern hardware — with reasonable effort and competitive quality. While the ongoing costs for GPU-based systems are still relatively high, falling prices and increasing efficiency can be expected as adoption grows and technology advances. Moreover, more affordable hosting alternatives beyond the major cloud providers already exist today.

Especially in heavily regulated industries — such as finance, healthcare, or the public sector — a self-hosted AI service can offer significant advantages:

- **Data sovereignty** is fully preserved, as no sensitive information leaves external systems.
- **Compliance requirements** are easier to meet, since infrastructure and data flows are fully controllable.
- **Performance and scalability** can be precisely tailored to your own needs.
- **Competitive advantages** emerge when you can offer services that are not only cheaper but also more secure and flexible than commercial alternatives.

## References

[^1]: [DeepL API Documentation](https://developers.deepl.com/docs/getting-started/intro)

[^2]: [Hugging Face Translation Models](https://huggingface.co/models?pipeline_tag=translation)

[^3]: [simple_ai_translation_service on GitHub](https://github.com/tmseidel/simple_ai_translation_service)

[^4]: [Hetzner GPU Dedicated Servers](https://www.hetzner.com/dedicated-rootserver/matrix-gpu/)

