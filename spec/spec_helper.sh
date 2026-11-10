# shellcheck shell=sh
# shellcheck disable=SC2034,SC2329

spec_helper_precheck() {
  minimum_version "0.28.0"
}

reset_poorman_state() {
  BASE_URL=
  DRY_RUN=
  ONLY=
  OVERWRITE_SNAPSHOT=
  BODY=
  META_JSON=
  HEADER_JSON=
  HTTP_CODE=
  SNAPSHOT=
  EMPTY_RESULT=

  _trapped=
  _req_id=0
  _skip=
  _only=
  _list=
  _quoted=
  _global_opts=
  _once_opts=
  _snapshot=
  _snapshot_0=
  _snapshot_1=
  _has_jq=
  _target_script=
  _stdin_script=
  _stdin_mode=
  _runner_mode=
  _POORMAN_LOADED=

  BeforeHook() { :; }
  AfterHook() { :; }

  if [ "${_tmp_script:-}" ] && [ -e "$_tmp_script" ]; then
    rm -f "$_tmp_script"
  fi
  _tmp_script=
}

make_temp_script() {
  _tmp_script=${TMPDIR:-/tmp}/poorman-shellspec-$$-$1.sh
  cat >"$_tmp_script"
  chmod +x "$_tmp_script"
  printf '%s\n' "$_tmp_script"
}
