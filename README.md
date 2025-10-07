# 📤 Sync Release to Google Drive

**Production-ready GitHub Action for uploading files to Google Drive with intelligent deduplication, update-in-place, and comprehensive sharing controls.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](CHANGELOG.md)

## ✨ Features

- 🚀 **Multi-file support** - Upload via glob patterns or newline-separated lists
- 🔄 **MD5 deduplication** - Skip uploads when content unchanged
- ♻️ **Update-in-place** - Preserve permissions and links on overwrite
- 🔒 **Security hardened** - Token masking, jq-based JSON, credential cleanup
- 🌐 **Flexible sharing** - None, anyone, domain, or specific user/email
- 📊 **Rich outputs** - File IDs, links, update/skip status
- 🛡️ **Robust error handling** - Retries, timeouts, preflight checks
- 📦 **Canonical links** - Direct from Drive API (no brittle URL hacks)

## 🚀 Quick Start

### Basic Upload

```yaml
- name: Upload to Google Drive
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: my-plugin.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
```

### Upload with Public Link

```yaml
- name: Upload and share publicly
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: release-package.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: anyone
    link_discoverable: false  # Link-only, not searchable
```

### Multi-file Upload with Glob

```yaml
- name: Upload all release artifacts
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: 'dist/*.zip'
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    overwrite: true
```

## 📋 Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `filename` | ✅ Yes | - | File(s) to upload. Accepts globs (e.g., `dist/*.zip`) or newline-separated list |
| `credentials` | ✅ Yes | - | Base64-encoded Google Service Account credentials JSON |
| `folder_id` | ✅ Yes | - | Google Drive folder ID to upload to |
| `overwrite` | No | `true` | Overwrite existing files with same name |
| `sharing` | No | `none` | Sharing mode: `none`, `anyone`, `domain`, `specific` |
| `sharing_role` | No | `reader` | Permission role: `reader`, `writer`, `commenter` |
| `sharing_email` | No | - | Email address for `specific` sharing mode |
| `sharing_domain` | No | - | Domain for `domain` sharing mode |
| `link_discoverable` | No | `false` | For `sharing=anyone`: allow file discovery in search |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `file_id` | Google Drive file ID |
| `file_name` | Uploaded filename |
| `web_view_link` | Google Drive web view link |
| `download_link` | Standard download link (Drive webContentLink) |
| `direct_link` | Direct download link (same as download_link) |
| `updated` | Whether file was updated (`true`) vs created (`false`) |
| `skipped` | Whether upload was skipped due to identical content |

## 🔧 Setup

### 1. Create Google Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable **Google Drive API**
4. Create **Service Account** credentials
5. Download JSON key file

### 2. Configure Google Drive

1. Create a folder in Google Drive
2. Right-click → Share → Add the service account email
3. Grant **Editor** permissions
4. Copy the folder ID from URL: `https://drive.google.com/drive/folders/FOLDER_ID_HERE`

### 3. Add GitHub Secrets

Encode credentials and add to repository secrets:

```bash
# Encode service account JSON to base64
cat service-account.json | base64 | pbcopy  # macOS
cat service-account.json | base64 -w 0      # Linux

# Add to GitHub Secrets:
# - GOOGLE_DRIVE_CREDENTIALS_B64 (paste base64 string)
# - GOOGLE_DRIVE_FOLDER_ID (paste folder ID)
```

## 📚 Usage Examples

### Release Workflow with Drive Upload

```yaml
name: Release Plugin

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Build release package
        run: npm run build:production
      
      - name: Upload to Google Drive
        id: drive_upload
        uses: code-atlantic/sync-release-to-google-drive@v1
        with:
          filename: dist/my-plugin_${{ github.ref_name }}.zip
          credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
          folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
          sharing: anyone
      
      - name: Use download link
        run: |
          echo "Download: ${{ steps.drive_upload.outputs.download_link }}"
          echo "View: ${{ steps.drive_upload.outputs.web_view_link }}"
```

### Conditional Upload on Content Change

```yaml
- name: Upload only if changed
  id: upload
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: my-file.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}

- name: Notify only if updated
  if: steps.upload.outputs.updated == 'true'
  run: echo "File was updated!"

- name: Skip notification if identical
  if: steps.upload.outputs.skipped == 'true'
  run: echo "File unchanged, skipped upload"
```

### Domain Sharing

```yaml
- name: Share with organization
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: internal-release.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: domain
    sharing_domain: yourcompany.com
    sharing_role: reader
```

### Specific User Sharing

```yaml
- name: Share with specific user
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: confidential.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: specific
    sharing_email: user@example.com
    sharing_role: writer
```

## 🔒 Security

### Hardened Implementation

✅ **Token Masking** - Access tokens masked in logs with `::add-mask::`  
✅ **jq-based JSON** - All JSON built with jq (no injection vulnerabilities)  
✅ **Credential Cleanup** - Sensitive vars unset on script exit  
✅ **Safe Glob Expansion** - Proper nullglob/dotglob handling  
✅ **Input Validation** - All parameters validated before use  
✅ **Quote-safe Search** - Parent-based search with local filtering  

### Best Practices

1. **Least Privilege**: Default `sharing: none` - opt-in for public links
2. **Service Account Scoping**: Limit Drive API scope to specific folders
3. **Secret Rotation**: Regularly rotate service account keys
4. **Audit Logs**: Monitor Drive activity logs for anomalies

## 🚀 Performance

### Optimizations

- **MD5 Deduplication**: Skip uploads when content identical (saves bandwidth)
- **Update-in-place**: Preserve permissions/links vs delete+create
- **Retry Logic**: 5 retries with exponential backoff for transient failures
- **Timeout Protection**: 300s max per request prevents hanging
- **Batch Operations**: Efficient multi-file processing

### Benchmarks

- **Unchanged file**: ~2s (MD5 check, skip upload)
- **New file upload**: ~5-10s (depending on size)
- **Update existing**: ~6-12s (resumable session + update)

## 🐛 Troubleshooting

### Common Issues

**❌ "Invalid credentials format"**
- Ensure credentials are base64-encoded correctly
- Verify JSON structure with `echo $CREDS | base64 -d | jq .`

**❌ "folder_id is not a folder or not accessible"**
- Verify folder ID is correct
- Ensure service account has Editor permissions on folder

**❌ "No files matched: dist/*.zip"**
- Check glob pattern matches files in workspace
- Verify files exist before upload step

**❌ "Failed to get access token"**
- Check service account key is valid
- Ensure Drive API is enabled in project

### Debug Mode

Enable debug output:

```yaml
- name: Upload with debug
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: my-file.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
  env:
    ACTIONS_STEP_DEBUG: true
```

## 📊 Workflow Integration Examples

### Slack Notification with Download Link

```yaml
- name: Upload to Drive
  id: drive
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: release.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: anyone

- name: Notify Slack
  run: |
    curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
      -H 'Content-Type: application/json' \
      -d '{
        "text": "🚀 Release ${{ github.ref_name }} ready!",
        "attachments": [{
          "color": "good",
          "fields": [
            {"title": "Download", "value": "${{ steps.drive.outputs.download_link }}"},
            {"title": "View", "value": "${{ steps.drive.outputs.web_view_link }}"}
          ]
        }]
      }'
```

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing`)
5. Open Pull Request

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Credits

Developed by [Code Atlantic](https://code-atlantic.com) for the WordPress plugin release ecosystem.

Based on Google Drive API best practices and community feedback.

---

**⭐ If this action helped you, consider starring the repo!**
