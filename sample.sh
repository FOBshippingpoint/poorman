#!/bin/sh

. poorman.sh

# /// configurations ///

BASE_URL=https://jsonplaceholder.typicode.com

# /// curl options ///

# Add global curl option
CurlOption --url-query "postId=10"
CurlOption --verbose

# /// hooks ///

AfterHook() {
  printf '%s' "$1" | jq
}

# /// requests ///

# This option only effect next request
CurlOption Once --write-out "%{header_json}"

# Get post by id
postId=10
GET /comments?postId=$postId

# This line will replaced with the response body of previous request
Snapshot

# Create new post
POST /posts --json "$(cat <<'PAYLOAD'
{
  "title": "poorman",
  "body": "A very limited alternative to postman",
  "userId": 1
}
PAYLOAD
)"

Snapshot

# Get album's photo
album=3
Skip GET /albums/$album/photos

# Alter user name
userId=1
PATCH /users/$userId --json '{"name": "John Doe"}'

Snapshot
