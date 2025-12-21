#!/usr/bin/env bash
set -euo pipefail

SITE_URL="https://eee.buet.ac.bd/"
HOST="eee.buet.ac.bd"

# Output directory that will be published to GitHub Pages
OUT_DIR="public"

# Banner settings
PRIMARY_URL="https://eee.buet.ac.bd/"
BANNER_TEXT='This is a read-only mirror for availability. The authoritative website is <a href="https://eee.buet.ac.bd/" rel="noopener noreferrer">eee.buet.ac.bd</a>.'

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# Crawl and convert into a static, browsable mirror.
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

# wget typically creates: public/eee.buet.ac.bd/...
# For https://buet-eee.github.io/ we need index.html at public/
if [ -d "${OUT_DIR}/${HOST}" ]; then
  shopt -s dotglob
  mv "${OUT_DIR}/${HOST}/"* "${OUT_DIR}/"
  rmdir "${OUT_DIR}/${HOST}" || true
  shopt -u dotglob
fi

# Create a defensive robots.txt (note: meta noindex is the real control)
cat > "${OUT_DIR}/robots.txt" <<'EOF'
User-agent: *
Disallow: /
EOF

# --- Inject SEO controls + banner into all HTML files ---
# 1) <meta name="robots" content="noindex, nofollow">
# 2) <link rel="canonical" href="https://eee.buet.ac.bd/">
# 3) A visible banner after <body> (once per page), HTML-safe
#
# We do minimal, resilient string insertions:
# - Insert meta/canonical right after <head> tag (case-insensitive)
# - Insert banner right after <body...> tag (case-insensitive), if not already present

find "${OUT_DIR}" -type f -name "*.html" -print0 | while IFS= read -r -d '' file; do
  # Inject robots noindex/nofollow if missing
  if ! grep -qi '<meta[[:space:]]\+name=["'\'']robots["'\'']' "$file"; then
    # Insert immediately after the opening <head> tag
    sed -i '0,/<head[^>]*>/I{s/<head[^>]*>/<head>\n<meta name="robots" content="noindex, nofollow">/I}' "$file"
  fi

  # Inject canonical if missing
  if ! grep -qi '<link[[:space:]]\+rel=["'\'']canonical["'\'']' "$file"; then
    # Insert after <head> tag as well (below robots tag if it was inserted)
    sed -i "0,/<head[^>]*>/I{s/<head[^>]*>/<head>\n<link rel=\"canonical\" href=\"${PRIMARY_URL}\">/I}" "$file"
  fi

  # Inject banner if missing (we add a unique marker attribute to avoid duplicates)
  if ! grep -qi 'data-mirror-banner="1"' "$file"; then
    # Build banner HTML. Keep it simple and self-contained, no external assets.
    # Use inline styles to avoid CSS dependency.
    banner_html=$(cat <<'BANNER'
<div data-mirror-banner="1" style="position:relative; z-index:9999; width:100%; box-sizing:border-box; padding:10px 12px; background:#fff3cd; color:#664d03; border-bottom:1px solid #ffecb5; font:14px/1.35 Arial, sans-serif;">
  <strong>Mirror notice:</strong>
  <span>__BANNER_TEXT__</span>
</div>
BANNER
)
    # Replace placeholder with configured banner text (already HTML)
    banner_html="${banner_html/__BANNER_TEXT__/${BANNER_TEXT}}"

    # Insert banner right after the opening <body ...> tag (case-insensitive)
    # We do a single replacement at the first occurrence only.
    # If a page has no <body>, we skip quietly.
    if grep -qi '<body[^>]*>' "$file"; then
      # Escape backslashes and ampersands for sed replacement
      safe_banner=$(printf '%s' "$banner_html" | sed 's/[\/&]/\\&/g')
      sed -i "0,/<body[^>]*>/I{s/<body[^>]*>/<body>\n${safe_banner}/I}" "$file"
    fi
  fi
done

# Sanity check
if [ ! -f "${OUT_DIR}/index.html" ]; then
  echo "Error: ${OUT_DIR}/index.html not found after mirroring."
  echo "Debug: listing possible index.html files:"
  find "${OUT_DIR}" -maxdepth 4 -type f -name "index.html" | head -n 30 || true
  exit 1
fi

echo "Mirror generated in: ${OUT_DIR}"
