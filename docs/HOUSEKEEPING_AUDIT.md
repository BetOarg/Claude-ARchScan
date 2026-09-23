# ARchScan Housekeeping Audit

This is a pre-release repository hygiene gate.

## Automatic blockers

The CI gate fails for unambiguous repository residue:

- tracked empty files, except intentional placeholders;
- temporary/backup artifacts such as .bak, .tmp, .old, .orig and swap files;
- tracked build/cache/generated artifacts that belong outside Git.

## Advisory findings

The audit reports but does not delete:

- tracked files ignored by .gitignore;
- temporary-looking workflow/script names;
- TODO/FIXME/XXX/HACK markers;
- Dart files with no obvious direct URI reference.

These require context validation because Flutter/Dart code can be reached through generated code, package exports, native integration, registration tables or route strings.

## Generated files

Required Isar and localization generated sources are not classified as dead code by this audit; their existing build/CI rules remain authoritative.

## Deletion policy

The audit never deletes files. REMOVE findings are corrected in a reviewed commit/PR. REVIEW findings must be validated before deletion.

Run locally with:

```bash
bash .github/scripts/housekeeping_audit.sh
```
