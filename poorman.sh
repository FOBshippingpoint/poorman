#!/bin/sh
# vim: set expandtab tabstop=2 softtabstop=2 shiftwidth=2 :

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

fetch() {
  _before_hook "$@"
  [ "${POORMAN_RUN_ONLY:-}" ] && [ "${dont_run:-}" ] && return
  request=$1 path=$2
  shift 2
  if [ "${global_opts:-}" ] || [ "${once_opts:-}" ]; then
    stat='set --'
    for arg in "$@"; do
      quote quoted "$arg"
      # shellcheck disable=SC2154
      stat="$stat $quoted"
    done
    stat="$stat ${global_opts:-} ${once_opts:-}"
    eval "$stat"
  fi
  last_result=$(curl --request "$request" "$@" "${BASE_URL%/}/${path#/}")
  eval "snapshot_$snapshot_idx=\$last_result"
  snapshot_idx=$((snapshot_idx + 1))
  _after_hook "$last_result"
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
  [ "${trapped:-}" ] || {
    trap _self_replace EXIT
    trapped=1
  }
}

BeforeHook() { :; }
AfterHook() { :; }
_before_hook() {
  [ "${BASE_URL:-}" ] || {
    echo '[ BASE_URL ] not set'
    exit 1
  }
  BeforeHook "$@"
}
_after_hook() {
  AfterHook "$@"
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
