# Changelog

## [1.1.1] — 2026-07-12

### Security
- Redact proxy, PAC, credential, token, and bypass-list values in all platform diagnostics.
- Add a non-mutating batch dry-run path and regression tests that fail on secret disclosure.

### Changed
- Exercise the Windows batch entry point and simulated macOS proxy output in CI.

## [1.1.0] — 2026-07-11

### Changed
- Removed shell `eval` usage and now pass process and network-service arguments safely.
- Added strict option validation, proxy credential redaction, and clearer parent-shell guidance.
- PowerShell mutations now fail loudly and support `-WhatIf` in addition to `-DryRun`.
- Added cross-platform syntax and dry-run CI.

### Security
- Documentation now recommends downloading and reviewing scripts instead of piping remote content directly into a shell.

## [1.0.0] — 2026-07-02

### Added
- Initial Windows, macOS, and Linux proxy repair scripts.
