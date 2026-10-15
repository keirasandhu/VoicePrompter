#!/bin/zsh -l
set -e
cd "${0:A:h}"
if ! command -v node >/dev/null 2>&1; then
  for candidate in "$HOME"/.nvm/versions/node/*/bin/node(N); do
    export PATH="${candidate:h}:$PATH"
  done
fi
if ! command -v npm >/dev/null 2>&1; then
  print "Node.js/npm is required. Install Node.js, then reopen this launcher."
  read "?Press Return to close."
  exit 1
fi
if [[ ! -d node_modules ]]; then npm ci; fi
if [[ ! -f dist/app/index.html ]]; then npm run build; fi
print "VoicePrompter: http://127.0.0.1:4318/app/"
print "Keep this window open while using it. Press Control-C to stop."
npm run preview -- --host 127.0.0.1 --port 4318 --strictPort &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM
for attempt in {1..50}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"
    exit $?
  fi
  if curl --fail --silent "http://127.0.0.1:4318/app/" >/dev/null; then
    open "http://127.0.0.1:4318/app/"
    wait "$server_pid"
    exit $?
  fi
  sleep 0.1
done
print "The app did not start. See the error above."
exit 1
