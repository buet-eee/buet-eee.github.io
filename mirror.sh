#!/usr/bin/env bash
set -euo pipefail

SITE_URL="https://eee.buet.ac.bd/"
HOST="eee.buet.ac.bd"

# GitHub Pages will publish this folder
OUT_DIR="public"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

wget \
  --mirror \
  --page-requisites \
  --convert-links \
  --adjust-extension \
  --no-parent \
  --execute robots=off \
  --domains="${HOST}" \
  --timeout=30 \
  --tries=2 \
  --wait=1 \
  --directory-prefix="${OUT_DIR}" \
  "${SITE_URL}"

# Move content to Pages root
if [ -d "${OUT_DIR}/${HOST}" ]; then
  shopt -s dotglob
  mv "${OUT_DIR}/${HOST}/"* "${OUT_DIR}/"
  rmdir "${OUT_DIR}/${HOST}" || true
  shopt -u dotglob
fi

test -f "${OUT_DIR}/index.html"
echo "Mirror generated in: ${OUT_DIR}"
