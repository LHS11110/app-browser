#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CEF_VERSION="151.3.24+g2384915+chromium-151.0.7922.174"
ARCH="macosarm64"
DISTRIB_NAME="cef_binary_${CEF_VERSION}_${ARCH}"
URL_ENCODED_VERSION="151.3.24%2Bg2384915%2Bchromium-151.0.7922.174"
DOWNLOAD_URL="https://cef-builds.spotifycdn.com/cef_binary_${URL_ENCODED_VERSION}_${ARCH}.tar.bz2"

THIRD_PARTY_DIR="${PROJECT_ROOT}/third_party"
TARGET_DIR="${THIRD_PARTY_DIR}/cef"
ARCHIVE_PATH="${THIRD_PARTY_DIR}/${DISTRIB_NAME}.tar.bz2"

mkdir -p "${THIRD_PARTY_DIR}"

if [[ -f "${TARGET_DIR}/include/cef_version.h" ]]; then
  echo "==> CEF is already installed in: ${TARGET_DIR}"
  exit 0
fi

echo "==> Downloading CEF (${DISTRIB_NAME})..."
if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  curl -L --progress-bar "${DOWNLOAD_URL}" -o "${ARCHIVE_PATH}"
fi

echo "==> Extracting ${ARCHIVE_PATH}..."
tar -xjf "${ARCHIVE_PATH}" -C "${THIRD_PARTY_DIR}"

# Remove existing symlink or old directory if present
rm -rf "${TARGET_DIR}"
mv "${THIRD_PARTY_DIR}/${DISTRIB_NAME}" "${TARGET_DIR}"

echo "==> CEF setup completed successfully: ${TARGET_DIR}"
