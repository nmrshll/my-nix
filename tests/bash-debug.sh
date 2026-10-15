#!/usr/bin/env bash
set -euo pipefail
source "$1"

testDir=$(mktemp -d)
trap 'rm -rf "$testDir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

plain=hello
empty=''
zero=0
quoted='quote" backslash\ $dollar * [glob] -n'
multiline=$'line one\nline two\tend'
values=('one two' '*')
export exported='exported value'
unset missing

# Diagnostics must not enter captured command output. An unset variable must
# neither abort a strict-mode caller nor prevent later arguments being shown.
stdout=$(dbg_vars plain empty zero quoted multiline values missing exported 2>"$testDir/debug")
[[ -z $stdout ]] || fail 'diagnostics leaked to stdout'
diagnostics=$(<"$testDir/debug")
[[ $diagnostics == *'declare -- plain="hello"'* ]] || fail 'plain scalar'
[[ $diagnostics == *'declare -- empty=""'* ]] || fail 'empty scalar'
[[ $diagnostics == *'declare -- zero="0"'* ]] || fail 'zero scalar'
[[ $diagnostics == *'declare -- quoted='* && $diagnostics == *'\$dollar'* ]] || fail 'shell quoting'
[[ $diagnostics == *'declare -- multiline='* ]] || fail 'multiline scalar'
[[ $multiline == $'line one\nline two\tend' ]] || fail 'multiline value changed'
[[ $diagnostics == *'declare -a values='* && $diagnostics == *'[0]="one two"'* && $diagnostics == *'[1]="*"'* ]] || fail 'array values'
[[ $diagnostics == *'missing: not found'* ]] || fail 'unset scalar'
[[ $diagnostics == *'declare -x exported="exported value"'* ]] || fail 'exported scalar after unset'

dbg_var missing 2>"$testDir/unset"
[[ $(<"$testDir/unset") == *'missing: not found'* ]] || fail 'unset-only call under strict mode'

dbg_var plain 2>"$testDir/single"
[[ $(<"$testDir/single") == 'declare -- plain="hello"' ]] || fail 'singular alias'

# With no names, declare -p would dump the entire environment. Both wrappers
# must instead produce no output and succeed under strict mode.
stdout=$(dbg_vars 2>"$testDir/none")
[[ -z $stdout && ! -s "$testDir/none" ]] || fail 'zero-argument plural call'
stdout=$(dbg_var 2>"$testDir/none")
[[ -z $stdout && ! -s "$testDir/none" ]] || fail 'zero-argument singular call'

check_caller_locals() {
  local var_name='caller local' _dbg_name='another local'
  dbg_vars var_name _dbg_name
  [[ $var_name == 'caller local' && $_dbg_name == 'another local' ]] || fail 'caller locals changed'
}
check_caller_locals 2>"$testDir/locals"
diagnostics=$(<"$testDir/locals")
[[ $diagnostics == *'var_name="caller local"'* ]] || fail 'caller local lookup'
[[ $diagnostics == *'_dbg_name="another local"'* ]] || fail 'caller local shadowed'

printf 'Bash debug fragment checks passed\n'
