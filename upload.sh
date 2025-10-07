#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Google Drive Upload Action (robust)
# Uploads files to Google Drive with automatic sharing configuration
# - Safe wildcard/multi-file
# - Update-in-place when possible; MD5 skip if identical
# - Retries/timeouts; safer JWT; canonical links
# ============================================================================

echo "🚀 Starting Google Drive upload..."

# ---- deps ------------------------------------------------------------------
for cmd in jq curl openssl file; do
  command -v "$cmd" >/dev/null || { echo "❌ Missing dependency: $cmd"; exit 1; }
done

# Curl defaults (fail fast + retries)
CURL="curl -fsS --retry 5 --retry-all-errors --retry-delay 2 --max-time 300"

# ---- inputs ----------------------------------------------------------------
FILENAME="${INPUT_FILENAME}"
FOLDER_ID="${INPUT_FOLDER_ID}"
OVERWRITE="${INPUT_OVERWRITE:-true}"
SHARING="${INPUT_SHARING:-none}"
SHARING_ROLE="${INPUT_SHARING_ROLE:-reader}"
SHARING_EMAIL="${INPUT_SHARING_EMAIL:-}"
SHARING_DOMAIN="${INPUT_SHARING_DOMAIN:-}"
LINK_DISCOVERABLE="${INPUT_LINK_DISCOVERABLE:-false}" # anyone: allowFileDiscovery

if [ -z "$FILENAME" ] || [ -z "$FOLDER_ID" ]; then
  echo "❌ ERROR: filename and folder_id are required"
  exit 1
fi

# ---- auth ------------------------------------------------------------------
echo "🔐 Authenticating with Google Drive API..."

# Decode credentials
CREDENTIALS=$(echo "$INPUT_CREDENTIALS" | base64 -d)
CLIENT_EMAIL=$(echo "$CREDENTIALS" | jq -r '.client_email')
PRIVATE_KEY=$(echo "$CREDENTIALS" | jq -r '.private_key')

if [ -z "$CLIENT_EMAIL" ] || [ -z "$PRIVATE_KEY" ] || [ "$CLIENT_EMAIL" = "null" ] || [ "$PRIVATE_KEY" = "null" ]; then
  echo "❌ ERROR: Invalid credentials format"
  exit 1
fi

# Helpers
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

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

JWT_HEADER=$(printf %s "$HEADER" | b64url)
JWT_CLAIM=$(printf %s "$CLAIM" | b64url)
JWT_SIGNATURE=$(printf %s "${JWT_HEADER}.${JWT_CLAIM}" | \
  openssl dgst -binary -sha256 -sign <(printf %s "$PRIVATE_KEY") | b64url)
JWT="${JWT_HEADER}.${JWT_CLAIM}.${JWT_SIGNATURE}"

# Get access token
TOKEN_RESPONSE=$($CURL -X POST https://oauth2.googleapis.com/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${JWT}")
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to get access token"
  echo "$(echo "$TOKEN_RESPONSE" | jq '{error,error_description}')" # minimal
  exit 1
fi
echo "::add-mask::$ACCESS_TOKEN"
echo "✅ Authentication successful"

# ---- folder preflight ------------------------------------------------------
if ! $CURL -G "https://www.googleapis.com/drive/v3/files/${FOLDER_ID}" \
     --data-urlencode "fields=id,mimeType" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" | \
     jq -e 'select(.mimeType=="application/vnd.google-apps.folder")' >/dev/null; then
  echo "❌ folder_id is not a folder or not accessible"
  exit 1
fi

# ---- resolve file list -----------------------------------------------------
declare -a files=()
if printf %s "$FILENAME" | grep -q $'\n'; then
  # newline-separated list
  while IFS= read -r line; do
    [[ -n "$line" ]] && files+=("$line")
  done <<<"$FILENAME"
else
  # globbing pattern
  shopt -s nullglob dotglob
  # shellcheck disable=SC2206
  eval "files=( $FILENAME )"
fi
if ((${#files[@]}==0)); then
  echo "❌ No files matched: $FILENAME"
  exit 1
fi

# ---- helpers ---------------------------------------------------------------
stat_size() { { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; } 2>/dev/null || echo ""; }
mime_of() { file --mime-type -b "$1" 2>/dev/null || echo application/octet-stream; }
md5_local() {
  if command -v md5sum >/dev/null; then md5sum "$1" | awk '{print $1}';
  elif command -v md5 >/dev/null; then md5 -q "$1";
  else echo ""; fi
}

# Upload or update a single file
upload_one() {
  local PATH_IN="$1"
  if [ ! -f "$PATH_IN" ]; then
    echo "❌ ERROR: File not found: $PATH_IN"
    return 1
  fi

  local FILE_NAME; FILE_NAME=$(basename "$PATH_IN")
  local MIME_TYPE; MIME_TYPE=$(mime_of "$PATH_IN")
  local SIZE; SIZE=$(stat_size "$PATH_IN")

  echo "📦 Processing: ${FILE_NAME} (${SIZE:-?} bytes)"

  # List files in folder and match by exact name locally
  local SEARCH
  SEARCH=$($CURL -G "https://www.googleapis.com/drive/v3/files" \
    --data-urlencode "q='${FOLDER_ID}' in parents and trashed=false" \
    --data-urlencode "pageSize=1000" \
    --data-urlencode "fields=files(id,name,md5Checksum)" \
    --data-urlencode "supportsAllDrives=true" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")

  mapfile -t MATCHING_IDS < <(jq -r --arg n "$FILE_NAME" '.files[] | select(.name==$n) | .id' <<<"$SEARCH")
  local REMOTE_MD5
  REMOTE_MD5=$(jq -r --arg n "$FILE_NAME" '.files[] | select(.name==$n) | .md5Checksum // empty' <<<"$SEARCH" | head -n1)
  local LOCAL_MD5; LOCAL_MD5=$(md5_local "$PATH_IN" || true)

  local FILE_ID=""
  local SKIPPED=false
  local UPDATED=false

  if [[ -n "$REMOTE_MD5" && -n "$LOCAL_MD5" && "$REMOTE_MD5" == "$LOCAL_MD5" ]]; then
    echo "ℹ️  Skipping upload; identical content (MD5 match)."
    FILE_ID=$(jq -r --arg n "$FILE_NAME" '.files[] | select(.name==$n) | .id' <<<"$SEARCH" | head -n1)
    SKIPPED=true
  else
    # Choose create vs update
    if [[ ${#MATCHING_IDS[@]} -eq 1 && "$OVERWRITE" == "true" ]]; then
      FILE_ID="${MATCHING_IDS[0]}"
      echo "♻️  Updating existing file in-place: $FILE_ID"
      # Initialize resumable update session
      local METADATA; METADATA=$(jq -nc --arg name "$FILE_NAME" '{"name":$name}')
      local SESSION
      SESSION=$($CURL -X PATCH \
        "https://www.googleapis.com/upload/drive/v3/files/${FILE_ID}?uploadType=resumable&supportsAllDrives=true" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json; charset=UTF-8" \
        -H "X-Upload-Content-Type: ${MIME_TYPE}" \
        ${SIZE:+-H "X-Upload-Content-Length: ${SIZE}"} \
        -d "$METADATA" -D - | grep -i '^Location:' | sed 's/^[Ll]ocation: *//' | tr -d '\r')
      if [ -z "$SESSION" ]; then echo "❌ Failed to init update session"; return 1; fi
      $CURL -X PUT "$SESSION" -H "Content-Type: ${MIME_TYPE}" --data-binary "@${PATH_IN}" >/dev/null
      UPDATED=true
    else
      if [[ ${#MATCHING_IDS[@]} -gt 1 && "$OVERWRITE" == "true" ]]; then
        echo "🗑️  Deleting ${#MATCHING_IDS[@]} duplicates before create..."
        for id in "${MATCHING_IDS[@]}"; do
          $CURL -X DELETE "https://www.googleapis.com/drive/v3/files/${id}?supportsAllDrives=true" \
            -H "Authorization: Bearer ${ACCESS_TOKEN}" >/dev/null || true
        done
      elif [[ ${#MATCHING_IDS[@]} -ge 1 && "$OVERWRITE" != "true" ]]; then
        echo "ℹ️  overwrite=false and file exists; using existing."
        FILE_ID=$(jq -r --arg n "$FILE_NAME" '.files[] | select(.name==$n) | .id' <<<"$SEARCH" | head -n1)
        SKIPPED=true
      fi
      if [[ "$SKIPPED" = false ]]; then
        echo "⬆️  Creating new file..."
        local METADATA; METADATA=$(jq -nc --arg name "$FILE_NAME" --arg folderId "$FOLDER_ID" '{"name":$name,"parents":[$folderId]}')
        local SESSION
        SESSION=$($CURL -X POST \
          "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true" \
          -H "Authorization: Bearer ${ACCESS_TOKEN}" \
          -H "Content-Type: application/json; charset=UTF-8" \
          -H "X-Upload-Content-Type: ${MIME_TYPE}" \
          ${SIZE:+-H "X-Upload-Content-Length: ${SIZE}"} \
          -d "$METADATA" -D - | grep -i '^Location:' | sed 's/^[Ll]ocation: *//' | tr -d '\r')
        [ -n "$SESSION" ] || { echo "❌ Failed to initialize upload session"; return 1; }
        local RESP
        RESP=$($CURL -X PUT "$SESSION" -H "Content-Type: ${MIME_TYPE}" --data-binary "@${PATH_IN}")
        FILE_ID=$(echo "$RESP" | jq -r '.id // empty')
        [ -n "$FILE_ID" ] || { echo "❌ Upload failed"; echo "$RESP"; return 1; }
      fi
    fi
  fi

  # Sharing
  if [[ "$SHARING" != "none" && "$SKIPPED" = false ]]; then
    echo "🔓 Configuring sharing (mode: ${SHARING})..."
    local PERM_DATA=""
    case "$SHARING" in
      anyone)
        # Google only allows reader for type:anyone; let role input be ignored here.
        local allow; allow=$( [[ "$LINK_DISCOVERABLE" == "true" ]] && echo true || echo false )
        PERM_DATA=$(jq -nc --argjson afd "$allow" '{"role":"reader","type":"anyone","allowFileDiscovery":$afd}')
        ;;
      domain)
        if [ -z "$SHARING_DOMAIN" ]; then echo "❌ sharing_domain required for domain sharing"; return 1; fi
        PERM_DATA=$(jq -nc --arg role "$SHARING_ROLE" --arg domain "$SHARING_DOMAIN" \
          '{"role":$role,"type":"domain","domain":$domain}')
        ;;
      specific)
        if [ -z "$SHARING_EMAIL" ]; then echo "❌ sharing_email required for specific sharing"; return 1; fi
        PERM_DATA=$(jq -nc --arg role "$SHARING_ROLE" --arg email "$SHARING_EMAIL" \
          '{"role":$role,"type":"user","emailAddress":$email}')
        ;;
      *) echo "⚠️  Unknown sharing mode: ${SHARING}, skipping";;
    esac
    if [ -n "$PERM_DATA" ]; then
      local PR
      PR=$($CURL -X POST \
        "https://www.googleapis.com/drive/v3/files/${FILE_ID}/permissions?supportsAllDrives=true&sendNotificationEmail=false" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$PERM_DATA")
      if [[ "$(echo "$PR" | jq -r '.id // empty')" != "" ]]; then
        echo "✅ Sharing configured"
      else
        echo "⚠️  Sharing configuration may have failed"; echo "$PR"
      fi
    fi
  fi

  # Canonical links
  local INFO
  INFO=$($CURL -G "https://www.googleapis.com/drive/v3/files/${FILE_ID}" \
    --data-urlencode "fields=id,name,webViewLink,webContentLink" \
    --data-urlencode "supportsAllDrives=true" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}")
  local WEB_VIEW_LINK; WEB_VIEW_LINK=$(jq -r '.webViewLink // empty' <<<"$INFO")
  local DOWNLOAD_LINK; DOWNLOAD_LINK=$(jq -r '.webContentLink // empty' <<<"$INFO")
  local DIRECT_LINK; DIRECT_LINK="$DOWNLOAD_LINK" # canonical; avoid brittle confirm=t tricks

  echo ""
  echo "📋 Upload Summary:"
  echo "  File ID: ${FILE_ID}"
  echo "  Filename: ${FILE_NAME}"
  echo "  Updated: ${UPDATED}"
  echo "  Skipped: ${SKIPPED}"
  echo "  View Link: ${WEB_VIEW_LINK}"
  echo "  Download Link: ${DOWNLOAD_LINK}"
  echo ""

  # Set outputs (last processed file wins; compatible with single-file callers)
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "file_id=${FILE_ID}"
      echo "file_name=${FILE_NAME}"
      echo "web_view_link=${WEB_VIEW_LINK}"
      echo "download_link=${DOWNLOAD_LINK}"
      echo "direct_link=${DIRECT_LINK}"
      echo "updated=${UPDATED}"
      echo "skipped=${SKIPPED}"
    } >> "$GITHUB_OUTPUT"
  fi
}

# ---- main loop -------------------------------------------------------------
for f in "${files[@]}"; do
  upload_one "$f"
done

# Hygiene
unset ACCESS_TOKEN PRIVATE_KEY CREDENTIALS
echo "✅ Google Drive sync complete!"
