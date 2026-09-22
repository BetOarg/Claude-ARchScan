# Dependency audit — beta release

Date: 2026-09-22

## Current policy

ARchScan is in pre-beta launch stabilization. Dependency changes are treated as release-risk changes: a newer package is not adopted solely because it exists.

The repository CI remains the authoritative compatibility check for any dependency update.

## Findings

| Package | Current constraint | Current latest observed | Decision |
|---|---:|---:|---|
| intl | 0.20.3 | 0.20.3 | Keep |
| camera | ^0.10.5+9 | 0.12.1 | Defer |
| sensors_plus | ^3.0.3 | 7.1.0 | Defer |
| vector_math | ^2.1.4 | 2.4.3 | Defer |
| provider | ^6.1.2 | 6.1.5+1 | Defer |
| shared_preferences | 2.3.5 | 2.5.5 | Defer |
| file_picker | ^8.0.0 | 13.1.0 | Defer |
| printing | ^5.13.1 | 5.15.1 | Defer |
| share_plus | ^10.0.0 | 13.3.0 | Defer |
| path_provider | ^2.1.2 | 2.1.6 | Defer |
| flutter_svg | ^2.0.10+1 | 2.3.0 | Defer |
| image | ^4.2.0 | 4.10.1 | Defer |
| permission_handler | ^11.3.1 | 13.0.2 | Defer |
| flutter_lints | ^3.0.0 | 6.0.0 | Defer |
| build_runner | ^2.4.8 | 2.16.1 | Defer |

## Release decision

No runtime dependency is upgraded in this PR.

Several available releases are major/minor jumps or introduce newer SDK/native build requirements. In particular, current package metadata shows newer requirements for packages such as `sensors_plus`, while `camera` 0.12.1 requires Flutter 3.44/Dart 3.12. These changes should be validated independently rather than mixed into the beta stabilization work.

`intl 0.20.3` remains pinned because it is already the current stable release.

## Follow-up

After beta stabilization, upgrade dependencies in small, isolated PRs. Each PR must pass:

- Dart formatting
- core/app analysis and tests
- Android release bundle build
- iOS simulator build
- store-readiness checks
- security audit
- physical regression tests for scanner modes and exports when native/plugin behavior changes

## Temporary CI cleanup

The temporary text-audit formatter workflow is removed in this PR. It was an emergency branch-only formatting helper and is no longer needed after PR #39.
