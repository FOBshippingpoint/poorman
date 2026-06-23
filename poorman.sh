#!/bin/sh
# vim: set expandtab tabstop=2 softtabstop=2 shiftwidth=2 :

# @name Poorman
# @description A very limited alternative to Postman, powered by curl and POSIX shell.
# @version 0.1
# @author CC Lan

WRITE_OUT='__POORMAN_DELIM__%{json}__POORMAN_DELIM__%{header_json}'
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
          msg "[ $_arg ] is required."
        ;;
      esac
    fi
  done
  [ "${_failed:-}" ] && die || return
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
# $1 {GET|POST|PUT|PATCH|DELETE} request - request method
# $2 {str} path - path of URL. e.g., /users/1
# @need {1|any} ONLY - is current script run in ONLY mode?
# @need {1|any} _only - is current request mark as "Only"
# @need {str}? BASE_URL - base URL of the request
# @need {str} WRITE_OUT - curl write out
# @need {1|any} DRY_RUN - is current script run in DRY_RUN mode? Prints curl commands if DRY_RUN=1
# @internal
_fetch() {
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
  [ "${BASE_URL:-}" ] && BASE_URL="${BASE_URL%/}/"
  set -- curl -X "$_request" --write-out "$WRITE_OUT" "$@" "${BASE_URL:-}${_path#/}"
  if [ "${DRY_RUN:-}" = 1 ]; then
    quote_complex_only "$@"
    printf '%s' "${_list#?}"
  else
    _after_hook "$("$@")"
  fi
}

GET() { _fetch GET "$@"; }
POST() { _fetch POST "$@"; }
PUT() { _fetch PUT "$@"; }
PATCH() { _fetch PATCH "$@"; }
DELETE() { _fetch DELETE "$@"; }

# Skip the request
#
# $@ {any} request_command - the request command starts with GET|POST|PUT|PATCH|DELETE
Skip() { 
  case $1 in
    GET|POST|PUT|PATCH|DELETE) ;;
    *) die "[ Skip $1 ... ] is invalid, expecting GET|POST|PUT|PATCH|DELETE";;
  esac
  _skip=1 "$@"
}
# Only run the request
#
# $@ {any} request_command - the request command starts with GET|POST|PUT|PATCH|DELETE
# @need {1|any} ONLY - Only works when $ONLY = 1
Only() {
  case $1 in
    GET|POST|PUT|PATCH|DELETE) ;;
    *) die "[ Only $1 ... ] is invalid, expecting GET|POST|PUT|PATCH|DELETE";;
  esac
  if [ "${ONLY:-}" = 1 ]; then
    _only=1 "$@"
  else
    # shellcheck disable=SC1007
    _only= "$@"
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
# Add curl options for the next request
#
# $@ {any} curl_options - options passed to curl as is
CurlOptionOnce() {
  for _opt in "$@"; do
    quote _quoted "$_opt"
    _once_opts="${_once_opts:-} ${_quoted:-}"
  done
}

# Enable trap _self_replace on exit
#
# @set {int} _req_id - _req_id + 1
Snapshot() {
  if [ ! "${_trapped:-}" ]; then
    trap _self_replace EXIT
    _trapped=1
  fi
  eval "_snapshot_$_req_id=\$SNAPSHOT"
  _req_id=$((_req_id + 1)) # increase count every single call and ignoring Skip/Only in order to sync with _self_replace
}

# Hook before each request
BeforeHook() { :; }
# Hook after each request
AfterHook() { :; }

# Standard after hook for rich snapshot
#
# @set {str} SNAPSHOT - set snapshot to header + curl meta + body
_std_jq_after_hook() {
  SNAPSHOT="$(jq --null-input --raw-output \
    --argjson selected '[ "content-type", "date", "http_code", "method", "time_total", "size_download", "url_effective" ]' \
    --argjson meta "$META_JSON" \
    --argjson header "$HEADER_JSON" '
$meta + $header
| to_entries
| map(select(.key | IN($selected[])))
| (map(.key | length) | max) as $max_len
| .[]
| .key + (" " * ($max_len - (.key | length) + 4)) + ([.value] | flatten | join(" "))')
-------------------------
$(jq --null-input --argjson body "$BODY" '$body' 2>/dev/null || printf '%s' "$BODY")"
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
  if [ "$_result" = '' ]; then
    EMPTY_RESULT=1
  else
    # shellcheck disable=SC2034
    EMPTY_RESULT=0
  fi
  case $_result in
    *__POORMAN_DELIM__*)
      BODY=${_result%%__POORMAN_DELIM__*}
      _result=${_result#*__POORMAN_DELIM__}
      META_JSON=${_result%%__POORMAN_DELIM__*}
      _result=${_result#*__POORMAN_DELIM__}
      HEADER_JSON=$_result # last one, no need to cut
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

# Trap function that injects all "Snapshot" to the script file
_self_replace() {
  _new_content=
  _req_id=0
  while IFS= read -r _line; do
    case $_line in
    Snapshot)
      eval "_snapshot=\$_snapshot_$_req_id"
      if [ "${_snapshot:-}" ]; then
        _new_content="$_new_content
: <<'SNAPSHOT'
${_snapshot:-}
SNAPSHOT"
      else
        _new_content="$_new_content
$_line"
      fi
      _req_id=$((_req_id + 1))
      ;;
    *)
      _new_content="$_new_content
$_line"
      ;;
    esac
  done <"$0"
  printf '%s' "$_new_content" >"$0"
}
