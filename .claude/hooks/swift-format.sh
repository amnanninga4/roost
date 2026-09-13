#!/usr/bin/env bash
# PostToolUse hook: format and lint a Swift file right after Claude writes it.
# Reads the tool call JSON on stdin. Never blocks the edit (always exits 0).
f=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
case "$f" in
  *.swift)
    if command -v swiftformat >/dev/null 2>&1; then
      swiftformat --quiet "$f" >/dev/null 2>&1
    fi
    if command -v swiftlint >/dev/null 2>&1; then
      swiftlint lint --quiet "$f" 2>/dev/null | head -20
    fi
    ;;
esac
exit 0
