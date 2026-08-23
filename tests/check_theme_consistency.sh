#!/usr/bin/env bash
# ==========================================================================
# tests/check_theme_consistency.sh — Verify pushTheme/popTheme duplication
#
# Extracts the color values and style-var values from each satellite module's
# pushTheme() function and compares them against the canonical copy in
# triune_buttons.lua (the smallest/cleanest satellite).  Exits non-zero on
# drift.
#
# The comparison ignores variable names (pushCol vs UI.pushCol) and only
# compares the numeric tuples and ImGui enum names, since triune.lua uses a
# UI.pushCol wrapper while satellites use a standalone pushCol.
# ==========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LUA_DIR="$REPO_ROOT/mq2triune/lua"

# The canonical satellite module (smallest, cleanest pushTheme copy)
CANONICAL="$LUA_DIR/triune_buttons.lua"

# All satellite modules that should carry identical pushTheme copies
SATELLITES=(
    "$LUA_DIR/triune_buffbot.lua"
    "$LUA_DIR/triune_cursor.lua"
    "$LUA_DIR/triune_dps.lua"
    "$LUA_DIR/triune_spellbook.lua"
    "$LUA_DIR/triune_track.lua"
    "$LUA_DIR/triune_updater.lua"
)

# Extract just the color/var tuples from a pushTheme function body.
# This normalizes away the variable-name differences (ImGuiCol vs Col, etc.)
# and produces a stable fingerprint of the actual theme values.
extract_theme_fingerprint() {
    local file="$1"
    # Extract pushTheme body (from 'local function pushTheme' to next 'end' at col 1)
    sed -n '/^local function pushTheme()/,/^end$/p' "$file" \
        | grep -oP '\.\w+,\s*[\d.]+,\s*[\d.]+,\s*[\d.]+[^)]*\)' \
        | sed 's/[[:space:]]//g' \
        | sort
}

# Also extract style vars
extract_stylevar_fingerprint() {
    local file="$1"
    sed -n '/^local function pushTheme()/,/^end$/p' "$file" \
        | grep -iP 'pushVar\(' \
        | grep -oP '\.\w+,\s*[\d.]+[^)]*\)' \
        | sed 's/[[:space:]]//g' \
        | sort
}

fail=0

# Get canonical fingerprints
canonical_colors=$(extract_theme_fingerprint "$CANONICAL")
canonical_vars=$(extract_stylevar_fingerprint "$CANONICAL")

if [ -z "$canonical_colors" ]; then
    echo "::error::Could not extract pushTheme colors from canonical file: $(basename "$CANONICAL")"
    exit 1
fi

echo "Canonical theme source: $(basename "$CANONICAL")"
echo "  Color entries: $(echo "$canonical_colors" | wc -l)"
echo "  StyleVar entries: $(echo "$canonical_vars" | wc -l)"
echo ""

for sat in "${SATELLITES[@]}"; do
    name="$(basename "$sat")"

    sat_colors=$(extract_theme_fingerprint "$sat")
    sat_vars=$(extract_stylevar_fingerprint "$sat")

    if [ -z "$sat_colors" ]; then
        echo "::error file=$sat::Could not extract pushTheme from $name"
        fail=1
        continue
    fi

    # Compare colors
    color_diff=$(diff <(echo "$canonical_colors") <(echo "$sat_colors") || true)
    if [ -n "$color_diff" ]; then
        echo "::error file=$sat::Theme COLOR drift in $name"
        echo "  Diff vs $(basename "$CANONICAL"):"
        echo "$color_diff" | head -20
        fail=1
    else
        echo "OK: $name (colors match)"
    fi

    # Compare vars
    var_diff=$(diff <(echo "$canonical_vars") <(echo "$sat_vars") || true)
    if [ -n "$var_diff" ]; then
        echo "::error file=$sat::Theme STYLEVAR drift in $name"
        echo "  Diff vs $(basename "$CANONICAL"):"
        echo "$var_diff" | head -20
        fail=1
    else
        echo "OK: $name (style vars match)"
    fi
done

echo ""
if [ $fail -ne 0 ]; then
    echo "FAIL: Theme drift detected. Update the drifted module(s) to match $(basename "$CANONICAL")."
    exit 1
else
    echo "All satellite themes match the canonical copy."
    exit 0
fi
