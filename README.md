# Local coding models on DGX Spark

This workspace serves local GGUF models through a CUDA-enabled `llama.cpp` API and connects them to Codex CLI, [jcode](https://github.com/1jehuang/jcode), and [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

## What works

| Model | Local size | Context here | Codex | jcode | DeepSeek Harness |
| --- | ---: | ---: | --- | --- | --- |
| Qwen3.8-27B Q6_K_L | 24.2 GB | 65,536 | Tested | Tested, including bash tool | Tested, including bash tool |
| DeepSeek-V4-Flash-0731 Q2_K_S | 98.6 GB | 8,192 | Not configured | Configured | Configured |

Qwen is installed and is the recommended daily driver. The DeepSeek download and launch path is ready, but the 98.6 GB model has intentionally not been downloaded automatically.

DeepSeek-V4-Pro-0813 is the newest official DeepSeek checkpoint. Its official weights are about 893 GB, so it cannot run in the 128 GB unified memory of one DGX Spark. Flash-0731 is the newest V4 variant with a remotely plausible one-Spark quantization, but its aggressive 2-bit GGUF is experimental and can lose meaningful quality.

## Install the harnesses

```bash
./scripts/install-harnesses.sh
```

This installs pinned ARM64 builds under `tools/`:

- jcode `0.78.1`
- DeepSeek Harness `0.1.0-rc.8`

The wrappers keep their state under ignored `run/` directories instead of changing `~/.jcode` or `~/.dsh`. jcode telemetry is disabled by default in these wrappers. DeepSeek Harness is a developer preview and may make breaking configuration changes in future releases.

## Use Qwen

Start or switch to the Qwen server:

```bash
./scripts/use-model.sh qwen
./scripts/smoke-test.sh
```

Use any harness:

```bash
./codex-qwen
./jcode-qwen
./dsh-qwen
```

The first two commands open their interactive interfaces. `dsh-qwen` starts the browser UI at `http://127.0.0.1:3080` without opening a browser automatically.

One-shot examples:

```bash
./codex-qwen exec "Explain this repository"
./jcode-qwen run "Explain this repository"
./dsh-qwen --profile headless "Explain this repository"
```

The validated tool-loop prompts were:

```bash
./jcode-qwen run --tool-profile minimal \
  "Use the bash tool to execute uname -m, then return only the command output."

./dsh-qwen --profile headless \
  "Use the bash tool to execute uname -m, then return only the command output."
```

Both returned `aarch64` after a real tool call.

## Try DeepSeek V4 Flash locally

First check that you have at least 110 GB free, then explicitly download the two pinned Q2_K_S shards:

```bash
./scripts/download-deepseek.sh
```

Stop Qwen and load DeepSeek:

```bash
./scripts/use-model.sh deepseek
./scripts/smoke-test-deepseek.sh
```

Then use either requested harness:

```bash
./jcode-deepseek
./dsh-deepseek
```

Headless examples:

```bash
./jcode-deepseek run "Inspect this repository"
./dsh-deepseek --profile headless "Inspect this repository"
```

The first launch may take several minutes. Watch it with:

```bash
tail -f logs/deepseek-v4-flash.log
```

Do not load Qwen and DeepSeek simultaneously on one Spark. `use-model.sh` stops the other known server before switching.

### Why the DeepSeek defaults are conservative

The Flash profile starts with one slot and an 8,192-token context. It does not load the additional 10.8 GB DSpark speculative head. It also uses FP16 KV cache, disables flash attention, repacking, and warmup, because current llama.cpp DeepSeek V4 issues have included silent corruption with quantized K cache and multi-pass CUDA flash attention.

Treat this as a feasibility and quality experiment. Before increasing context, confirm:

1. The system is not swapping and has safe memory headroom.
2. Plain streamed chat remains coherent.
3. A forced function call arrives as a structured tool call.
4. A tool-result follow-up completes correctly.

## Server details

Qwen:

- API: `http://127.0.0.1:30000/v1`
- Model ID: `Qwen/Qwen3.8-27B`
- Model: Q6_K_L plus vision projector and MTP draft head

DeepSeek:

- API: `http://127.0.0.1:30001/v1`
- Model ID: `deepseek-ai/DeepSeek-V4-Flash-0731`
- Model: `ggml-org` Q2_K_S, without DSpark draft

Both servers bind only to localhost. If you change a host to `0.0.0.0`, protect it with a firewall, authenticated reverse proxy, or SSH tunnel.

Useful server commands:

```bash
./scripts/start.sh
./scripts/stop.sh
./scripts/start-deepseek.sh
./scripts/stop-deepseek.sh
```

## Tuning

| Variable | Default | Purpose |
| --- | --- | --- |
| `QWEN_API_PORT` | `30000` | Qwen port |
| `QWEN_CTX_SIZE` | `65536` | Qwen server and wrapper context |
| `QWEN_MODEL_FILE` | Q6_K_L path | Alternative Qwen GGUF |
| `DEEPSEEK_API_PORT` | `30001` | DeepSeek port |
| `DEEPSEEK_CTX_SIZE` | `8192` | Experimental DeepSeek context |
| `DEEPSEEK_MODEL_FILE` | Q2_K_S shard 1 | Alternative DeepSeek GGUF |

The jcode wrappers honor port and context overrides dynamically. DeepSeek Harness uses the checked-in YAML templates under `harnesses/deepseek-harness/`; edit those templates and remove the corresponding `run/dsh-*/settings.yaml` to regenerate a runtime profile.

## Rebuild and model provenance

```bash
./scripts/build.sh
./scripts/download-model.sh
```

The llama.cpp build follows NVIDIA's [DGX Spark recipe](https://build.nvidia.com/spark/llama-cpp/instructions) and targets GB10 `sm_121a`. Downloads are pinned for reproducibility:

- Qwen GGUF revision: `990216cf312573f2ac4060279848e0f4237600c7`
- DeepSeek GGUF revision: `f559fd6005309e5f6bd650342ee8711ff189b3b8`

The source-backed feasibility and compatibility notes are in [the research report](docs/multi-harness-deepseek-research.md).
