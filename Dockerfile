# ---------- build stage ----------
FROM python:3.10-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone repo (contains pyproject.toml + uv.lock)
RUN git clone --depth 1 https://github.com/Wentao274/IFBench.git .

# Create venv and install from lockfile (exact reproducibility)
RUN uv sync --frozen --no-dev

# Download NLTK data into project dir
RUN .venv/bin/python -c "\
import nltk; \
nltk.download('punkt_tab', download_dir='/app/nltk_data'); \
nltk.download('averaged_perceptron_tagger_eng', download_dir='/app/nltk_data'); \
nltk.download('words', download_dir='/app/nltk_data')"

# ---------- runtime stage ----------
FROM python:3.10-slim

WORKDIR /app

# Copy venv (self-contained) + project code
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/*.py /app/
COPY --from=builder /app/ifbench_test.sh /app/
COPY --from=builder /app/nltk_data /app/nltk_data
COPY --from=builder /app/data /app/data
COPY --from=builder /app/eval /app/eval

# Activate venv via PATH (no need for "source activate")
ENV PATH="/app/.venv/bin:$PATH" \
    VIRTUAL_ENV="/app/.venv" \
    NLTK_DATA=/app/nltk_data \
    PYTHONUNBUFFERED=1

# Default env vars (override at runtime)
ENV API_BASE="http://host.docker.internal:8080/v1" \
    API_KEY="" \
    MODEL="" \
    TEMPERATURE="0.6" \
    MAX_TOKENS="8192" \
    SEED="42" \
    TOP_P="0.95" \
    TOP_K="40" \
    INPUT_FILE="data/IFBench_test.jsonl" \
    OUTPUT_FILE="" \
    WORKERS="8"

# Data and eval output volumes
VOLUME ["/app/data", "/app/eval"]

ENTRYPOINT ["bash", "./ifbench_test.sh"]
CMD ["http://host.docker.internal:8080/v1", "", ""]
