#!/usr/bin/env python3
"""Post-process thinking model responses to extract final answers."""

import json
import re
import argparse
from pathlib import Path


def extract_final_answer(response: str) -> str:
    """Extract final answer from thinking model output.

    Handles multiple formats:
    - <think>...</think> blocks
    - <thinking>...</thinking> blocks
    - ▂▂▂...▂▂▂ style blocks (some models use this)
    """
    if not response:
        return response

    # Patterns to remove thinking blocks
    patterns = [
        r'<think>.*?</think>\s*',       # <think>...</think>
        r'<thinking>.*?</thinking>\s*', # <thinking>...</thinking>
    ]

    result = response
    for pattern in patterns:
        # Use DOTALL to match across newlines
        result = re.sub(pattern, '', result, flags=re.DOTALL | re.IGNORECASE)

    # Clean up leading whitespace
    result = result.strip()

    return result


def process_file(input_file: str, output_file: str | None = None):
    """Process a JSONL file of responses."""
    input_path = Path(input_file)
    if output_file is None:
        output_file = str(input_path).replace('-responses.jsonl', '-responses-processed.jsonl')

    processed = 0
    changed = 0

    with open(input_file, 'r') as fin, open(output_file, 'w') as fout:
        for line in fin:
            data = json.loads(line)
            original = data.get('response', '')
            processed_response = extract_final_answer(original)

            if processed_response != original:
                changed += 1
                data['response'] = processed_response

            fout.write(json.dumps(data, ensure_ascii=False) + '\n')
            processed += 1

    print(f"Processed {processed} responses")
    print(f"Changed {changed} responses ({changed/processed*100:.1f}%)")
    print(f"Output: {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Post-process thinking model responses")
    parser.add_argument("input_file", help="Input JSONL file with responses")
    parser.add_argument("-o", "--output", help="Output file (default: input-processed.jsonl)")
    args = parser.parse_args()

    process_file(args.input_file, args.output)


if __name__ == "__main__":
    main()
