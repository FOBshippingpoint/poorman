#!/bin/sh
# vim: set expandtab tabstop=2 softtabstop=2 shiftwidth=2 :

# @name        Poorman
# @description A very limited alternative to Postman, powered by curl and POSIX shell.
# @version     0.9
# @author      CC Lan
# @date        2026-11-10

[ "${_POORMAN_LOADED:-}" ] && return 0 2>/dev/null
_POORMAN_LOADED=1

POORMAN_VERSION='0.9'
POORMAN_DELIM='__POORMAN_DELIM__'
WRITE_OUT="$POORMAN_DELIM%{json}$POORMAN_DELIM%{header_json}"
_trapped=
_req_id=0
_skip=

# Prints message to stderr
#
# $@ {any}? - word separated with a whitespace.
msg() {
  IFS=" $IFS"
  set -- '%s\n' "${*:-}"
  IFS=${IFS#?}
  # shellcheck disable=SC2059
  printf "$@"
}

# Exit with message and code
#
# $1 {any}? message
# $2 {int}? exit_code - default to 1
die() {
  [ "${1:-}" ] && msg "$1"
  exit "${2:-1}"
}

usage() {
  cat <<'USAGE'
Poorman - a very limited alternative to Postman, powered by curl and POSIX shell.

Full doc see: https://github.com/FOBshippingpoint/poorman 

Usage:
  . ./poorman.sh
  ./poorman.sh [options] [script_file]
  cat script_file | ./poorman.sh

Options:
  -h, --help            Print this help
  -v, --version         Print version

Config:
  BASE_URL=https://example.com
  DRY_RUN=1             Print curl commands instead of running requests
  ONLY=1                Run only requests wrapped by Only
  OVERWRITE_SNAPSHOT=1  Overwrite existing Snapshot blocks on exit

Requests:
  GET endpoint [curl_options...]
  POST endpoint [curl_options...]
  PUT endpoint [curl_options...]
  PATCH endpoint [curl_options...]
  DELETE endpoint [curl_options...]
  HEAD endpoint [curl_options...]
  OPTIONS endpoint [curl_options...]
  Request METHOD endpoint [curl_options...]

Modifiers:
  CurlOptionGlobal [curl_options...]  Add curl options for subsequent requests
  CurlOptionGlobalReset               Clear all global curl options
  CurlOptionOnce [curl_options...]    Add curl options for the next request only
  Skip request...                     Skip one request
  Only request...                     Run request only when ONLY=1
  Snapshot                            Replace/update itself with the latest snapshot on exit

Helpers:
  BodyJq [jq_options...] filter       Query latest response BODY with jq
  HeaderJq [jq_options...] filter     Query latest response HEADER_JSON with jq

Hooks:
  BeforeHook            Override to run before each enabled request
  AfterHook             Override to run after each enabled request

Examples Script:
  # example.sh
  . ./poorman.sh
  BASE_URL=https://jsonplaceholder.typicode.com
  CurlOptionGlobal --location
  GET /posts/1
  Snapshot

  DRY_RUN=1 GET /users/1 --header 'Accept: application/json'
USAGE
}

# Check dependencies
# Will set "_has_<dep>" to 1 if satisfied, or empty if not.
#
# <<'EXAMPLE'
# _check_deps curl=required jq=optional
# # _has_curl=1 and _has_jq=1
# EXAMPLE
# 
# $@ {str}? dep_description - In dep=[optional|required] format
# @return 0 - if all required dependencies are satisfied.
_check_deps() {
  _failed=
  for _arg in "$@"; do
    _dep=${_arg%=*}
    _req=${_arg#*=}
    if type "$_dep" >/dev/null 2>&1; then
      eval "_has_$_dep=1"
    else
      unset "_has_$_dep"
      case $_req in
        required)
          _failed=1
          msg "[ $_dep ] is required."
        ;;
      esac
    fi
  done
  [ "${_failed:-}" ] && die
  return 0
}
_check_deps 'curl=required' 'jq=optional'

# Genius quoting function by Koichi Nakashima
# Under License: Creative Commons Zero v1.0 Universal
#
# <<'EXAMPLE'
# quote _quoted '@#$%!@"~''\''
# echo "$_quoted"
# '@#$%!@"~'\'
# EXAMPLE
#
# $1 {str} varname  - variable name to set
# $2 {str} to_quote - string to quote
# @see https://github.com/ko1nksm/getoptions/blob/master/lib/getoptions_base.sh
quote() {
  _q="$2'" _r=""
  while [ "$_q" ]; do _r="$_r${_q%%\'*}'\''" && _q=${_q#*\'}; done
  _q="'${_r%????}'" && _q=${_q#\'\'} && _q=${_q%\'\'}
  eval "$1=\${_q:-\"''\"}"
}

# Save args as string to variable $_list
#
# @set {str} _list - quoted string for eval "set -- $_list"
to_list() {
  _list=
  for _arg in "$@"; do
    quote _quoted "$_arg"
    # shellcheck disable=SC2154
    _list="$_list $_quoted"
  done
}

# Safely quote complex arguments into list
#
# @set {str} _list - quoted string for eval "set -- $_list"
to_list_quote_complex() {
  _list=
  for _w in "$@"; do
    case $_w in
      *[!a-zA-Z0-9_-]*)
        quote _quoted "$_w"
        _list="$_list $_quoted"
        ;;
      *)
        _list="$_list $_w"
        ;;
    esac
  done
}

# Send curl request
#
# $1 {str} request - HTTP request method
# $2 {str} path - path or full URL. e.g., /users/1 or https://example.com/users/1
# @need {1|any} ONLY - is current script run in ONLY mode?
# @need {1|any} _only - is current request mark as "Only"
# @need {str}? BASE_URL - base URL of the request
# @need {str} WRITE_OUT - curl write out
# @need {1|any} DRY_RUN - is current script run in DRY_RUN mode? Prints curl commands if DRY_RUN=1
# @internal
_fetch() {
  SNAPSHOT=
  if [ "${ONLY:-}" = 1 ] && [ ! "${_only:-}" ]; then
    _once_opts=
    return
  fi
  if [ "${_skip:-}" ]; then
    _once_opts=
    return
  fi
  _before_hook
  _request=$1 _path=$2
  shift 2
  to_list "$@"
  eval "set -- ${_list:-} ${_global_opts:-} ${_once_opts:-}"
  _once_opts=
  case $_path in
    http://* | https://*)
      _url=$_path
      ;;
    *)
      [ "${BASE_URL:-}" ] && BASE_URL="${BASE_URL%/}/"
      _url="${BASE_URL:-}${_path#/}"
      ;;
  esac
  set -- curl -X "$_request" --write-out "$WRITE_OUT" "$@" "$_url"
  if [ "${DRY_RUN:-}" = 1 ]; then
    to_list_quote_complex "$@"
    printf '%s\n' "${_list#?}"
  else
    _after_hook "$("$@")"
  fi
}

Request() {
  [ $# -ge 2 ] || die "[ Request ${*:-} ] is invalid, expecting Request <METHOD> <endpoint> [curl_options...]"
  _fetch "$@"
}
GET() { _fetch GET "$@"; }
POST() { _fetch POST "$@"; }
PUT() { _fetch PUT "$@"; }
PATCH() { _fetch PATCH "$@"; }
DELETE() { _fetch DELETE "$@"; }
HEAD() { _fetch HEAD "$@"; }
OPTIONS() { _fetch OPTIONS "$@"; }

# Skip the request
#
# $@ {any} request_command - the request command starts with GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request
Skip() { 
  case ${1:-} in
    GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request|Only) ;;
    *) die "[ Skip ${1:-} ... ] is invalid, expecting GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request";;
  esac
  _skip=1
  "$@"
  _status=$?
  _skip=
  return "$_status"
}
# Only run the request
#
# $@ {any} request_command - the request command starts with GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request
# @need {1|any} ONLY - Only works when $ONLY = 1
Only() {
  case ${1:-} in
    GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request|Skip) ;;
    *) die "[ Only ${1:-} ... ] is invalid, expecting GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request";;
  esac
  if [ "${ONLY:-}" = 1 ]; then
    _only=1
    "$@"
    _status=$?
    _only=
    return "$_status"
  else
    "$@"
  fi
}

# Add curl options for subsequent requests
#
# $@ {any} curl_options - options passed to curl as is
CurlOptionGlobal() {
  for _opt in "$@"; do
    quote _quoted "$_opt"
    _global_opts="${_global_opts:-} ${_quoted:-}"
  done
}
# Clear all global curl options
CurlOptionGlobalReset() {
  _global_opts=
}
# Add curl options for the next request
#
# $@ {any} curl_options - options passed to curl as is
CurlOptionOnce() {
  for _opt in "$@"; do
    quote _quoted "$_opt"
    _once_opts="${_once_opts:-} ${_quoted:-}"
  done
}

# Query latest response BODY with jq
#
# $@ {any} jq_args - arguments passed to jq
BodyJq() {
  [ "${_has_jq:-}" ] || die "[ jq ] is required."
  jq "$@" <<EOF
${BODY:-}
EOF
}

# Query latest response HEADER_JSON with jq
#
# $@ {any} jq_args - arguments passed to jq
HeaderJq() {
  [ "${_has_jq:-}" ] || die "[ jq ] is required."
  jq "$@" <<EOF
${HEADER_JSON:-}
EOF
}

# Enable snapshot replacement on exit
#
# @set {int} _req_id - _req_id + 1
Snapshot() {
  if [ ! "${_trapped:-}" ]; then
    if [ ! "${_runner_mode:-}" ]; then
      trap '_replace_snapshots "$0"' EXIT
    fi
    _trapped=1
  fi
  eval "_snapshot_$_req_id=\${SNAPSHOT:-}"
  _req_id=$((_req_id + 1)) # increase count every single call and ignoring Skip/Only in order to sync with _replace_snapshots
}

# Hook before each request
BeforeHook() { :; }
# Hook after each request
AfterHook() { :; }

# Standard after hook for rich snapshot
#
# @set {str} SNAPSHOT - set snapshot to header + curl meta + body
_std_jq_after_hook() {
  SNAPSHOT="$(jq --slurp --raw-output \
    --argjson selected '[ "content-type", "date", "http_code", "method", "time_total", "size_download", "url_effective" ]' '
.[0] + .[1]
| to_entries
| map(select(.key | IN($selected[])))
| (map(.key | length) | max) as $max_len
| .[]
| .key + (" " * ($max_len - (.key | length) + 4)) + ([.value] | flatten | join(" "))' <<EOF
$META_JSON
$HEADER_JSON
EOF
)
-------------------------
$(jq . <<EOF 2>/dev/null || printf '%s' "$BODY"
$BODY
EOF
)"
}

# Interal before hook that calls BeforeHook
_before_hook() {
  BeforeHook
}

# Interal after hook that calls AfterHook
#
# $1 {str} response - response from previous request
_after_hook() {
  _result=${1:-}
  BODY=
  META_JSON=
  HEADER_JSON=
  HTTP_CODE=
  if [ "$_result" = '' ]; then
    EMPTY_RESULT=1
  else
    # shellcheck disable=SC2034
    EMPTY_RESULT=0
  fi
  case $_result in
    *"$POORMAN_DELIM"*)
      BODY=${_result%%"$POORMAN_DELIM"*}
      _result=${_result#*"$POORMAN_DELIM"}
      META_JSON=${_result%%"$POORMAN_DELIM"*}
      _result=${_result#*"$POORMAN_DELIM"}
      HEADER_JSON=$_result # last one, no need to cut
      case $META_JSON in
        *'"http_code":'*)
          HTTP_CODE=${META_JSON#*'"http_code":'}
          HTTP_CODE=${HTTP_CODE%%,*}
          # shellcheck disable=SC2034
          HTTP_CODE=${HTTP_CODE%%\}*}
          ;;
      esac
      SNAPSHOT=$BODY
      ;;
    *)
      # shellcheck disable=SC2034
      SNAPSHOT=$_result
      ;;
  esac
  if [ "${_has_jq:-}" ] && [ "${META_JSON:-}" ] && [ "${HEADER_JSON:-}" ]; then
    _std_jq_after_hook
  fi
  AfterHook
}

# Replace Snapshot placeholders in a script file
#
# $1 {path} target - script file to rewrite, defaults to $0
_replace_snapshots() {
  _target=$1
  _new_content=
  _first_line=1
  _req_id=0
  if [ ! -w "$_target" ]; then
    msg "WARN: [ $_target ] is not writable"
    return
  fi
  while IFS= read -r _line || [ "$_line" ]; do
    case $_line in
    Snapshot)
      eval "_snapshot=\${_snapshot_$_req_id:-}"
      if [ "${_snapshot:-}" ]; then
        _block="Snapshot <<'SNAPSHOT'
${_snapshot:-}
SNAPSHOT"
      else
        _block=$_line
      fi
      _req_id=$((_req_id + 1))
      ;;
    "Snapshot <<'SNAPSHOT'")
      _old_block=$_line
      while IFS= read -r _heredoc_line || [ "$_heredoc_line" ]; do
        _old_block="$_old_block
$_heredoc_line"
        [ "$_heredoc_line" = SNAPSHOT ] && break
      done
      eval "_snapshot=\${_snapshot_$_req_id:-}"
      if [ "${OVERWRITE_SNAPSHOT:-}" = 1 ] && [ "${_snapshot:-}" ]; then
        _block="Snapshot <<'SNAPSHOT'
${_snapshot:-}
SNAPSHOT"
      else
        _block=$_old_block
      fi
      _req_id=$((_req_id + 1))
      ;;
    *)
      _block=$_line
      ;;
    esac
    if [ "$_first_line" ]; then
      _new_content=$_block
      _first_line=
    else
      _new_content="$_new_content
$_block"
    fi
  done <"$_target"
  printf '%s\n' "$_new_content" >"$_target"
  if [ "${_stdin_mode:-}" = 1 ]; then
    printf '%s\n' "$_new_content"
  fi
}

# If not sourced, print help or execute script/stdin
if [ ! "${__SOURCED__:-}" ]; then
  case ${ZSH_EVAL_CONTEXT:-} in
    *:file*) ;;
    *)
      case ${0##*/} in
        poorman.sh)
          case ${1:-} in
            -h | --help)
              usage
              exit 0
              ;;
            -v | --version)
              msg "$POORMAN_VERSION"
              exit 0
              ;;
            '')
              if [ -t 0 ]; then
                usage
                exit 0
              fi
              _stdin_script=${TMPDIR:-/tmp}/poorman_stdin_$$.sh
              cat >"$_stdin_script" # Copy stdin to file
              if [ ! -s "$_stdin_script" ]; then
                rm -f "$_stdin_script"
                usage
                exit 0
              fi
              _target_script=$_stdin_script
              _stdin_mode=1
              _runner_mode=1
              trap 'rm -f "$_stdin_script"' EXIT
              # shellcheck disable=SC1090
              . "$_stdin_script"
              [ "${_trapped:-}" ] && _replace_snapshots "$_target_script"
              rm -f "$_stdin_script"
              ;;
            *)
              [ -f "$1" ] || die "[ $1 ] file not found."
              _target_script=$1
              _runner_mode=1
              case $1 in
                */*) _source_path=$1 ;;
                *) _source_path=./$1 ;;
              esac
              shift
              # shellcheck disable=SC1090
              . "$_source_path"
              [ "${_trapped:-}" ] && _replace_snapshots "$_target_script"
              ;;
          esac
          ;;
      esac
      ;;
  esac
fi
