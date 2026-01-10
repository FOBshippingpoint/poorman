#!/bin/sh

. ./poorman.sh

# /// configurations ///

# Base URL of each requests. Trailing slash is optional.
BASE_URL=https://jsonplaceholder.typicode.com
# Set to 1 if you only want to run requests starts with "Only"
ONLY=
# Set to 1 if you want to see the actual curl commands
DRY_RUN=

# /// curl options ///

# Add global curl option
CurlOptionGlobal --location

# /// hooks ///

AfterHook() {
  # Prints response body for every request
  printf '%s' "$BODY"
}

# /// requests ///

# Add option that only affect next request
CurlOptionOnce --user admin:password

# Get post by id
commentId=1
GET /comments/$commentId
# This line will replaced with the response body of previous request
Snapshot
# Like this:
# : <<'SNAPSHOT'
# http_code        200
# method           GET
# size_download    268
# time_total       0.411915
# url_effective    https://jsonplaceholder.typicode.com/comments/1
# date             Sat, 10 Jan 2026 10:23:10 GMT
# content-type     application/json; charset=utf-8
# -------------------------
# {
#   "postId": 1,
#   "id": 1,
#   "name": "id labore ex et quam laborum",
#   "email": "Eliseo@gardner.biz",
#   "body": "laudantium enim quasi est quidem magnam voluptate ipsam eos\ntempora quo necessitatibus\ndolor quam autem quasi\nreiciendis et nam sapiente accusantium"
# }
# SNAPSHOT

# Create new post
POST /posts --json "$(
  cat <<'PAYLOAD'
{
  "title": "poorman",
  "body": "A very limited alternative to postman",
  "userId": 1
}
PAYLOAD
)"
Snapshot

# [SKIP] Get album's photo
album=3
Skip GET /albums/$album/photos

# Alter user name
userId=1
PATCH /users/$userId --json '{"name": "John Doe"}'
Snapshot
