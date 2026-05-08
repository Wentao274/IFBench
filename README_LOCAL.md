
## IFBench 本地模型测试操作步骤

### 步骤一： 获取IFBench仓库目录后，在根目录执行
```shell
uv sync --frozen
```
### 步骤二： 进入uv虚拟环境
```shell
souce .venv/bin/activate
```
### 步骤三：执行测试
```shell
nohup bash ./ifbench_test.sh http://127.0.0.1:8080/v1 ${api-key} ${model_name} > ./ifb_test.log 2>&1 &

实际使用示例：
nohup bash ./ifbench_test.sh http://127.0.0.1:8080/v1 abc123 minimax-m2.5 > ./ifb_test_mm25.log 2>&1 &

```
### 步骤四：测试完成后，查看结果 （结果的前面一部分内容示例如下）：
```shell
Loaded 300 prompts from data/IFBench_test.jsonl
Model: minimax-m2.5
API: http://127.0.0.1:8080/v1
TOP_P: 0.95
TOP_K: 40
TEAMPERATURE: 1.0
MAX_TOKENS: 8192
WORKERS: 32
Generating responses for 300 prompts...
Generating: 100%|██████████| 300/300 [33:51<00:00,  6.77s/it]

Saved 300 responses to data/mm25-responses.jsonl

Run evaluation with:
  uv run python3 -m run_eval --input_data=data/IFBench_test.jsonl --input_response_data=data/mm25-responses.jsonl --output_dir=eval
Processed 300 responses
Changed 250 responses (83.3%)
Output: data/mm25-clean.jsonl
I0506 21:30:11.367919 139928561730752 run_eval.py:56] Generating eval_results_strict...
I0506 21:30:11.786441 139928561730752 run_eval.py:62] Accuracy: 0.623333
I0506 21:30:11.791992 139928561730752 run_eval.py:76] Generated: eval/mm25-clean-eval_results_strict.jsonl
I0506 21:30:11.792427 139928561730752 run_eval.py:56] Generating eval_results_loose...
I0506 21:30:13.049116 139928561730752 run_eval.py:62] Accuracy: 0.660000
I0506 21:30:13.054249 139928561730752 run_eval.py:76] Generated: eval/mm25-clean-eval_results_loose.jsonl
================================================================
eval/mm25-clean-eval_results_strict.jsonl Accuracy Scores:
prompt-level: 0.6233333333333333
instruction-level: 0.625

```

### 注意事项
如果输出的结果日志里有类似下面这样的timed out的失败项，则最好重新进行测试，直到无超时问题出现为止，测试结果才算有效测试结果。

```text
Saved 300 responses to data/mm25-responses.jsonl
Errors: 32
  - Key 48: timed out
  - Key 49: timed out
  - Key 81: timed out
  - Key 88: timed out
  - Key 91: timed out
```

**为了尽可能减少超时问题发生，可以增加请求的超时时间，修改generate_responses.py中的代码**
```python
    response = client.post(
        f"{api_base.rstrip('/')}/chat/completions",
        headers=headers,
        json=payload,
        timeout=3600,
    )
```

