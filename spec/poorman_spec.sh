# shellcheck shell=sh
# shellcheck disable=SC2034,SC2154,SC2329

Describe "poorman.sh"
  Include "./poorman.sh"

  BeforeEach "reset_poorman_state"
  AfterEach "reset_poorman_state"

  Describe "usage"
    It "does not print help when sourced by another script"
      poorman_path=$PWD/poorman.sh
      script=$(make_temp_script source <<SCRIPT
#!/bin/sh
. "$poorman_path"
printf '%s\n' after-source
SCRIPT
)

      When run script "$script"
      The status should be success
      The output should equal "after-source"
    End

    It "prints help when executed directly with --help"
      When run script ./poorman.sh --help
      The status should be success
      The output should include "Usage:"
    End

    It "runs a script file passed as an argument and updates its Snapshot"
      poorman_path=$PWD/poorman.sh
      script=$(make_temp_script arg_run <<SCRIPT
. "$poorman_path"
curl() {
  printf 'arg body%s{"http_code":200}%s{}' "\$POORMAN_DELIM" "\$POORMAN_DELIM"
}
_has_jq=
GET /users/1
Snapshot
SCRIPT
)

      When run script ./poorman.sh "$script"
      The status should be success
      The contents of file "$script" should include "Snapshot <<'SNAPSHOT'"
      The contents of file "$script" should include "arg body"
    End

    It "runs a script from stdin and outputs rewritten content when Snapshot is used"
      script=$(make_temp_script stdin_src <<'SCRIPT'
curl() {
  printf 'piped body%s{"http_code":200}%s{}' "$POORMAN_DELIM" "$POORMAN_DELIM"
}
_has_jq=
GET /users/1
Snapshot
SCRIPT
)

      When run sh -c "./poorman.sh < \"$script\""
      The status should be success
      The output should include "GET /users/1"
      The output should include "Snapshot <<'SNAPSHOT'"
      The output should include "piped body"
    End

    It "runs a script from stdin without echoing script when Snapshot is not used"
      script=$(make_temp_script stdin_no_snap <<'SCRIPT'
DRY_RUN=1
GET /users/1
SCRIPT
)

      When run sh -c "./poorman.sh < \"$script\""
      The status should be success
      The output should equal "curl -X GET --write-out '$WRITE_OUT' 'users/1'"
    End

    Parameters
      "-v"
      "--version"
    End

    It "prints version when executed directly with $1"
      When run script ./poorman.sh "$1"
      The status should be success
      The output should equal "$POORMAN_VERSION"
    End
  End

  Describe "_check_deps()"
    It "sets _has_<dep> for available optional dependencies"
      When call _check_deps "sh=optional"
      The variable _has_sh should equal 1
      The status should be success
    End

    It "clears _has_<dep> for unavailable optional dependencies"
      _has_missing_command=1
      When call _check_deps "missing_command=optional"
      The variable _has_missing_command should be undefined
      The status should be success
    End

    It "fails for unavailable required dependencies"
      When run _check_deps "missing_command=required"
      The status should equal 1
      The output should include "[ missing_command ] is required."
    End
  End

  Describe "to_list()"
    It "quotes all arguments for eval"
      When call to_list "alpha" "two words" "quote's"
      The variable _list should equal " 'alpha' 'two words' 'quote'\''s'"
    End
  End

  Describe "to_list_quote_complex()"
    It "quotes only complex arguments"
      When call to_list_quote_complex "alpha" "two words" "a_b-c"
      The variable _list should equal " alpha 'two words' a_b-c"
    End
  End

  Describe "request dry run"
    It "prints a GET curl command"
      DRY_RUN=1
      When call GET "/users/1"
      The output should equal "curl -X GET --write-out '$WRITE_OUT' 'users/1'"
    End

    It "normalizes BASE_URL and path slashes"
      DRY_RUN=1
      BASE_URL=https://example.test/api/
      When call POST "/users" --json '{"name":"Ada"}'
      The output should equal "curl -X POST --write-out '$WRITE_OUT' --json '{\"name\":\"Ada\"}' 'https://example.test/api/users'"
    End

    It "allows full http/https URLs to override BASE_URL"
      DRY_RUN=1
      BASE_URL=https://example.test/api/
      When call POST "https://auth.example.test/oauth/token"
      The output should equal "curl -X POST --write-out '$WRITE_OUT' 'https://auth.example.test/oauth/token'"
    End

    run_two_dry_requests() {
      DRY_RUN=1
      GET "/first"
      GET "/second"
    }

    It "prints each dry run request on its own line"
      When call run_two_dry_requests
      The line 1 of output should equal "curl -X GET --write-out '$WRITE_OUT' first"
      The line 2 of output should equal "curl -X GET --write-out '$WRITE_OUT' second"
    End

    It "supports generic Request with custom HTTP method"
      DRY_RUN=1
      When call Request PURGE "/cache"
      The output should equal "curl -X PURGE --write-out '$WRITE_OUT' cache"
    End

    It "fails when Request is missing method or endpoint"
      When run Request PURGE
      The status should equal 1
      The output should include "expecting Request <METHOD> <endpoint>"
    End

    Parameters
      PUT
      PATCH
      DELETE
      HEAD
      OPTIONS
    End

    It "supports $1"
      DRY_RUN=1
      When call "$1" "/thing"
      The output should start with "curl -X $1 "
    End
  End

  Describe "curl options"
    It "adds global options to subsequent requests"
      DRY_RUN=1
      CurlOptionGlobal --location --header "X-App: poorman"
      When call GET "/users"
      The output should equal "curl -X GET --write-out '$WRITE_OUT' --location --header 'X-App: poorman' users"
    End

    It "resets global options with CurlOptionGlobalReset"
      DRY_RUN=1
      CurlOptionGlobal --location --header "X-App: poorman"
      CurlOptionGlobalReset
      When call GET "/users"
      The output should equal "curl -X GET --write-out '$WRITE_OUT' users"
    End

    run_second_after_first() {
      DRY_RUN=1
      CurlOptionOnce --user "admin:password"
      GET "/first" >/dev/null
      GET "/second"
    }

    It "adds once options to one enabled request only"
      When call run_second_after_first
      The output should equal "curl -X GET --write-out '$WRITE_OUT' second"
    End
  End

  Describe "Skip()"
    curl() {
      echo "called"
    }

    poorman_skip() {
      eval 'Skip "$@"'
    }

    It "suppresses one request"
      When call Skip GET "/users"
      The output should equal ""
    End

    It "does not suppress the next plain request"
      run_after_skipped() {
        DRY_RUN=1
        poorman_skip GET "/skipped"
        GET "/users"
      }

      When call run_after_skipped
      The output should start with "curl -X GET "
    End

    It "rejects invalid commands"
      When run Skip NOPE "/users"
      The status should equal 1
      The output should include "expecting GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request"
    End

    It "rejects missing command under set -u"
      run_skip_without_args() {
        set -u
        poorman_skip
      }

      When run run_skip_without_args
      The status should equal 1
      The output should include "expecting GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request"
    End

    It "allows skipping an Only request"
      ONLY=1
      DRY_RUN=1
      When call Skip Only GET "/users"
      The output should equal ""
    End
  End

  Describe "Only()"
    It "runs marked requests when ONLY is enabled"
      ONLY=1
      DRY_RUN=1
      When call Only GET "/users"
      The output should start with "curl -X GET "
    End

    It "skips plain requests when ONLY is enabled"
      ONLY=1
      When call GET "/users"
      The output should equal ""
    End

    It "runs marked requests when ONLY is disabled"
      DRY_RUN=1
      When call Only DELETE "/users/1"
      The output should start with "curl -X DELETE "
    End

    It "respects Skip inside Only"
      ONLY=1
      DRY_RUN=1
      When call Only Skip GET "/users"
      The output should equal ""
    End

    It "rejects missing command under set -u"
      run_only_without_args() {
        set -u
        Only
      }

      When run run_only_without_args
      The status should equal 1
      The output should include "expecting GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Request"
    End
  End

  Describe "hooks and response variables"
    curl() {
      printf '{"id":1}%s{"http_code":201,"method":"POST"}%s{"content-type":["application/json"]}' "$POORMAN_DELIM" "$POORMAN_DELIM"
    }

    It "runs hooks and sets response variables including HTTP_CODE"
      BeforeHook() {
        _hook_order="${_hook_order:-}before "
      }

      AfterHook() {
        _hook_order="${_hook_order:-}after"
        printf '%s' "$BODY"
      }

      When call POST "/users"
      The output should equal '{"id":1}'
      The variable BODY should equal '{"id":1}'
      The variable HTTP_CODE should equal 201
      The variable META_JSON should equal '{"http_code":201,"method":"POST"}'
      The variable HEADER_JSON should equal '{"content-type":["application/json"]}'
      The variable SNAPSHOT should equal '{"id":1}'
      The variable EMPTY_RESULT should equal 0
      The variable _hook_order should equal "before after"
    End
  End

  Describe "BodyJq()"
    It "queries BODY with jq"
      _has_jq=1
      BODY='{"user":{"name":"Ada"}}'
      When call BodyJq -r '.user.name'
      The status should be success
      The output should equal "Ada"
    End

    It "fails when jq is unavailable"
      _has_jq=
      BODY='{"user":{"name":"Ada"}}'
      When run BodyJq '.user.name'
      The status should equal 1
      The output should include "[ jq ] is required"
    End
  End

  Describe "HeaderJq()"
    It "queries HEADER_JSON with jq"
      _has_jq=1
      HEADER_JSON='{"content-type":["application/json"]}'
      When call HeaderJq -r '.["content-type"][0]'
      The status should be success
      The output should equal "application/json"
    End

    It "fails when jq is unavailable"
      _has_jq=
      HEADER_JSON='{"content-type":["application/json"]}'
      When run HeaderJq '.["content-type"][0]'
      The status should equal 1
      The output should include "[ jq ] is required"
    End
  End

  Describe "_after_hook()"
    It "marks empty responses"
      When call _after_hook ""
      The variable EMPTY_RESULT should equal 1
      The variable SNAPSHOT should equal ""
    End

    It "uses a plain response as the snapshot"
      When call _after_hook "plain response"
      The variable EMPTY_RESULT should equal 0
      The variable SNAPSHOT should equal "plain response"
    End

    It "splits response using custom POORMAN_DELIM"
      POORMAN_DELIM="__CUSTOM_DELIM__"
      When call _after_hook 'body__CUSTOM_DELIM__{"http_code":204}__CUSTOM_DELIM__{}'
      The variable BODY should equal "body"
      The variable HTTP_CODE should equal 204
      The variable META_JSON should equal '{"http_code":204}'
      The variable HEADER_JSON should equal "{}"
    End

    It "builds rich SNAPSHOT with _std_jq_after_hook when jq is available"
      _has_jq=1
      When call _after_hook '{"id":1}__POORMAN_DELIM__{"http_code":200,"method":"GET"}__POORMAN_DELIM__{"content-type":["application/json"]}'
      The variable SNAPSHOT should include "http_code"
      The variable SNAPSHOT should include "content-type    application/json"
      The variable SNAPSHOT should include '  "id": 1'
    End
  End

  Describe "Snapshot()"
    It "rewrites Snapshot lines in the given script without adding leading blank lines"
      script=$(make_temp_script snapshot <<'SCRIPT'
#!/bin/sh
GET /users
Snapshot
SCRIPT
)
      _snapshot_0='saved body'

      When call _replace_snapshots "$script"
      The status should be success
      The line 1 of contents of file "$script" should equal "#!/bin/sh"
      The line 2 of contents of file "$script" should equal "GET /users"
      The line 3 of contents of file "$script" should equal "Snapshot <<'SNAPSHOT'"
      The line 4 of contents of file "$script" should equal "saved body"
      The line 5 of contents of file "$script" should equal "SNAPSHOT"
    End

    It "does not overwrite an existing Snapshot heredoc block when OVERWRITE_SNAPSHOT is not set"
      script=$(make_temp_script snapshot_no_overwrite <<'SCRIPT'
#!/bin/sh
GET /users
Snapshot <<'SNAPSHOT'
old body line 1
old body line 2
SNAPSHOT
POST /users
SCRIPT
)
      _snapshot_0='updated body'

      When call _replace_snapshots "$script"
      The status should be success
      The line 1 of contents of file "$script" should equal "#!/bin/sh"
      The line 2 of contents of file "$script" should equal "GET /users"
      The line 3 of contents of file "$script" should equal "Snapshot <<'SNAPSHOT'"
      The line 4 of contents of file "$script" should equal "old body line 1"
      The line 5 of contents of file "$script" should equal "old body line 2"
      The line 6 of contents of file "$script" should equal "SNAPSHOT"
      The line 7 of contents of file "$script" should equal "POST /users"
    End

    It "overwrites an existing Snapshot heredoc block when OVERWRITE_SNAPSHOT=1"
      script=$(make_temp_script snapshot_update <<'SCRIPT'
#!/bin/sh
GET /users
Snapshot <<'SNAPSHOT'
old body line 1
old body line 2
SNAPSHOT
POST /users
SCRIPT
)
      OVERWRITE_SNAPSHOT=1
      _snapshot_0='updated body'

      When call _replace_snapshots "$script"
      The status should be success
      The line 1 of contents of file "$script" should equal "#!/bin/sh"
      The line 2 of contents of file "$script" should equal "GET /users"
      The line 3 of contents of file "$script" should equal "Snapshot <<'SNAPSHOT'"
      The line 4 of contents of file "$script" should equal "updated body"
      The line 5 of contents of file "$script" should equal "SNAPSHOT"
      The line 6 of contents of file "$script" should equal "POST /users"
    End

    It "preserves an existing Snapshot heredoc block when its request was skipped even with OVERWRITE_SNAPSHOT=1"
      script=$(make_temp_script snapshot_preserve <<'SCRIPT'
#!/bin/sh
GET /users
Snapshot <<'SNAPSHOT'
kept body
SNAPSHOT
SCRIPT
)
      OVERWRITE_SNAPSHOT=1
      _snapshot_0=''

      When call _replace_snapshots "$script"
      The status should be success
      The line 1 of contents of file "$script" should equal "#!/bin/sh"
      The line 2 of contents of file "$script" should equal "GET /users"
      The line 3 of contents of file "$script" should equal "Snapshot <<'SNAPSHOT'"
      The line 4 of contents of file "$script" should equal "kept body"
      The line 5 of contents of file "$script" should equal "SNAPSHOT"
    End

    It "rewrites Snapshot even when the file has no trailing newline"
      script=$(make_temp_script snapshot_no_eof_nl <<'SCRIPT'
#!/bin/sh
GET /users
SCRIPT
)
      printf 'Snapshot' >>"$script"
      _snapshot_0='saved body'

      When call _replace_snapshots "$script"
      The status should be success
      The contents of file "$script" should include "saved body"
    End

    It "does not reuse previous SNAPSHOT when a request is skipped"
      curl() {
        printf 'First Body%s{"http_code":200}%s{}' "$POORMAN_DELIM" "$POORMAN_DELIM"
      }

      run_with_skipped_snapshot() {
        _trapped=1
        GET "/first"
        Snapshot
        eval 'Skip GET "/second"'
        Snapshot
      }

      When call run_with_skipped_snapshot
      The variable _snapshot_0 should equal "First Body"
      The variable _snapshot_1 should equal ""
    End

    It "works under set -u when SNAPSHOT is unset"
      run_snapshot_unset() {
        _trapped=1
        set -u
        unset SNAPSHOT
        Snapshot
      }

      When call run_snapshot_unset
      The status should be success
      The variable _snapshot_0 should equal ""
    End
  End
End
