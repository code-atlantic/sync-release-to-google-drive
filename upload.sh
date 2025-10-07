#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Google Drive Upload Action
# Uploads files to Google Drive with automatic sharing configuration
# ============================================================================

echo "🚀 Starting Google Drive upload..."

# Parse inputs
FILENAME="${INPUT_FILENAME}"
FOLDER_ID="${INPUT_FOLDER_ID}"
OVERWRITE="${INPUT_OVERWRITE:-true}"
SHARING="${INPUT_SHARING:-anyone}"
SHARING_ROLE="${INPUT_SHARING_ROLE:-reader}"
SHARING_EMAIL="${INPUT_SHARING_EMAIL:-}"
SHARING_DOMAIN="${INPUT_SHARING_DOMAIN:-}"

# Validate required inputs
if [ -z "$FILENAME" ] || [ -z "$FOLDER_ID" ]; then
  echo "❌ ERROR: filename and folder_id are required"
  exit 1
fi

# ============================================================================
# AUTHENTICATION
# ============================================================================

echo "🔐 Authenticating with Google Drive API..."

# Decode credentials
CREDENTIALS=$(echo "$INPUT_CREDENTIALS" | base64 -d)
CLIENT_EMAIL=$(echo "$CREDENTIALS" | jq -r '.client_email')
PRIVATE_KEY=$(echo "$CREDENTIALS" | jq -r '.private_key')

if [ -z "$CLIENT_EMAIL" ] || [ -z "$PRIVATE_KEY" ]; then
  echo "❌ ERROR: Invalid credentials format"
  exit 1
fi

# Create JWT for OAuth
NOW=$(date +%s)
EXP=$((NOW + 3600))

HEADER='{"alg":"RS256","typ":"JWT"}'
CLAIM=$(jq -nc \
  --arg iss "$CLIENT_EMAIL" \
  --arg scope "https://www.googleapis.com/auth/drive" \
  --arg aud "https://oauth2.googleapis.com/token" \
  --arg exp "$EXP" \
  --arg iat "$NOW" \
  '{"iss":$iss,"scope":$scope,"aud":$aud,"exp":($exp|tonumber),"iat":($iat|tonumber)}')

# Sign JWT
JWT_HEADER=$(echo -n "$HEADER" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT_CLAIM=$(echo -n "$CLAIM" | base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT_SIGNATURE=$(echo -n "${JWT_HEADER}.${JWT_CLAIM}" | \
  openssl dgst -binary -sha256 -sign <(echo "$PRIVATE_KEY") | \
  base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT="${JWT_HEADER}.${JWT_CLAIM}.${JWT_SIGNATURE}"

# Get access token
TOKEN_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${JWT}")
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
  echo "❌ Failed to get access token"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

echo "✅ Authentication successful"

# ============================================================================
# FILE UPLOAD
# ============================================================================

echo "📦 Uploading file: ${FILENAME}"

# Verify file exists
if [ ! -f "$FILENAME" ]; then
  echo "❌ ERROR: File not found: ${FILENAME}"
  exit 1
fi

FILE_NAME=$(basename "$FILENAME")
MIME_TYPE=$(file --mime-type -b "$FILENAME")

# Check if file exists and handle overwrite
if [ "$OVERWRITE" == "true" ]; then
  echo "🔍 Checking for existing file..."
  SEARCH_RESPONSE=$(curl -s -G \
    "https://www.googleapis.com/drive/v3/files" \
    --data-urlencode "q=name='${FILE_NAME}' and '${FOLDER_ID}' in parents and trashed=false" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")

  EXISTING_FILE_ID=$(echo "$SEARCH_RESPONSE" | jq -r '.files[0].id // empty')

  if [ -n "$EXISTING_FILE_ID" ]; then
    echo "🗑️  Deleting existing file: ${EXISTING_FILE_ID}"
    curl -s -X DELETE \
      "https://www.googleapis.com/drive/v3/files/${EXISTING_FILE_ID}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}"
  fi
fi

# Upload file
echo "⬆️  Uploading to Google Drive..."
UPLOAD_RESPONSE=$(curl -s -X POST \
  "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -F "metadata={\"name\":\"${FILE_NAME}\",\"parents\":[\"${FOLDER_ID}\"]};type=application/json;charset=UTF-8" \
  -F "file=@${FILENAME};type=${MIME_TYPE}")

FILE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [ -z "$FILE_ID" ] || [ "$FILE_ID" == "null" ]; then
  echo "❌ Upload failed"
  echo "$UPLOAD_RESPONSE"
  exit 1
fi

echo "✅ Upload successful: ${FILE_ID}"

# ============================================================================
# SHARING CONFIGURATION
# ============================================================================

if [ "$SHARING" != "none" ]; then
  echo "🔓 Configuring file sharing (mode: ${SHARING})..."

  case "$SHARING" in
    anyone)
      # Share with anyone who has the link
      PERM_DATA='{"role":"'${SHARING_ROLE}'","type":"anyone"}'
      ;;
    domain)
      # Share with entire domain
      if [ -z "$SHARING_DOMAIN" ]; then
        echo "❌ ERROR: sharing_domain required for domain sharing mode"
        exit 1
      fi
      PERM_DATA='{"role":"'${SHARING_ROLE}'","type":"domain","domain":"'${SHARING_DOMAIN}'"}'
      ;;
    specific)
      # Share with specific email
      if [ -z "$SHARING_EMAIL" ]; then
        echo "❌ ERROR: sharing_email required for specific sharing mode"
        exit 1
      fi
      PERM_DATA='{"role":"'${SHARING_ROLE}'","type":"user","emailAddress":"'${SHARING_EMAIL}'"}'
      ;;
    *)
      echo "⚠️  Unknown sharing mode: ${SHARING}, skipping"
      PERM_DATA=""
      ;;
  esac

  if [ -n "$PERM_DATA" ]; then
    PERM_RESPONSE=$(curl -s -X POST \
      "https://www.googleapis.com/drive/v3/files/${FILE_ID}/permissions" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$PERM_DATA")

    PERM_ID=$(echo "$PERM_RESPONSE" | jq -r '.id // empty')
    if [ -n "$PERM_ID" ]; then
      echo "✅ Sharing configured successfully"
    else
      echo "⚠️  Sharing configuration may have failed"
      echo "$PERM_RESPONSE"
    fi
  fi
fi

# ============================================================================
# GENERATE OUTPUT LINKS
# ============================================================================

WEB_VIEW_LINK="https://drive.google.com/file/d/${FILE_ID}/view"
DOWNLOAD_LINK="https://drive.google.com/uc?export=download&id=${FILE_ID}"
WEB_CONTENT_LINK="https://drive.google.com/uc?id=${FILE_ID}"

echo ""
echo "📋 Upload Summary:"
echo "  File ID: ${FILE_ID}"
echo "  Filename: ${FILE_NAME}"
echo "  View Link: ${WEB_VIEW_LINK}"
echo "  Download Link: ${DOWNLOAD_LINK}"
echo ""

# Set outputs
{
  echo "file_id=${FILE_ID}"
  echo "file_name=${FILE_NAME}"
  echo "web_view_link=${WEB_VIEW_LINK}"
  echo "download_link=${DOWNLOAD_LINK}"
  echo "web_content_link=${WEB_CONTENT_LINK}"
} >> "$GITHUB_OUTPUT"

echo "✅ Google Drive sync complete!"
