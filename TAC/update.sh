#!/usr/bin/env bash
# TriuneAutocombat Linux Updater Shell Wrapper (located inside mq2triune/)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/triune_updater.py" ] && command -v python3 &>/dev/null; then
    echo "[INFO] Launching Python 3 updater..."
    exec python3 "${SCRIPT_DIR}/triune_updater.py" "$@"
fi

if [ -f "${SCRIPT_DIR}/triune_updater.py" ] && command -v python &>/dev/null; then
    echo "[INFO] Launching Python updater..."
    exec python "${SCRIPT_DIR}/triune_updater.py" "$@"
fi

echo "[INFO] Python 3 not detected. Using curl/unzip fallback..."
REPO="gennro/TriuneAutocombat"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

echo "[INFO] Querying GitHub API for latest release..."
RELEASE_JSON=$(curl -sL -H "User-Agent: TriuneAutocombat-Updater" "${API_URL}")
TAG_NAME=$(echo "${RELEASE_JSON}" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)

echo "[INFO] Latest release tag: ${TAG_NAME}"
DOWNLOAD_URL=$(echo "${RELEASE_JSON}" | grep -o '"browser_download_url": "[^"]*' | head -n 1 | cut -d'"' -f4)

if [ -z "${DOWNLOAD_URL}" ]; then
    DOWNLOAD_URL="https://github.com/${REPO}/archive/refs/tags/${TAG_NAME}.zip"
fi

TMP_ZIP=$(mktemp --suffix=.zip)
trap 'rm -f "${TMP_ZIP}"' EXIT

echo "[INFO] Downloading release package from ${DOWNLOAD_URL}..."
curl -sL -o "${TMP_ZIP}" "${DOWNLOAD_URL}"

TARGET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
echo "[INFO] Extracting update files to ${TARGET_DIR}..."
unzip -o -q "${TMP_ZIP}" -d "${TARGET_DIR}"

echo "[SUCCESS] Update completed successfully!"
