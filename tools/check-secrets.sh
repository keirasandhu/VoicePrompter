#!/usr/bin/env bash
# Blocks real secrets from being committed or pushed.
#   tools/check-secrets.sh                 scan what is staged
#   tools/check-secrets.sh <from> <to>     scan the commits in a range (used by the pre-push hook)
#
# Only the credential-shaped value itself can mark it as a fake (for example
# sk_live_fakefakefake...). The file name, the rest of the line and comments
# such as "# example" are never considered, so they cannot wave a real key
# through.
set -euo pipefail

if [ $# -eq 2 ]; then
  diff=$(git diff "$1" "$2" --unified=0 --no-color)
else
  diff=$(git diff --cached --unified=0 --no-color)
fi

printf '%s\n' "$diff" | python3 -c '
import re, sys

PATTERN = re.compile(
    r"sk_live_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{24,}"
    r"|xox[bpae]-[0-9]{6,}-[A-Za-z0-9-]{10,}|EAA[A-Za-z0-9]{60,}|pit-[a-f0-9]{8}-[a-f0-9]{4}-"
    r"|shpat_[a-f0-9]{32}|shpss_[a-f0-9]{32}|pk_[a-f0-9]{32}|AKIA[0-9A-Z]{16}"
    r"|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|sk-ant-[A-Za-z0-9_-]{30,}"
    r"|sk-proj-[A-Za-z0-9_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----"
)
FAKE_VALUE = re.compile(r"never|fake|example|dummy|placeholder|redacted|xxxx", re.IGNORECASE)
DATA_URI = re.compile(r"data:[a-z]+/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]+")

hits = []
current = "?"
for line in sys.stdin.read().splitlines():
    if line.startswith("+++ "):
        current = line[6:] if line.startswith("+++ b/") else line[4:]
        continue
    if not line.startswith("+") or line.startswith("+++"):
        continue
    content = DATA_URI.sub("", line[1:])  # embedded images are not credentials
    for match in PATTERN.finditer(content):
        if not FAKE_VALUE.search(match.group(0)):
            redacted = PATTERN.sub("[SECRET]", content)[:200]
            hits.append(current + ": " + redacted)
            break
if hits:
    print("BLOCKED: this looks like a real secret. Remove it and keep it in the server env file instead.", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    sys.exit(1)
'
