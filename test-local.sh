#!/usr/bin/env bash
set -euo pipefail

# Check tools
for cmd in jq curl openssl file base64; do
  command -v $cmd &>/dev/null || { echo "❌ Missing: $cmd"; exit 1; }
done

# Hardcoded test configuration
CREDS="../popup-maker-378201-7770feee46f8.json"
FOLDER_ID="1DnYdcPx3cf1UX3p1zDX6CEgCNYmLB3a6"

echo "🧪 Testing Google Drive Upload"
echo "📁 Credentials: $CREDS"
echo "📂 Folder ID: $FOLDER_ID"
echo ""

# Verify credentials file exists
[ -f "$CREDS" ] || { echo "❌ Credentials not found: $CREDS"; exit 1; }

# Create test file with timestamp
TEST_FILE="test-upload.zip"
echo "test upload $(date)" | zip -q "$TEST_FILE" -
echo "📦 Created test file: $TEST_FILE"

# Set env vars for upload script
export INPUT_CREDENTIALS=$(base64 -i "$CREDS")
export INPUT_FOLDER_ID="$FOLDER_ID"
export INPUT_FILENAME="$TEST_FILE"
export INPUT_OVERWRITE="true"
export INPUT_SHARING="anyone"
# INPUT_LINK_DISCOVERABLE defaults to "false" (link-only, not searchable)

echo ""
echo "→ Running upload script..."
./upload.sh && echo "✅ Test completed successfully" || echo "❌ Test failed"
