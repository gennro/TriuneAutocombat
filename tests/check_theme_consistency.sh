#!/usr/bin/env bash
# ==========================================================================
# tests/check_theme_consistency.sh — Verify there is exactly one theme
#
# Every companion tool used to be a standalone script carrying its own copy
# of pushTheme()/popTheme(), and this script diffed those copies against a
# canonical one. All of them are in-process plugins now (TAC/lua/tac/*.lua)
# and draw through core.pushTheme()/core.popTheme(), so the check is simply:
#
#   1. triune.lua still defines UI.pushTheme / UI.popTheme (the one theme).
#   2. No plugin defines its own pushTheme/popTheme or pushes the theme
#      colour tuples itself (drift would be invisible until it looked wrong).
#   3. Every plugin that opens a (non-overlay) window uses core.pushTheme().
#
# Exits non-zero on drift.
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LUA_DIR="$REPO_ROOT/TAC/lua"
PLUGIN_DIR="$LUA_DIR/tac"
CORE="$LUA_DIR/triune.lua"

fail=0

if ! grep -q '^function UI.pushTheme()' "$CORE" || ! grep -q '^function UI.popTheme()' "$CORE"; then
    echo "::error file=$CORE::triune.lua must define UI.pushTheme() and UI.popTheme()"
    exit 1
fi
echo "Canonical theme source: $(basename "$CORE") (UI.pushTheme / UI.popTheme)"

# Fingerprint of the canonical colour tuples, used to spot copied theme blocks.
canonical_colors=$(sed -n '/^function UI.pushTheme()/,/^end$/p' "$CORE" \
    | grep -oP '\.\w+,\s*[\d.]+,\s*[\d.]+,\s*[\d.]+[^)]*\)' | sed 's/[[:space:]]//g' | sort)
echo "  Color entries: $(echo "$canonical_colors" | wc -l)"
echo ""

shopt -s nullglob
for plugin in "$PLUGIN_DIR"/*.lua; do
    name="$(basename "$plugin")"

    if grep -qE '^\s*local function (pushTheme|popTheme|pushCol|pushVar)\s*\(' "$plugin"; then
        echo "::error file=$plugin::$name defines its own theme helpers; use core.pushTheme()/core.popTheme()"
        fail=1
        continue
    fi

    copied=$( (grep -oP '\.\w+,\s*[\d.]+,\s*[\d.]+,\s*[\d.]+[^)]*\)' "$plugin" || true) | sed 's/[[:space:]]//g' | sort | comm -12 - <(echo "$canonical_colors") | wc -l)
    if [ "$copied" -gt 3 ]; then
        echo "::error file=$plugin::$name re-pushes $copied canonical theme colour tuples (copied theme block)"
        fail=1
        continue
    fi

    # Transparent overlays (NoBackground, e.g. floating damage text) have no theme to apply.
    if grep -q 'ImGui.Begin(' "$plugin" && ! grep -q 'core.pushTheme()' "$plugin" && ! grep -q 'ImGuiWindowFlags.NoBackground' "$plugin"; then
        echo "::error file=$plugin::$name opens a window without core.pushTheme()"
        fail=1
        continue
    fi

    echo "OK: $name"
done

echo ""
if [ $fail -ne 0 ]; then
    echo "FAIL: Theme drift detected. Plugins must draw through core.pushTheme()/core.popTheme()."
    exit 1
else
    echo "All plugins draw through the core theme."
    exit 0
fi
