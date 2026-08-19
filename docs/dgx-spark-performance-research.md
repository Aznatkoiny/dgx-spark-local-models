# DGX Spark performance research: Qwen3.8-27B with `llama.cpp` and jcode

Research date: 2026-08-19
Scope: one NVIDIA DGX Spark/GB10, Qwen3.8-27B GGUF, `llama-server`, one interactive jcode session

## Conclusion

The observed **approximately 15 generated tokens/second was credible for this dense 27B model and was not, by itself, evidence of a misconfigured DGX Spark**. A completed local tuning sweep subsequently raised the matched two-prompt coding result to **32.03 tokens/s** with Q5_K_M, MTP depth 3, and `GGML_CUDA_CUB_3DOT2=OFF`. The closest upstream result is `llama.cpp`'s merged Qwen 27B MTP work: on a DGX Spark, a Q8 27B model generated roughly 7.0–7.7 tokens/s without MTP, averaged about 15.7 tokens/s with a two-token MTP draft, and about 16.8 tokens/s with a three-token draft. Those are derived aggregates from the PR's prompt set, not promises for Qwen3.8, another quant, or a coding-agent workload. [`llama.cpp` MTP PR #22673](https://github.com/ggml-org/llama.cpp/pull/22673)

The local log independently supports that diagnosis. One long jcode turn generated 34,637 tokens at 15.89 tokens/s, with 74.4% draft acceptance and an average accepted draft length of 2.49. Later short, highly predictable generations reached roughly 21–22 tokens/s at 100% acceptance. In other words, MTP is functioning; its benefit varies materially with the text being generated.

The completed local sweep produced these decisions:

1. **Use MTP depth 3 for coding.** It improved the matched Q6 coding sample from 22.48 to 27.94 tokens/s (+24.3%). It was slightly worse on one low-acceptance 8K continuation, so the gain remains workload-dependent.
2. **Use Q5_K_M as the daily driver.** In the final back-to-back non-CUB sweep it reached 32.03 tokens/s, versus 26.57 for Q6 (+20.5%). Q4_K_XL reached 34.76 (+8.5% over Q5), which was not enough additional speed to justify making the larger quality tradeoff the default.
3. **Keep physical ubatch at 512.** Across two independent 8K prompts, 512 and 1024 were effectively tied at 614.33 and 612.46 prompt tokens/s; 2048 fell to 584.25. A favorable single-prompt 2048 result did not reproduce.
4. **Keep `GGML_CUDA_CUB_3DOT2` off on this installation.** The isolated matched coding result was 24.01 tokens/s with CUB 3.2 versus 26.57 without it. The NVIDIA option remains available for future retesting, but generic tuning guidance lost to local evidence here.
5. **Keep backend sampling, CUDA graph optimization, and Direct I/O off/default.** Q5 measured 31.96, 31.84, and 31.86 tokens/s respectively versus the 32.03 baseline. Direct I/O's 6.85-second load-to-listen time was within the normal 5.2–7.3-second `auto` range.
6. **Control live context and output/reasoning length.** The repo-local jcode default is low effort with a 2,048-token reasoning cap; `none` remains the fastest routine-work profile.

A matched 768-token local A/B after the source review found no backend-sampling gain: 22.32 tokens/s with backend sampling versus 22.40 without it. The final Q5 coding A/B agreed: 31.96 with backend sampling versus 32.03 without it. It remains an experimental NVIDIA recipe flag, but it is not enabled on this installation.

## Completed local benchmark matrix

All final coding rows used the same two NVIDIA SPEED-Bench qualitative coding prompts, temperature 0, seed 42, reasoning disabled, one server slot, Flash Attention, Q8 K/V, MTP depth 3, ubatch 512, and the same Q4_0 MTP head. Reported decode speed is the mean of llama.cpp's server timings, not client-side token counting.

| Target / isolated change | Decode tok/s | Average latency | Draft acceptance | Decision |
|---|---:|---:|---:|---|
| Q6_K_L, CUB 3.2 option off | 26.57 | 10.63 s | 94.77% | Quality profile |
| Q6_K_L, CUB 3.2 | 24.01 | 11.90 s | 94.77% | Keep off |
| Q5_K_M, CUB 3.2 option off | 32.03 | 8.94 s | 96.63% | Daily-driver default |
| Q4_K_XL, CUB 3.2 option off | 34.76 | 8.28 s | 94.77% | Optional fast profile |
| Q5 plus backend sampling | 31.96 | 9.06 s | 96.63% | Keep off |
| Q5 plus `GGML_CUDA_GRAPH_OPT=1` | 31.84 | 9.00 s | 96.63% | Keep off |
| Q5 plus `--load-mode dio` | 31.86 | 8.99 s | 96.63% | Keep `auto` |

The MTP-depth A/B was an earlier matched Q6/CUB trial: N=2 reached 22.48 tokens/s and N=3 reached 27.94, with identical output lengths. For physical batch size, an expanded two-prompt 8K prefill sample measured 614.33 prompt tokens/s at ubatch 512, 612.46 at 1024, and 584.25 at 2048. One unrelated harness request delayed the client during the 1024 trial, so the comparison uses server prompt timings rather than client wall time.

## What is already correct

The current setup has most of the important fundamentals right:

- A Release CUDA build targeting GB10 (`121a-real`) with native CPU tuning. NVIDIA's dedicated Spark recipe also calls for CUDA, native tuning, and the native SM 121a target. [NVIDIA DGX Spark `llama.cpp` recipe](https://build.nvidia.com/spark/llama-cpp/instructions)
- Full GPU offload for both target and MTP models. Do not move layers back to the CPU; upstream Spark benchmarks use full GPU offload. [`llama.cpp` DGX Spark benchmark](https://github.com/ggml-org/llama.cpp/blob/master/benches/dgx-spark/dgx-spark.md)
- Flash Attention enabled. Keep it enabled; both NVIDIA's performance recipe and upstream Spark benchmarks use it. [NVIDIA Spark performance benchmarking guide](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md#llamacpp)
- One server slot (`--parallel 1`) for one interactive jcode session. This favors latency and prefix-cache locality rather than aggregate multi-user throughput.
- MTP speculative decoding with the official Q4_0 MTP tensor. The Qwen3.8-27B GGUF repository currently publishes that MTP quant. [Unsloth Qwen3.8-27B MTP files](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/tree/main/MTP)
- Symmetric Q8 K/V cache and preserved reasoning. Q8 K/V is a defensible long-context memory/quality compromise; there is no primary Spark benchmark establishing a universally faster K/V type for this exact model.

## Prioritized experiments

| Priority | Experiment | Primarily improves | Evidence and expected tradeoff |
|---:|---|---|---|
| 1 | Change `--spec-draft-n-max 2` to `3` | Token generation | **Adopted.** The local coding sample improved 24.3%, while one low-acceptance 8K continuation was slightly slower. NVIDIA's current Spark example uses 3, as does the `llama.cpp` default. [NVIDIA recipe](https://build.nvidia.com/spark/llama-cpp/instructions), [`llama.cpp` speculative decoding guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md), [MTP PR](https://github.com/ggml-org/llama.cpp/pull/22673) |
| 4 | Add `--backend-sampling` | Per-token latency | NVIDIA includes it in its Spark server command, but a matched local A/B measured 22.32 tokens/s with it and 22.40 without it. `llama-server` also marks the feature experimental. Retest only after other runtime or build changes. [`llama-server` README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md), [NVIDIA guide](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md#llamacpp) |
| 2 | Rebuild with `-DGGML_CUDA_CUB_3DOT2=ON` | CUDA path, especially batched work | **Tested, not adopted.** The local matched coding result was 10.7% faster without it. NVIDIA uses the option in a Spark performance build, but it is not universally beneficial. [NVIDIA guide](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md#llamacpp), [`ggml-cuda` CMake source](https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cuda/CMakeLists.txt) |
| 2 | Sweep `--ubatch-size 512`, `1024`, `2048`, keeping `--batch-size >= --ubatch-size` | Prompt processing and TTFT | **Tested; 512 retained.** The expanded local 8K sample measured 614.33, 612.46, and 584.25 prompt tokens/s respectively. [`llama-server` README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md), [Spark benchmark](https://github.com/ggml-org/llama.cpp/blob/master/benches/dgx-spark/dgx-spark.md) |
| 3 | Test Q5_K_M/Q5_K_XL, then Q4_K_M/Q4_K_XL | Token generation and model load | **Q5_K_M adopted.** It improved the final coding sample 20.5% over Q6; Q4_K_XL added only another 8.5% and remains optional because quantization can reduce model accuracy. [Unsloth GGUF file tree](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/tree/main), [`llama.cpp` quantization documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/quantize/README.md), [NVIDIA hardware specification](https://docs.nvidia.com/dgx/dgx-spark/hardware.html) |
| 4 | Test `--load-mode dio` after warmup | Load/residency consistency | **Tested, not adopted.** Load time was within the `auto` range and coding decode was 0.5% lower. [NVIDIA guide](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md#llamacpp), [`llama-server` load modes](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md) |
| 5 | A/B with `GGML_CUDA_GRAPH_OPT=1` | Token generation | **Tested, not adopted.** It was 0.6% slower on the local Q5 coding sample. [`llama.cpp` CUDA performance discussion](https://github.com/ggml-org/llama.cpp/discussions/17621) |

Do not combine every change for the first test. One-variable trials reveal whether a flag helps the actual jcode workload and make regressions reversible.

## Decode speed is only one part of jcode latency

There are three distinct clocks:

1. **Prompt processing (PP)** evaluates new prompt tokens. It determines much of time-to-first-token after a large file read, tool result, or history change. Flash Attention, batch/ubatch, prefix reuse, and live context matter here.
2. **Token generation (TG)** produces output one token at a time. Target quant size and accepted MTP predictions dominate the opportunities here. This is the approximately 15 tokens/s number.
3. **Agent-loop time** includes PP, TG, tool execution, filesystem or shell work, and every subsequent model turn. A faster TG number does not shorten a slow tool or an unnecessarily huge completion.

jcode's local-model path is an OpenAI-compatible streaming Chat Completions client with function/tool calling; the model kernels and the measured TG rate live in `llama-server`. [jcode self-hosted endpoint documentation](https://github.com/1jehuang/jcode#self-hosted-openai-compatible-endpoints-including-vllm)

This matters in the observed workload: one cancelled jcode turn had already emitted more than **13,000 tokens**, so its generation length—not jcode's streaming or HTTP transport—dominated elapsed time. The wrapper maps friendly environment variables to jcode's documented request-body override:

```bash
# Fastest routine-work profile: no hidden reasoning
QWEN_REASONING_EFFORT=none ./jcode-qwen

# Balanced profile: low effort with a hard 2K-token reasoning guardrail
QWEN_REASONING_EFFORT=low QWEN_REASONING_BUDGET_TOKENS=2048 ./jcode-qwen
```

The checked-in `.env.example` makes the balanced profile persistent without publishing the real `.env`. The wrapper-generated named provider does not advertise selectable effort levels to jcode, so these variables are more reliable than assuming `/effort` is active. `llama-server` maps top-level `reasoning_effort: "none"` to non-thinking mode and accepts per-request reasoning budgets. Qwen cautions that lowering reasoning effort can reduce one-turn latency yet increase total work through errors and retries, so validate task success rather than optimizing token count alone. [jcode extra-body documentation](https://github.com/1jehuang/jcode#extra-request-body-fields-extra_body), [`llama.cpp` reasoning-budget discussion](https://github.com/ggml-org/llama.cpp/discussions/21445), [Qwen3.8-27B model card](https://huggingface.co/Qwen/Qwen3.8-27B)

Keep `--reasoning-preserve`. Qwen says retained reasoning improves KV-cache utilization and reduces redundant reasoning across turns. Removing it can make the visible response shorter while causing the model to redo hidden work later. [Qwen3.8-27B model card](https://huggingface.co/Qwen/Qwen3.8-27B)

## Context, prompt caching, and concurrency

`llama-server` reuses an exact common prefix by default. The local log shows this working: one request retained almost the entire previous prefix and only evaluated 88 new prompt tokens. Keep system prompts, tool schemas, and stable instructions byte-identical so that jcode can preserve that prefix. [`llama-server` README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md), [`llama.cpp` prompt-cache discussion](https://github.com/ggml-org/llama.cpp/discussions/8860)

The configured 65,536-token capacity is not the same thing as a continuously full context. Reducing the cap alone is unlikely to improve shallow-context decode; it mostly reduces reserved KV memory and forces earlier truncation or compaction. What hurts is the **active** history. Upstream Spark results for a different Qwen model show generation falling as context depth rises, so periodically compact or start a fresh jcode session after long tool loops. A 32K or 48K profile is reasonable if it enforces healthy compaction, but it trades away recall. Qwen's full native limit is much larger, while NVIDIA recommends at least 32K for coding/agentic use; those are capability recommendations, not performance targets. [`llama.cpp` Spark context-depth benchmark](https://github.com/ggml-org/llama.cpp/blob/master/benches/dgx-spark/dgx-spark.md), [NVIDIA recipe](https://build.nvidia.com/spark/llama-cpp/instructions), [Qwen model card](https://huggingface.co/Qwen/Qwen3.8-27B)

Keep `--parallel 1` when one human is using jcode. Additional slots are for aggregate concurrency: they split context capacity, introduce competing sequences, and reduce the chance that the one useful prefix remains resident. If multiple harnesses need simultaneous service, benchmark more slots for aggregate throughput, but do not expect lower single-session latency. MTP's upstream work also notes that multi-sequence operation is not yet fully optimized. [MTP PR](https://github.com/ggml-org/llama.cpp/pull/22673), [`llama.cpp` multi-slot cache discussion](https://github.com/ggml-org/llama.cpp/discussions/13488)

## Quantization and K/V cache choices

Start the quality/speed comparison at **Q5**, not immediately at the smallest available quant. Use a fixed set of real coding tasks, compare correctness and number of retries, and only then try Q4. A model that emits faster but needs another repair turn can be slower overall. Unsloth's generated quick-start selects Q4_K_M, but that is a deployment default rather than a guarantee that it is the best coding-quality point. [Unsloth Qwen3.8-27B GGUF model card](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)

Keep Q8_0/Q8_0 K/V for the first trials so only one variable changes. Later, compare it with F16/F16 if sufficient memory remains. More aggressive Q4/Q5 K/V formats can save context memory but add another quality and kernel-support variable; do not combine them with a target-model quant change. Flash Attention should remain on throughout.

If vision is unused, `--no-mmproj` avoids loading the vision projection and frees headroom. Upstream documents lower memory use, not a guaranteed tokens/s increase. [MTP PR](https://github.com/ggml-org/llama.cpp/pull/22673)

## Hardware and system checks

Use the supplied 240 W power adapter, leave adequate airflow, and keep ambient temperature within NVIDIA's stated 5–30 °C operating range. Update the DGX OS as a validated stack; NVIDIA's 7.5.0 release includes newer GB10 unified-memory handling. [DGX Spark hardware guide](https://docs.nvidia.com/dgx/dgx-spark/hardware.html), [DGX Spark release notes](https://docs.nvidia.com/dgx/dgx-spark/release-notes.html)

No official NVIDIA Spark `llama.cpp` recipe found in this research recommends manual overclocking, fixed clocks, or a MAXN toggle. Do not make those the first tuning move. Use `nvidia-smi` during a benchmark as a diagnostic: look for unexpected throttling, low utilization, or another process consuming unified memory. A machine already matching upstream MTP-class performance is unlikely to have a gross power-cap fault.

For newer CUDA features than the DGX OS host stack provides, NVIDIA recommends its current NGC development container rather than mixing arbitrary host drivers and CUDA packages. [NVIDIA Spark performance guide](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/connect-two-sparks/assets/performance_benchmarking_guide.md#llamacpp)

## A reproducible benchmark sequence

Use `llama.cpp`'s server SPEED-Bench in addition to the jcode UI. It records prompt throughput, predicted-token throughput, latency, and MTP acceptance, and supports baseline/speculative comparisons. [`llama.cpp` SPEED-Bench README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/bench/speed-bench/README.md)

Run after model warmup, with one concurrent request and identical prompts:

1. Current Q6, MTP N=2.
2. Current Q6, MTP disabled. This establishes the actual speculative speedup.
3. Current Q6, MTP N=3.
4. Winning MTP depth, backend sampling on/off.
5. Winning runtime settings, ubatch 512/1024/2048; record PP and TTFT separately from TG.
6. Rebuild with CUB 3.2 and repeat the winner.
7. Repeat with one Q5 target, then one Q4 target, using the same MTP file and K/V cache.

For every run record:

- PP tokens/s and TTFT;
- TG tokens/s;
- MTP accepted/generated ratio and mean accepted length;
- active context length;
- peak unified-memory use;
- end-to-end task time and whether the task succeeded.

Use several representative coding prompts rather than a single synthetic completion. The upstream MTP results show why: acceptance and resulting speed vary by prompt. There is also an open CUDA acceptance report for a different Qwen3.5-9B GGUF; it should not be generalized to Qwen3.8-27B, but an unexpectedly low local acceptance ratio is a reason to compare with MTP disabled and check current `llama.cpp` issues. [`llama.cpp` issue #26750](https://github.com/ggml-org/llama.cpp/issues/26750)

## Recommended first profile

The adopted daily-driver profile is Q5_K_M, full GPU offload, Flash Attention, Q8 K/V, one slot, 65K capacity, and preserved reasoning:

```text
build:  -DGGML_CUDA_CUB_3DOT2=OFF
serve:  --spec-draft-n-max 3
serve:  --batch-size 2048 --ubatch-size 512
serve:  --load-mode auto
off:    backend sampling, GGML_CUDA_GRAPH_OPT
jcode:  reasoning_effort=low, reasoning_budget_tokens=2048
```

Q6_K_L remains the quality-oriented profile and Q4_K_XL the optional maximum-speed profile. Re-run this matrix after a material `llama.cpp`, CUDA, model, or harness update; these settings are empirical choices for this installation rather than permanent truths.
