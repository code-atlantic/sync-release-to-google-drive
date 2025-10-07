# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-10-07

### 🎉 Production-Ready Release

Complete rewrite with robust error handling, security hardening, and performance optimization.

### Added
- **Multi-file support**: Upload multiple files via glob patterns (e.g., `dist/*.zip`) or newline-separated lists
- **MD5 deduplication**: Automatically skip uploads when file content is identical (MD5 match)
- **Update-in-place**: Preserve permissions and links by updating existing files instead of delete+create
- **Link discoverability control**: New `link_discoverable` input for "anyone with link" vs searchable files
- **Enhanced outputs**: Added `updated` and `skipped` boolean outputs for workflow logic
- **Dependency validation**: Fail-fast checks for required tools (jq, curl, openssl, file)
- **Folder preflight check**: Validate folder exists and is accessible before upload
- **Security hardening**:
  - Token masking with `::add-mask::` to prevent leaks in logs
  - All JSON built with jq (no injection risks)
  - Proper credential cleanup with `unset` at script end
- **Retry logic**: Automatic retries (5x) with exponential backoff for transient failures
- **Timeout protection**: 300s max per request to prevent hanging jobs

### Changed
- **BREAKING**: Default `sharing` changed from `anyone` to `none` (principle of least privilege)
- **BREAKING**: `direct_link` now returns canonical Drive URL instead of brittle confirm bypass
- **Improved search**: Query by parent folder only, then filter locally (no quote injection)
- **Better JWT signing**: Use `printf` instead of `echo -n` for portability
- **Enhanced MIME detection**: Fallback to `application/octet-stream` on failure
- **Canonical link fetching**: Get `webViewLink` and `webContentLink` directly from API
- **Resumable upload headers**: Include `X-Upload-Content-Type` and `X-Upload-Content-Length`
- **Better duplicate handling**: Delete all duplicates or use existing based on overwrite setting

### Fixed
- **Quote injection vulnerability**: Filenames with special characters no longer break searches
- **Race conditions**: Update-in-place prevents permission loss during overwrites
- **Session URL extraction**: More robust Location header parsing
- **curl error handling**: Now uses `-fsS` to fail on HTTP errors properly
- **Remote MD5 handling**: Proper empty string handling when MD5 unavailable

### Security
- ✅ No JSON injection vulnerabilities (all via jq)
- ✅ Proper token masking in logs
- ✅ Credential cleanup on exit
- ✅ Safe glob expansion with proper nullglob handling
- ✅ Input validation for all parameters

### Performance
- 🚀 MD5 skip saves bandwidth on unchanged files
- 🚀 Update-in-place preserves links and permissions
- 🚀 Batch permission operations
- 🚀 Efficient multi-file processing

## [0.2.0] - 2025-01-07

### Added
- Added `direct_link` output with enhanced download URL format
- Support for shared drives with `supportsAllDrives=true` parameter
- Enhanced permission management for shared drive compatibility
- Improved error handling for shared drive restrictions

### Changed
- Updated download URL generation with multiple format options
- Simplified permission settings for better compatibility
- Enhanced sharing configuration with `sendNotificationEmail=false`
- Improved URL formats for better download reliability

### Fixed
- Fixed shared drive upload issues by adding proper API parameters
- Fixed permission setting failures in shared drive environments
- Fixed GitHub Actions output handling for local testing environments

## [0.1.0] - 2025-01-07

### Added
- Initial release of Google Drive sync action
- Support for uploading files to Google Drive folders
- Automatic file sharing configuration (anyone, domain, specific)
- Multiple output formats (view link, download link, web content link)
- Overwrite protection for existing files
- Service account authentication via JWT
- Resumable upload support for reliability
