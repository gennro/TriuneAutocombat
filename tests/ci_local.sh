#!/usr/bin/env bash
# Runs the same five checks as .github/workflows/ci.yml so a push can be
# verified locally first. Usage: bash tests/ci_local.sh
# Needs: luajit, luac5.1 (or luac), luacheck.
set -u
cd "$(dirname "$0")/.." || exit 1
LUAC=$(command -v luac5.1 || command -v luac)
fail=0
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
bad()  { printf '\033[31mFAIL: %s\033[0m\n' "$1"; fail=1; }

step "1/5 LuaJIT + Lua 5.1 syntax"
errlog=$(mktemp)
while IFS= read -r f; do
    if ! luajit -bl "$f" > /dev/null 2>"$errlog"; then bad "$f (luajit)"; cat "$errlog"
    elif ! "$LUAC" -p "$f" > /dev/null 2>"$errlog"; then bad "$f (luac: >200 locals or syntax)"; cat "$errlog"
    fi
done < <(find TAC -name '*.lua' -type f)
rm -f "$errlog"
[ "$fail" = 0 ] && echo "all files compile"

step "2/5 Version consistency"
MAIN=$(grep -oP "^local VERSION\s+= '\K[^']+" TAC/lua/triune.lua)
README=$(grep -oP "Current version: \*\*\K[^*]+" README.md)
if [ "$MAIN" != "$README" ]; then bad "triune.lua=$MAIN README.md=$README"; else echo "in sync: $MAIN"; fi

step "3/5 Luacheck"
luacheck TAC/ -q || bad "luacheck warnings (CI fails on any warning)"

step "4/5 Unit tests"
luajit tests/test_pure_logic.lua | tail -n 8 || bad "unit tests"
[ "${PIPESTATUS[0]}" = 0 ] || bad "unit tests"

step "5/5 Theme consistency"
bash tests/check_theme_consistency.sh | tail -n 2 || bad "theme consistency"
[ "${PIPESTATUS[0]}" = 0 ] || bad "theme consistency"

echo
if [ "$fail" = 0 ]; then printf '\033[32mAll CI checks passed - safe to push.\033[0m\n'
else printf '\033[31mSome CI checks failed - fix before pushing.\033[0m\n'; fi
exit $fail
