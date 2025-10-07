# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
