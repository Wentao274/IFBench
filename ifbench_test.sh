#!/bin/bash
ROOT_PATH=$(cd `dirname $0`; pwd)

echo $ROOT_PATH
cd ${ROOT_PATH}

CurDate=$(date +'%Y%m%d%H%M%S')

export NLTK_DATA=${ROOT_PATH}/nltk_data

if [ ${#1} -gt 0 ] && [ ${#3} -gt 0 ] && [ ${#4} -gt 0 ]; then
    API_BASE="$1"
    API_KEY="${2:-}"
    MODEL="$3"
    CHIP="$4"
else
    echo "Usage: $0 <api_base> <api_key> <model> <chip>"
    exit 1
fi

if [[ "$MODEL" == *"/"* ]]; then
    MODEL=$(echo "$MODEL" | awk -F'/' '{print $NF}')
fi

rm -f .env

cat > .env << EOF
api_base=$API_BASE
api_key=$API_KEY
model=$MODEL
temperature=1.0
top_p=0.95
top_k=40
max_tokens=16384
seed=42
input_file=data/IFBench_test.jsonl
output_file=data/${CHIP}/${MODEL}/${CurDate}/${MODEL}-responses.jsonl
workers=8
EOF

mkdir -p data/${CHIP}/${MODEL}/${CurDate}

# 2. 生成模型响应
uv run python3 generate_responses.py

# 快速测试
#uv run python generate_responses.py --limit 5

# 3. Thinking 模型后处理（重要！）
uv run python3 postprocess_thinking.py data/${CHIP}/${MODEL}/${CurDate}/${MODEL}-responses.jsonl -o data/${CHIP}/${MODEL}/${CurDate}/${MODEL}-clean.jsonl

# 4. 运行评估
# mkdir -p output/${CHIP}/${MODEL}/${CurDate}
mkdir -p eval/${CHIP}/${MODEL}/${CurDate}
uv run python3 -m run_eval \
        --input_data=data/IFBench_test.jsonl \
        --input_response_data=data/${CHIP}/${MODEL}/${CurDate}/${MODEL}-clean.jsonl \
        --output_dir=eval/${CHIP}/${MODEL}/${CurDate}