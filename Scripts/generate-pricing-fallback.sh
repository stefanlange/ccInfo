#!/bin/bash
set -e

# Determine repository structure
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default output path (can be overridden by argument)
OUTPUT_PATH="${1:-$REPO_ROOT/CCInfo/CCInfo/Resources/claude-pricing-fallback.json}"

# LiteLLM pricing data URL
LITELLM_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

# Temporary files
TEMP_FULL_JSON=$(mktemp)
TEMP_FILTERED_JSON=$(mktemp)

# Cleanup on exit
trap 'rm -f "$TEMP_FULL_JSON" "$TEMP_FILTERED_JSON"' EXIT

echo "Fetching LiteLLM pricing data from GitHub..."

# Fetch the full pricing JSON with timeout and error handling
if ! curl -f -s --connect-timeout 15 "$LITELLM_URL" -o "$TEMP_FULL_JSON"; then
    echo "ERROR: Failed to fetch pricing data from $LITELLM_URL" >&2
    exit 1
fi

echo "Filtering to Claude models only..."

# Filter to Claude models using Python (available on all macOS systems)
python3 - "$TEMP_FULL_JSON" "$TEMP_FILTERED_JSON" << 'PYTHON_EOF'
import json
import sys

# Load the full pricing data
with open(sys.argv[1], 'r') as f:
    data = json.load(f)

# Filter to Claude models only
# - Key must contain "claude" (case-insensitive)
# - Value must be a dict with pricing fields
# - Must have input_cost_per_token (skip metadata entries)
claude_models = {
    k: v for k, v in data.items()
    if 'claude' in k.lower()
    and isinstance(v, dict)
    and 'input_cost_per_token' in v
}

# Write filtered data with sorted keys for deterministic output
with open(sys.argv[2], 'w') as f:
    json.dump(claude_models, f, indent=2, sort_keys=True)

PYTHON_EOF

echo "Validating output..."

# Validate the filtered JSON is valid
if ! python3 -m json.tool "$TEMP_FILTERED_JSON" > /dev/null 2>&1; then
    echo "ERROR: Generated JSON is invalid" >&2
    exit 1
fi

# Count models and ensure we have at least 10
MODEL_COUNT=$(python3 -c "import json; print(len(json.load(open('$TEMP_FILTERED_JSON'))))")

if [ "$MODEL_COUNT" -lt 10 ]; then
    echo "ERROR: Only found $MODEL_COUNT Claude models (expected at least 10)" >&2
    exit 1
fi

# Ensure output directory exists
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# Move the validated file to final location
mv "$TEMP_FILTERED_JSON" "$OUTPUT_PATH"

echo "✓ Generated claude-pricing-fallback.json with $MODEL_COUNT models"
echo "  Output: $OUTPUT_PATH"
