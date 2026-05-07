#!/bin/bash
ROOT_PATH=$(cd `dirname $0`; pwd)

echo $ROOT_PATH
cd ${ROOT_PATH}

CurDate=`date +'%Y%m%d'`

export NLTK_DATA=${ROOT_PATH}/nltk_data

API_BASE="${1:-http://127.0.0.1:8080/v1}"
API_KEY="${2:-abc123}"
MODEL="${3:-glm-5}"

cat > .env << EOF
api_base=$API_BASE
api_key=$API_KEY
model=$MODEL
temperature=1.0
top_p=0.95
top_k=40
max_tokens=8192
seed=42
input_file=data/IFBench_test.jsonl
output_file=data/${MODEL}-responses.jsonl
workers=32
EOF

# 2. 生成模型响应
python3 generate_responses.py

# 快速测试
#uv run python generate_responses.py --limit 5

# 3. Thinking 模型后处理（重要！）
python3 postprocess_thinking.py data/${MODEL}-responses.jsonl -o data/${MODEL}-clean.jsonl

# 4. 运行评估
python3 -m run_eval \
	--input_data=data/IFBench_test.jsonl \
	--input_response_data=data/${MODEL}-clean.jsonl \
	--output_dir=eval

