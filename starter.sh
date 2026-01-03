#!/bin/sh

# Load the library
. poorman.sh

# /// configurations ///
BASE_URL=https://jsonplaceholder.typicode.com

# /// curl options ///
CurlOption --location

# /// hooks ///
# Optional: Format JSON output if jq is installed
AfterHook() {
  printf '%s' "$1" | jq
}

# /// requests ///

# 1. Simple GET request
GET /todos/1
Snapshot

# 2. POST request with JSON body
POST /posts --json "$(cat <<'JSON'
{
  "title": "starter",
  "body": "sourced from poorman.sh",
  "userId": 1
}
JSON
)"

Snapshot
