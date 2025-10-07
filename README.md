# Sync Release to Google Drive

GitHub Action to upload files to Google Drive with automatic sharing and permission management.

## Features

- ✅ Upload files to Google Drive via Service Account
- ✅ Automatic file sharing (anyone/domain/specific email)
- ✅ Overwrite existing files
- ✅ Returns file ID, view link, and download link
- ✅ Pure shell implementation (no dependencies)
- ✅ Flexible permission management

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `filename` | Yes | - | File to upload (path relative to workflow root) |
| `credentials` | Yes | - | Base64-encoded Google Service Account credentials JSON |
| `folder_id` | Yes | - | Google Drive folder ID to upload to |
| `overwrite` | No | `true` | Overwrite existing files with same name |
| `sharing` | No | `anyone` | Sharing mode: `none`, `anyone`, `domain`, `specific` |
| `sharing_role` | No | `reader` | Permission role: `reader`, `writer`, `commenter` |
| `sharing_email` | No | - | Email address (required if `sharing: specific`) |
| `sharing_domain` | No | - | Domain (required if `sharing: domain`) |

## Outputs

| Output | Description |
|--------|-------------|
| `file_id` | Google Drive file ID |
| `file_name` | Uploaded filename |
| `web_view_link` | Google Drive web view link |
| `download_link` | Direct download link |
| `web_content_link` | Direct browser-viewable link |

## Setup

### 1. Create Google Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable **Google Drive API**
4. Create a **Service Account**
5. Generate and download JSON key

### 2. Prepare Credentials

```bash
# Base64 encode your service account JSON key
base64 -i service-account-key.json -o encoded-credentials.txt

# Or on Linux/Unix:
cat service-account-key.json | base64 > encoded-credentials.txt
```

### 3. Share Drive Folder

Share your Google Drive folder with the service account email (found in the JSON key):
- Email format: `your-service-account@your-project.iam.gserviceaccount.com`
- Give **Editor** permissions

### 4. Add GitHub Secrets

Add these secrets to your GitHub repository:

- `GOOGLE_DRIVE_CREDENTIALS_B64` - Base64-encoded service account credentials
- `GOOGLE_DRIVE_FOLDER_ID` - Google Drive folder ID (from folder URL)

## Usage Examples

### Basic Upload with Public Link Sharing

```yaml
- name: Upload to Google Drive
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: dist/my-plugin.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: anyone
    sharing_role: reader
```

### Upload Without Sharing (Private)

```yaml
- name: Upload to Google Drive (Private)
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: sensitive-data.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: none
```

### Share with Specific Email

```yaml
- name: Upload and share with team member
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: team-report.pdf
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: specific
    sharing_email: teammate@company.com
    sharing_role: writer
```

### Share with Organization Domain

```yaml
- name: Upload and share with company domain
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: internal-docs.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
    sharing: domain
    sharing_domain: company.com
    sharing_role: reader
```

### Use Outputs in Subsequent Steps

```yaml
- name: Upload to Google Drive
  id: drive_upload
  uses: code-atlantic/sync-release-to-google-drive@v1
  with:
    filename: release.zip
    credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
    folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}

- name: Send Slack notification with link
  run: |
    echo "File uploaded: ${{ steps.drive_upload.outputs.web_view_link }}"
    curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
      -d '{"text":"Download: ${{ steps.drive_upload.outputs.download_link }}"}'
```

### Complete Release Workflow

```yaml
name: Release to Google Drive

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
        run: |
          npm install
          npm run build
          zip -r release-${{ github.ref_name }}.zip dist/

      - name: Upload to Google Drive
        id: upload
        uses: code-atlantic/sync-release-to-google-drive@v1
        with:
          filename: release-${{ github.ref_name }}.zip
          credentials: ${{ secrets.GOOGLE_DRIVE_CREDENTIALS_B64 }}
          folder_id: ${{ secrets.GOOGLE_DRIVE_FOLDER_ID }}
          sharing: anyone
          sharing_role: reader

      - name: Notify team
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -H 'Content-Type: application/json' \
            -d '{
              "text": "Release ${{ github.ref_name }} available",
              "attachments": [{
                "fields": [
                  {"title": "File", "value": "${{ steps.upload.outputs.file_name }}"},
                  {"title": "View", "value": "<${{ steps.upload.outputs.web_view_link }}|Open in Drive>"},
                  {"title": "Download", "value": "<${{ steps.upload.outputs.download_link }}|Direct Download>"}
                ]
              }]
            }'
```

## Sharing Modes

### `anyone` (default)
- Anyone with the link can access
- Most common for public releases
- Safe for sharing in support tickets

### `none`
- File remains private
- Only service account has access
- Requires manual sharing later

### `domain`
- Share with entire Google Workspace domain
- Good for internal tools
- Requires `sharing_domain` parameter

### `specific`
- Share with specific email address
- Good for team collaboration
- Requires `sharing_email` parameter

## Permission Roles

| Role | Capabilities |
|------|-------------|
| `reader` | View and download only |
| `commenter` | View, download, and comment |
| `writer` | View, download, edit, and delete |

## Troubleshooting

### "Failed to get access token"
- Verify credentials are properly base64 encoded
- Check service account has Drive API enabled

### "Upload failed"
- Verify folder ID is correct
- Ensure service account has Editor access to folder
- Check file exists at specified path

### "Sharing configuration failed"
- Verify sharing parameters are correct
- For domain sharing, ensure Workspace domain is valid
- For specific sharing, ensure email address is valid

## License

MIT License - see LICENSE file for details

## Contributing

Contributions welcome! Please open an issue or PR.

## Support

For issues and questions, please open a GitHub issue in this repository.