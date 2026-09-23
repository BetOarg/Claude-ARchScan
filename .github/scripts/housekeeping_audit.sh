#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
failures=0
reviews=0

echo "== ARchScan Housekeeping Audit =="

echo "-- Tracked empty files --"
empty_found=0
while IFS= read -r -d '' file; do
  if [[ -f "$file" && ! -s "$file" ]]; then
    case "$file" in
      .gitkeep|.github/ISSUE_TEMPLATE/*|.github/PULL_REQUEST_TEMPLATE/*) ;;
      *) echo "REMOVE: empty tracked file: $file"; failures=$((failures + 1)); empty_found=1 ;;
    esac
  fi
done < <(git ls-files -z)
[[ "$empty_found" -eq 0 ]] && echo "OK: no tracked empty files."

echo "-- Temporary/backup artifacts --"
while IFS= read -r -d '' file; do
  case "$file" in
    *.bak|*.tmp|*.temp|*.old|*.orig|*.rej|*.swp|*.swo|*~)
      echo "REMOVE: temporary artifact: $file"; failures=$((failures + 1)) ;;
  esac
done < <(git ls-files -z)

echo "-- Generated/cache artifacts accidentally tracked --"
while IFS= read -r -d '' file; do
  case "$file" in
    .dart_tool/*|build/*|.gradle/*|android/.gradle/*|ios/Pods/*|ios/Flutter/ephemeral/*)
      echo "REMOVE: generated/cache artifact: $file"; failures=$((failures + 1)) ;;
  esac
done < <(git ls-files -z)

echo "-- Tracked files ignored by .gitignore --"
tracked_ignored="$(git ls-files -ci --exclude-standard)"
if [[ -n "$tracked_ignored" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    echo "REVIEW: tracked file is ignored by .gitignore: $file"
    reviews=$((reviews + 1))
  done <<< "$tracked_ignored"
else
  echo "OK: no tracked files are unexpectedly ignored."
fi

echo "-- Temporary workflow/script names --"
while IFS= read -r -d '' file; do
  base="$(basename "$file")"
  case "$base" in
    *temp*|*temporary*|*scratch*|*debug*)
      echo "REVIEW: development-style workflow/script name: $file"; reviews=$((reviews + 1)) ;;
  esac
done < <(git ls-files -z '.github/*')

echo "-- Suspicious source markers --"
marker_matches="$(git grep -n -I -E '(^|[[:space:]])(TODO|FIXME|XXX|HACK)([[:space:]:]|$)' -- '*.dart' '*.swift' '*.kt' '*.java' 2>/dev/null || true)"
if [[ -n "$marker_matches" ]]; then
  printf '%s\n' "$marker_matches"
  reviews=$((reviews + 1))
else
  echo "OK: no TODO/FIXME/XXX/HACK markers in tracked source."
fi

echo "-- Candidate orphan Dart files (review only) --"
orphan_count=0
while IFS= read -r -d '' file; do
  case "$file" in
    packages/*/lib/*.dart)
      base="$(basename "$file" .dart)"
      [[ "$base" == "main" || "$base" == "app" ]] && continue
      refs="$(git grep -l -I -E "['\"][^'\"]*/?$base\\.dart['\"]" -- ':!'"$file" 2>/dev/null || true)"
      if [[ -z "$refs" ]]; then
        echo "REVIEW: no obvious direct URI reference found for $file"
        reviews=$((reviews + 1))
        orphan_count=$((orphan_count + 1))
      fi
      ;;
  esac
done < <(git ls-files -z)
[[ "$orphan_count" -eq 0 ]] && echo "OK: no obvious unreferenced lib/*.dart candidates."

echo "Housekeeping result: failures=$failures reviews=$reviews"
if (( failures > 0 )); then
  echo "Housekeeping gate: FAIL"
  exit 1
fi
echo "Housekeeping gate: PASS"
echo "Review findings are advisory; validate before deletion."
