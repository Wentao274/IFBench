# IFBench 本地与 Jenkins 测试指南

本文档介绍如何使用 `ifbench_test.sh` 手动执行 IFBench 精度测试，以及通过 `Jenkinsfile` 自动触发测试的完整流程。

---

## 一、环境准备

### 1. 依赖安装

进入 IFBench 仓库根目录，使用 `uv` 同步依赖（首次执行会创建 `.venv` 虚拟环境）：

```shell
uv sync --frozen
```

> 若网络受限，可临时设置代理（参考 Jenkinsfile 中的做法）：

### 2. 激活虚拟环境

```shell
source .venv/bin/activate
```

### 3. 赋予测试脚本执行权限

```shell
chmod +x ifbench_test.sh
```

### 4. NLTK 数据

脚本执行时会自动设置 `NLTK_DATA` 环境变量指向仓库内的 `nltk_data/` 目录，无需额外下载。

---

## 二、手动执行测试

### 1. 用法

```shell
./ifbench_test.sh <api_base> <api_key> <model> <chip>
```

| 参数       | 说明                                          | 是否必填 |
| ---------- | --------------------------------------------- | -------- |
| `api_base` | OpenAI 兼容 API 地址，需以 `/v1` 结尾         | 是       |
| `api_key`  | API Key，无需认证时传空字符串 `""`            | 否       |
| `model`    | 模型名称，支持带路径前缀（如 `org/model`）    | 是       |
| `chip`     | 芯片平台名称，用于结果目录归类（如 `nvidia-h100`） | 是       |

### 2. 执行示例

后台运行并将日志输出到文件：

```shell
nohup bash ./ifbench_test.sh http://127.0.0.1:8080/v1 abc123 minimax-m2.5 nvidia-h100 > ./ifb_test_mm25.log 2>&1 &
```

无需认证时：

```shell
nohup bash ./ifbench_test.sh http://127.0.0.1:8080/v1 "" minimax-m2.5 nvidia-h100 > ./ifb_test_mm25.log 2>&1 &
```

### 3. 脚本内部执行流程

脚本会自动完成以下步骤：

1. **生成 `.env` 配置文件**，包含以下默认参数：
   - `temperature=1.0`、`top_p=0.95`、`top_k=40`
   - `max_tokens=16384`、`seed=42`、`workers=8`
   - `input_file=data/IFBench_test.jsonl`
   - `output_file=data/<chip>/<model>/<时间戳>/<model>-responses.jsonl`
2. **创建输出目录** `data/<chip>/<model>/<时间戳>/`
3. **生成模型响应**：`uv run python3 generate_responses.py`
4. **Thinking 模型后处理**：`uv run python3 postprocess_thinking.py`，生成 `<model>-clean.jsonl`
5. **运行评估**：`uv run python3 -m run_eval`，结果输出到 `eval/<chip>/<model>/<时间戳>/`

### 4. 查看测试结果

测试完成后，日志中会输出关键指标，示例片段如下：

```text
Loaded 300 prompts from data/IFBench_test.jsonl
Model: minimax-m2.5
API: http://127.0.0.1:8080/v1
TOP_P: 0.95
TOP_K: 40
TEAMPERATURE: 1.0
MAX_TOKENS: 16384
WORKERS: 8
Generating responses for 300 prompts...
Generating: 100%|██████████| 300/300 [33:51<00:00,  6.77s/it]

Saved 300 responses to data/<chip>/<model>/<时间戳>/<model>-responses.jsonl
Processed 300 responses
Changed 250 responses (83.3%)
Output: data/<chip>/<model>/<时间戳>/<model>-clean.jsonl
I0506 21:30:11.367919 ... run_eval.py:56] Generating eval_results_strict...
I0506 21:30:11.786441 ... run_eval.py:62] Accuracy: 0.623333
I0506 21:30:11.792427 ... run_eval.py:76] Generated: eval/.../eval_results_strict.jsonl
I0506 21:30:11.792427 ... run_eval.py:56] Generating eval_results_loose...
I0506 21:30:13.049116 ... run_eval.py:62] Accuracy: 0.660000
================================================================
eval/.../eval_results_strict.jsonl Accuracy Scores:
prompt-level: 0.6233333333333333
instruction-level: 0.625
```

重点关注 `Accuracy (Strict)` 与 `Accuracy (Loose)` 两个指标。

---

## 三、Jenkins 流水线

`Jenkinsfile` 定义了通过 SSH 远程执行 IFBench 测试的自动化流水线。

### 1. 执行节点与远程主机

- **Jenkins Agent**：`slave-3`
- **远程执行主机**：`10.201.132.50`（用户 `root`），通过 `sshagent` 凭据 `HOST_SSH_KEY` 免密登录
- **远程工作目录**（`WORK_DIR`）：默认 `/dingofs/data2/userdata/liwt/maas-image/IFBench`

### 2. 构建参数

| 参数           | 类型     | 默认值                                              | 说明                                            |
| -------------- | -------- | --------------------------------------------------- | ----------------------------------------------- |
| `TESTER`       | string   | `liwt`                                              | 测试人员名称（必填）                            |
| `CHIP`         | string   | `nvidia-h100`                                       | 芯片平台名称（必填）                            |
| `ENGINE`       | choice   | `vllm` / `sglang`                                   | 推理框架（必填）                                |
| `PD`           | choice   | `agg` / `disagg`                                    | PD 分离模式（`agg` 非分离，`disagg` PD 分离）   |
| `MODEL`        | string   | `kimi-k2.5`                                         | 模型服务名称（必填）                            |
| `BASE_URL`     | string   | `http://10.201.149.10:8080`                         | API 地址（必填，自动补全 `/v1`）                |
| `API_KEY`      | password | 空                                                  | API Key（可选，无需认证时留空）                 |
| `DESCRIPTION`  | string   | 空                                                  | 模型服务的描述信息                              |
| `RECIPIENTS`   | text     | `liwt@zetyun.com`                                   | 测试报告邮件接收者（逗号分隔）                  |
| `WORK_DIR`     | string   | `/dingofs/data2/userdata/liwt/maas-image/IFBench`   | 测试仓库目录（请勿改动）                        |

### 3. 执行阶段

流水线包含以下阶段，按顺序执行：

1. **打印测试参数**：输出本次构建的所有参数信息。
2. **API 连通性预检**：SSH 到远程主机，对 `/models` 与 `/chat/completions` 接口发起请求。若失败，将构建标记为 `UNSTABLE` 并设置 `CONNECTIVITY_FAILED`，后续阶段跳过。
3. **环境检查**（连通性通过后执行）：
   - 清理可能残留的 `ifbench_test` 进程
   - 赋予脚本执行权限
   - 若 `.venv` 不存在，则通过代理执行 `uv sync --frozen` 创建虚拟环境
   - 激活虚拟环境
4. **运行 IFBench 测试**（连通性通过后执行）：
   - 创建输出目录 `output/<TESTER>/<BUILD_NUMBER>/<CHIP>/<MODEL>/`
   - 执行 `./ifbench_test.sh <baseUrl> <apiKey> <MODEL> <CHIP>`
   - 日志重定向到 `ifb_results_build<BUILD_NUMBER>.log`
5. **拉取测试结果**：通过 `scp` 将远程的测试结果目录、`.env` 及连通性预检日志拉取到 Jenkins 的 `reports/<BUILD_NUMBER>/`，并使用 `iconv` 转换日志为 UTF-8。
6. **发送邮件**：解析日志中的关键指标（请求数、Errors、Changed、Accuracy Strict/Loose、TOP_P/TOP_K/Temperature/Max Tokens/Workers 等），生成 HTML 邮件报告发送给 `RECIPIENTS`，并附带日志附件。

### 4. 构建后处理

- **归档产物**：`reports/<BUILD_NUMBER>/**` 全部归档至 Jenkins
- **清理工作空间**：每次构建后执行 `cleanWs()`

### 5. 构建状态说明

| 情况                       | 构建结果     |
| -------------------------- | ------------ |
| 连通性预检失败             | `UNSTABLE`   |
| 测试阶段失败               | `UNSTABLE`（阶段 `FAILURE`） |
| 邮件/拉取结果失败          | `UNSTABLE`（阶段 `FAILURE`） |
| 全部成功                   | `SUCCESS`    |

---

## 四、注意事项

如果输出的结果日志里有类似下面这样的 `timed out` 的失败项，则最好重新进行测试，直到无超时问题出现为止，测试结果才算有效测试结果。

```text
Saved 300 responses to data/mm25-responses.jsonl
Errors: 32
  - Key 48: timed out
  - Key 49: timed out
  - Key 81: timed out
  - Key 88: timed out
  - Key 91: timed out
```

**为了尽可能减少超时问题发生，可以增加请求的超时时间，修改 `generate_responses.py` 中的代码：**

```python
    response = client.post(
        f"{api_base.rstrip('/')}/chat/completions",
        headers=headers,
        json=payload,
        timeout=3600,
    )
```
