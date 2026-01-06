#!/bin/sh
# vim: set expandtab tabstop=2 softtabstop=2 shiftwidth=2 :

WRITE_OUT='__POORMAN_DELIM__%{json}__POORMAN_DELIM__%{header_json}'
POORMAN_RUN_ONLY=
trapped=
snapshot_idx=0
_check_deps() {
  set -- curl
  failed=
  for dep in "$@"; do
    if ! type "$dep" >/dev/null 2>&1; then
      failed=1
      echo "[ $dep ] is needed."
    fi
  done
  [ "${failed:-}" ] && exit 1
}
_check_only() {
  if [ -f "$0" ] && [ -r "$0" ]; then
    while IFS= read -r line; do
      case $line in
      Only\(\)*) ;;
      Only\ *)
        POORMAN_RUN_ONLY=1
        dont_run=1
        ;;
      esac
    done <"$0"
  fi
}
_check_deps
_check_only

# Genius quoting function by Koichi Nakashima
# Under License: Creative Commons Zero v1.0 Universal
# Source: https://github.com/ko1nksm/getoptions/blob/master/lib/getoptions_base.sh
quote() {
  q="$2'" r=""
  while [ "$q" ]; do r="$r${q%%\'*}'\''" && q=${q#*\'}; done
  q="'${r%????}'" && q=${q#\'\'} && q=${q%\'\'}
  eval "$1=\${q:-\"''\"}"
}

to_list() {
  list=
  for arg in "$@"; do
    quote quoted "$arg"
    list="$list $quoted"
  done
}

fetch() {
  _before_hook
  [ "${POORMAN_RUN_ONLY:-}" ] && [ "${dont_run:-}" ] && return
  request=$1 path=$2
  shift 2
  to_list "$@"
  eval "set -- ${list:-} ${global_opts:-} ${once_opts:-}"
  [ "${BASE_URL:-}" ] && BASE_URL="${BASE_URL%/}/"
  set -- curl -X "$request" --write-out "$WRITE_OUT" "$@" "${BASE_URL:-}${path#/}"
  if [ "${DRY_RUN:-}" ]; then 
    IFS=" $IFS"
    printf '%s\n\n' "$*"
    IFS=${IFS#?}
  else
    _after_hook "$("$@")"
  fi
}

GET() { fetch GET "$@"; }
POST() { fetch POST "$@"; }
PUT() { fetch PUT "$@"; }
PATCH() { fetch PATCH "$@"; }
DELETE() { fetch DELETE "$@"; }

Skip() { :; }
Only() {
  if [ "${POORMAN_RUN_ONLY:-}" ]; then
    dont_run=
    "$@"
    dont_run=1
  else
    "$@"
  fi
}
CurlOption() {
  once=
  case $1 in
  Once)
    once=1
    shift
    ;;
  esac
  for opt in "$@"; do
    quote quoted "$opt"
    if [ "${once:-}" ]; then
      once_opts="${once_opts:-} ${quoted:-}"
    else
      global_opts="${global_opts:-} ${quoted:-}"
    fi
  done
}

Snapshot() {
  if [ ! "${trapped:-}" ]; then
    trap _self_replace EXIT
    trapped=1
  fi
}

BeforeHook() { :; }
AfterHook() { :; }

_before_hook() {
  BeforeHook
}

_after_hook() {
  result=$1
  BODY=${result%%__POORMAN_DELIM__*}
  result=${result#*__POORMAN_DELIM__}
  META_JSON=${result%%__POORMAN_DELIM__*}
  result=${result#*__POORMAN_DELIM__}
  HEADER_JSON=$result # last one
  RESULT=$BODY
  AfterHook
  eval "snapshot_$snapshot_idx=\$RESULT"
  snapshot_idx=$((snapshot_idx + 1))
  once_opts=
}

_self_replace() {
  new_content=
  snapshot_idx=0
  while IFS= read -r line; do
    case $line in
    Snapshot)
      eval "result=\$snapshot_$snapshot_idx"
      new_content="$new_content
: <<'RESULT'
${result:-}
RESULT"
      snapshot_idx=$((snapshot_idx + 1))
      ;;
    *)
      new_content="$new_content
$line"
      ;;
    esac
  done <"$0"
  printf '%s' "$new_content" >"$0"
}

# AfterHook() {
#   # last_result=$(printf '%s' "$last_json" | jq '.http_code')
#   RESULT="$(jq --null-input --raw-output --argjson selected '[ "content-type", "date", "http_code", "method", "time_total", "size_download", "url_effective" ]' --argjson meta "$META_JSON" --argjson header "$HEADER_JSON" '
#   $meta + $header
#   | to_entries 
#   | map(select(.key | IN($selected[])))
#   | (map(.key | length) | max) as $max_len 
#   | .[] 
#   | .key + (" " * ($max_len - (.key | length) + 4)) + ([.value] | flatten | join(" "))
#   ')
# -------------------------
# $BODY"
# }
