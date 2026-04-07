#!/bin/sh

PROMPT="Take a look at the git logs and figure out a good version number. Please refer to the following for the output format. Don't use markdown-syntax. Just plaintext\
  \ Suggested: <version number>
  \ Reason: <reason for the suggested version number>
  "
AGENT="claude"

echo "Suggesting a version number using $AGENT..."

# Check agent is installed
if ! command -v "$AGENT" >/dev/null 2>&1; then
  echo "error: $AGENT is not installed. Please install it first." >&2
  exit 1
fi

$AGENT -p "$PROMPT"
