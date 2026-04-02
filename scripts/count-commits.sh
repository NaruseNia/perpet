#!/bin/bash
# Count commits excluding chore:, version:, and ! prefixed messages

count=$(git log --oneline --format="%s" | grep -vcE '^(chore:|version:|!)')
echo "$count"
