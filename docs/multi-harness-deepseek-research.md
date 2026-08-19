# Local llama.cpp models in jcode and DeepSeek Harness

Research date: 2026-08-19.

Source snapshots inspected:

- jcode `37272c9150c5759575acf16c892bb3458439dc7a` (`0.77.1` in the workspace manifest)
- DeepSeek Harness `141eb6fef83422698aef7a981029e843e8161534` (`0.1.0-rc.8`)
- the local llama.cpp checkout `3e7344670adf63ce28527a4d42f2d71eca27c41e`

## Conclusions

1. **The existing local Qwen3.8-27B server can be used by both harnesses.** Both have an OpenAI-compatible Chat Completions path, and the existing server exposes `POST /v1/chat/completions`, model discovery, streaming SSE, and standard function/tool calls.
2. **jcode is the simpler integration.** Its documented `provider add` command directly supports unauthenticated localhost endpoints and persists the correct context window.
3. **DeepSeek Harness should use its generic `llm-pi-ai` adapter for Qwen or any other llama.cpp model.** Its native `llm-deepseek` adapter can also point at another base URL, but it intentionally sends DeepSeek-specific thinking fields and identity headers. The generic adapter is the cleaner contract for a non-DeepSeek model.
4. **The latest official DeepSeek release is DeepSeek-V4-Pro-0813, and it cannot run locally on one 128 GB DGX Spark.** Its official checkpoint is 893 GB. Even a hypothetical uniform 2-bit representation of roughly 1.6T parameters would be about 400 GB before metadata, buffers, and KV cache.
5. **The newest remotely plausible local V4 is DeepSeek-V4-Flash-0731, not Pro-0813.** The llama.cpp organization publishes a 98.6 GB `Q2_K_S` GGUF. It may fit only as a tight, experimental configuration with a small context and no 10.8 GB DSpark draft at first. This is a llama.cpp/ggml conversion, not an official DeepSeek quantization, and such an aggressive 2-bit quantization can materially reduce quality.
6. **The practical first-party DeepSeek fallback is DeepSeek-R1-0528-Qwen3-8B.** Its official BF16 checkpoint is only about 16.4 GB and has a 131,072-token configured context. It is a distilled 8B model from 2025, not the latest V4 model.

Implementation update: jcode 0.78.1 and DeepSeek Harness 0.1.0-rc.8 were subsequently installed in this workspace. Qwen completed streamed text and real `bash` tool loops in both harnesses, each returning `aarch64` from `uname -m`. The native DeepSeek Harness route was also exercised against the local API shape. The 98.6 GB Flash checkpoint itself has not been downloaded, so its quality, memory residency, and tool stability remain unverified on this machine.

## 1. Existing Qwen3.8-27B server

The current project serves the model as:

- base URL: `http://127.0.0.1:30000/v1`
- model ID: `Qwen/Qwen3.8-27B`
- deployed context: 65,536 tokens, one slot
- API: OpenAI-compatible Chat Completions and Responses
- tools: llama.cpp Jinja template parsing, standard function calls

The deployed 65,536-token limit, rather than the model card's larger native limit, is the value each harness must use for context accounting. See the local [server configuration](../scripts/serve.sh) and the official [Qwen3.8-27B model card](https://huggingface.co/Qwen/Qwen3.8-27B). Qwen publishes the model under Apache-2.0.

## 2. jcode

### Compatibility

jcode explicitly supports arbitrary local OpenAI-compatible endpoints. Its self-hosting documentation says it uses:

- `GET /v1/models` when catalog discovery is enabled;
- streaming `POST /v1/chat/completions`;
- OpenAI function/tool definitions and streamed `delta.tool_calls`;
- OpenAI image content for vision-capable models.

The transport appends `/chat/completions` to the configured base, sends `stream: true`, sends `stream_options.include_usage` for direct compatible endpoints, sends function schemas under `tools`, and sets `tool_choice: "auto"`. These shapes match llama.cpp's server. Sources: [jcode provider/self-hosting documentation](https://github.com/1jehuang/jcode/blob/37272c9150c5759575acf16c892bb3458439dc7a/README.md#self-hosted-openai-compatible-endpoints-including-vllm), [request construction](https://github.com/1jehuang/jcode/blob/37272c9150c5759575acf16c892bb3458439dc7a/crates/jcode-provider-openrouter-runtime/src/openrouter_provider_impl.rs), and [SSE transport](https://github.com/1jehuang/jcode/blob/37272c9150c5759575acf16c892bb3458439dc7a/crates/jcode-provider-openrouter-runtime/src/openrouter_sse_stream.rs).

jcode publishes a Linux AArch64 artifact, so the DGX Spark is a supported installation target. See its [installer architecture dispatch](https://github.com/1jehuang/jcode/blob/37272c9150c5759575acf16c892bb3458439dc7a/scripts/install.sh) and [support matrix](https://github.com/1jehuang/jcode/blob/37272c9150c5759575acf16c892bb3458439dc7a/README.md#platform-support).

### Exact Qwen setup

Install jcode using its documented Linux installer:

```bash
curl -fsSL https://jcode.sh/install | bash
```

Register the current server:

```bash
jcode provider add spark-qwen \
  --base-url http://127.0.0.1:30000/v1 \
  --model Qwen/Qwen3.8-27B \
  --no-api-key \
  --context-window 65536 \
  --model-catalog \
  --set-default
```

Validate basic generation and the agent/tool loop:

```bash
jcode --provider-profile spark-qwen auth-test \
  --prompt 'Reply exactly JCODE_QWEN_OK'

jcode --provider-profile spark-qwen run \
  'Run uname -m with the shell tool, then report only its output.'
```

The generated profile is stored in `~/.jcode/config.toml`. Its essential equivalent is:

```toml
[provider]
default_provider = "spark-qwen"
default_model = "Qwen/Qwen3.8-27B"

[providers.spark-qwen]
type = "openai-compatible"
base_url = "http://127.0.0.1:30000/v1"
default_model = "Qwen/Qwen3.8-27B"

[[providers.spark-qwen.models]]
id = "Qwen/Qwen3.8-27B"
context_window = 65536
```

Do not set a 262K or 1M context in the harness while llama.cpp is launched with `--ctx-size 65536`; incorrect accounting postpones compaction until the backend rejects the request.

### Reasoning and tool-call caveats

- jcode's local provider is Chat Completions, not the Responses API used by its OpenAI/Codex OAuth path.
- Tool use depends on both the model's behavior and llama.cpp's template/parser. The existing Qwen server already has `--jinja`, and the Codex integration completed a shell-tool round trip, which is encouraging but does not replace a jcode tool smoke test.
- If the endpoint takes too long before its first thinking token, `JCODE_STREAM_IDLE_TIMEOUT_SECS` raises the default 180-second idle timeout.
- `extra_body` or `JCODE_OPENAI_EXTRA_BODY` can add backend-specific top-level fields. This should not be needed for the existing Qwen llama.cpp route; use it only after inspecting an actual rejected request.

jcode itself is [MIT-licensed](https://github.com/1jehuang/jcode/blob/37272c9150c5759575acf16c892bb3458439dc7a/LICENSE).

## 3. DeepSeek Harness (`dsh`)

### Status and architecture

DeepSeek Harness is an official DeepSeek project, MIT-licensed, and currently marked **developer preview** with compatibility-breaking changes expected. The inspected package version is `0.1.0-rc.8`. It runs with Node.js and ships a Linux ARM64 Landlock helper, matching the DGX Spark platform. Sources: [project README](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/README.md), [package manifest](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/package.json), [ARM64 helper support](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/native/landlock-run/README.md), and [license](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/LICENSE).

The default bundle mounts two relevant adapters:

- `llm-deepseek`: native DeepSeek Chat Completions transport, provider route `deepseek-official`;
- `llm-pi-ai`: generic multi-provider transport, mounted dormant until `settings.yaml` declares a route.

The generic adapter supports a hand-declared `openai-completions` provider with a base URL, model catalog, context window, max output, tool schemas, and compatibility switches. This is the intended path for a self-hosted llama.cpp model. Sources: [base bundle composition](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/bundle/base/cordis.patch.yml) and [`llm-pi-ai` contract](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/llm/llm-pi-ai/README.md).

### Exact Qwen setup

Start once so `dsh` initializes `~/.dsh` and its `web` profile:

```bash
npx @deepseek-ai/dsh@0.1.0-rc.8 web --no-open
```

Then add the following to `~/.dsh/settings.yaml` (or `$DSH_HOME/settings.yaml` when `DSH_HOME` is set):

```yaml
llm-pi-ai:
  providers:
    spark-qwen:
      displayName: Spark Qwen3.8 27B
      apiKeyEnv: SPARK_QWEN_LOCAL_KEY
      api: openai-completions
      baseURL: http://127.0.0.1:30000/v1
      defaultContextWindow: 65536
      defaultMaxTokens: 16384
      compat:
        supportsDeveloperRole: false
        supportsUsageInStreaming: true
        maxTokensField: max_tokens
        supportsStrictMode: false
      models:
        - id: Qwen/Qwen3.8-27B
          name: Qwen3.8 27B (DGX Spark)
          contextWindow: 65536
          maxTokens: 16384

agent-default-model:
  provider: spark-qwen
  model: Qwen/Qwen3.8-27B
```

The underlying pi-ai OpenAI-compatible client still requires an API key value even when the server does not authenticate. DeepSeek Harness documents a placeholder credential as the keyless-local-server workaround. Put this non-secret placeholder in `~/.dsh/.credentials.yaml`:

```yaml
SPARK_QWEN_LOCAL_KEY: local-no-auth
```

The route and model can instead be added from the Web UI's Models page. Settings and credentials are hot-reloaded; a new session uses the `agent-default-model` selection, while an existing session retains its logged route. Sources: [`llm-pi-ai` dynamic configuration and keyless note](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/llm/llm-pi-ai/README.md#dynamic-configuration-settings--credentials), [default model service](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/core/agent-default-model/README.md), and [home-path resolution](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/util/home-paths/README.md).

Run either UI or headless mode:

```bash
npx @deepseek-ai/dsh@0.1.0-rc.8 web --no-open

npx @deepseek-ai/dsh@0.1.0-rc.8 --profile headless \
  'Run uname -m with bash and report only its output.'
```

### Why not use the native adapter for Qwen?

The native adapter would technically reach the server with:

```bash
DEEPSEEK_BASE_URL=http://127.0.0.1:30000/v1
DEEPSEEK_API_KEY=local-no-auth
```

It appends `/chat/completions`, passes arbitrary model IDs, sends standard tools, and parses streamed `reasoning_content` and `tool_calls`. However, it also sends DeepSeek-specific `thinking`/`reasoning_effort` fields, mandatory harness identity headers, and DeepSeek reasoning-passback semantics. Those are appropriate for V4 and unnecessary for Qwen. See the [native adapter request contract](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/llm/llm-deepseek/README.md) and [wire serialization](https://github.com/deepseek-ai/deepseek-harness/blob/141eb6fef83422698aef7a981029e843e8161534/packages/llm/llm-deepseek/src/serialize.ts).

### Tool-call caveats

- The generic adapter and native adapter both use ordinary OpenAI function schemas. llama.cpp must convert the model's emitted syntax into streamed `delta.tool_calls`; `--jinja` is therefore required.
- Keep `supportsStrictMode: false` unless a smoke test proves the local endpoint accepts OpenAI's per-tool `strict` field.
- Reasoning configuration is intentionally omitted from the initial Qwen profile. First validate text and tools. A later profile can add model-specific `reasoningEfforts` and `thinkingFormat` after confirming the exact llama.cpp request/response shape.
- DeepSeek Harness is moving quickly. Pin the RC during setup and revalidate the settings schema before upgrades.

## 4. Latest DeepSeek release and DGX Spark feasibility

### Latest official release: DeepSeek-V4-Pro-0813

As of the research date, the newest official checkpoint in the DeepSeek organization is [`deepseek-ai/DeepSeek-V4-Pro-0813`](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813). Its commit history dates the release to 2026-08-13: [official repository history](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813/commits/main).

Key facts from the official card and config:

- flagship MoE: approximately 1.6T target-model parameters and 49B activated per token;
- 1,048,576-token configured context;
- 61 transformer layers, 384 routed experts plus one shared expert in MoE layers, six routed experts selected per token;
- hybrid Compressed Sparse Attention and Heavily Compressed Attention, mHC residuals, and an attached DSpark speculative-decoding module;
- official checkpoint: 66 safetensor shards, about **893 GB**, mixed FP4 expert and FP8 weights;
- official local path converts the Hugging Face weights to DeepSeek's custom PyTorch format and uses model parallelism; the example is `MP=4`/four processes;
- official serving examples use vLLM or SGLang on a four-GPU GB300 node;
- repository and weights: MIT.

Sources: [model card](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813), [file tree](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813/tree/main), [config](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813/blob/main/config.json), [local inference instructions](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813/blob/main/inference/README.md), and [license](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813/blob/main/LICENSE).

NVIDIA specifies 128 GB of coherent unified system memory for one DGX Spark. That memory is shared by the OS, CPU, GPU, model, compute buffers, and KV cache. An 893 GB checkpoint is roughly seven times the entire memory pool. MoE activation sparsity reduces work per token; it does not remove the need to retain the routed expert weights. Therefore **Pro-0813 cannot be hosted in-core on one Spark**. Source: [NVIDIA DGX Spark hardware specification](https://docs.nvidia.com/dgx/dgx-spark/hardware.html).

The official DeepSeek API exposes the stable model ID `deepseek-v4-pro` through OpenAI Chat Completions and the Anthropic API. That hosted route can be used by both harnesses, but it is not local inference. Source: [DeepSeek V4 API announcement](https://api-docs.deepseek.com/news/news260424/).

### Latest Flash release: DeepSeek-V4-Flash-0731

[`DeepSeek-V4-Flash-0731`](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731) is the latest official Flash checkpoint:

- 284B target parameters, 13B activated per token; the attached DSpark module brings the repository's reported tensor count to about 304B;
- 1M context;
- official mixed FP4/FP8 safetensors total **167 GB**;
- MIT license;
- official vLLM example uses four GB300 GPUs.

The 167 GB official checkpoint also does not fit in 128 GB. “DSpark” in these model names means DeepSeek's speculative decoding method; it does **not** mean NVIDIA DGX Spark. Sources: [official Flash-0731 card](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731), [official file tree](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731/tree/main), and [DeepSeek's DSpark checkpoint note](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-DSpark).

### Experimental one-Spark V4 candidate

The llama.cpp organization publishes [`ggml-org/DeepSeek-V4-Flash-0731-GGUF`](https://huggingface.co/ggml-org/DeepSeek-V4-Flash-0731-GGUF) with these main-model choices:

| GGUF | Size | One Spark |
|---|---:|---|
| MXFP4 | 155 GB | No |
| Q2_K | 117 GB | Too little safe runtime headroom |
| Q2_K_S | 98.6 GB | Plausible but tight and experimental |

The repo also contains roughly 10.8 GB DSpark draft artifacts. Start without them. A 98.6 GB file leaves only about 29 GB of the advertised 128 GB before the OS, CUDA/compute buffers, and KV cache, so begin at 8K context and measure actual residency before increasing it. The repository notes that the Q2 models were produced without an imatrix calibration. Sources: [GGUF model card](https://huggingface.co/ggml-org/DeepSeek-V4-Flash-0731-GGUF) and [exact files and sizes](https://huggingface.co/ggml-org/DeepSeek-V4-Flash-0731-GGUF/tree/main).

The current local llama.cpp revision contains a dedicated `deepseek4` graph and DeepSeek V4 chat/tool parser, so the backend architecture is present: [DeepSeek V4 model implementation](https://github.com/ggml-org/llama.cpp/blob/3e7344670adf63ce28527a4d42f2d71eca27c41e/src/models/deepseek4.cpp) and [V4 chat/tool handling](https://github.com/ggml-org/llama.cpp/blob/3e7344670adf63ce28527a4d42f2d71eca27c41e/common/chat.cpp#L2090).

A conservative first launch would be:

```bash
CUDA_DEVICE_MIN_SYS_MEM_MB=0 \
./llama.cpp/build/bin/llama-server \
  -hf ggml-org/DeepSeek-V4-Flash-0731-GGUF:Q2_K_S \
  --alias deepseek-ai/DeepSeek-V4-Flash-0731 \
  --host 127.0.0.1 \
  --port 30001 \
  --ctx-size 8192 \
  --parallel 1 \
  --n-gpu-layers all \
  --fit off \
  --no-repack \
  --no-warmup \
  --flash-attn off \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --jinja \
  --reasoning-format deepseek \
  --reasoning-preserve
```

These settings favor correctness and peak-memory control. Current llama.cpp reports document silent V4 corruption with a quantized K cache and with CUDA flash attention when a prompt spans multiple forward passes; the workspace therefore starts with FP16 KV and flash attention disabled. Sources: [quantized K-cache issue](https://github.com/ggml-org/llama.cpp/issues/25382) and [multi-pass CUDA flash-attention issue](https://github.com/ggml-org/llama.cpp/issues/26509).

This is a feasibility experiment, not a performance promise. Before connecting a harness, require all four checks:

1. the server loads without swapping or an OOM;
2. a plain streamed chat completes;
3. a forced single function call is emitted as `delta.tool_calls`;
4. a tool-result follow-up completes with reasoning passback.

Once it passes, point either harness at port `30001` using the same configuration patterns above, model ID `deepseek-ai/DeepSeek-V4-Flash-0731`, and the **actually deployed** context of 8,192. Increase context only after observing memory headroom.

### Practical smaller DeepSeek fallback

[`deepseek-ai/DeepSeek-R1-0528-Qwen3-8B`](https://huggingface.co/deepseek-ai/DeepSeek-R1-0528-Qwen3-8B) is an official distilled model with:

- 8B parameters;
- about 16.4 GB of BF16 safetensors;
- `max_position_embeddings: 131072`;
- MIT license.

It easily fits in BF16 on the Spark, and a Q4/Q6 GGUF leaves ample context and concurrency headroom. A GGUF is a conversion from the official checkpoint rather than a DeepSeek-published artifact. For coding-agent use, validate tool calling explicitly: older llama.cpp issues around R1 tool templates show why “text generation works” is not sufficient proof of a stable agent loop. The existing Qwen3.8-27B is likely the stronger default local coding model unless an evaluation demonstrates an R1-specific advantage.

## 5. Recommended rollout

1. Integrate the already-working Qwen server into **jcode** and run text plus shell-tool smokes.
2. Integrate that same server into **DeepSeek Harness** through `llm-pi-ai` and repeat the same tool test.
3. Keep Qwen as the daily local model.
4. If V4 experimentation is desired, download only the 98.6 GB Flash-0731 `Q2_K_S` GGUF, launch it on a second port with an 8K context, and verify quality and tool stability before wiring either harness.
5. Use `deepseek-v4-pro` through the official DeepSeek API when the latest Pro quality is required. A single DGX Spark cannot host Pro-0813 locally.
