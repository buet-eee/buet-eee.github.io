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
# Some assets may return 404/403 intermittently; do not abort solely on those.
set +e

#wget --continue --no-verbose --retry-connrefused --waitretry=2 --timeout=30 --tries=3 $URL || echo "Warning: $URL not found, skipping."
wget \
  --mirror \
  --page-requisites \
  --continue \
  --retry-connrefused \
  --waitretry=2 \
  --tries=3 \
  --convert-links \
  --adjust-extension \
  --no-parent \
  --execute robots=off \
  --domains="${HOST}" \
  --timeout=60 \
  --tries=3 \
  --random-wait \
  --wait=2 \
  --server-response \
  --content-on-error \
  --directory-prefix="${OUT_DIR}" \
  "${SITE_URL}"
WGET_RC=$?
set -e
# Move content to Pages root (wget typically creates public/eee.buet.ac.bd/...)
if [ -d "${OUT_DIR}/${HOST}" ]; then
  shopt -s dotglob
  mv "${OUT_DIR}/${HOST}/"* "${OUT_DIR}/"
  rmdir "${OUT_DIR}/${HOST}" || true
  shopt -u dotglob
fi

# Defensive robots.txt (meta noindex is the real control)
cat > "${OUT_DIR}/robots.txt" <<'EOF'
User-agent: *
Disallow: /
EOF

# Hard fail if we do not have a homepage
if [ ! -f "${OUT_DIR}/index.html" ]; then
  echo "Error: ${OUT_DIR}/index.html not found after mirroring."
  echo "Debug: listing possible index.html files:"
  find "${OUT_DIR}" -maxdepth 4 -type f -name "index.html" | head -n 30 || true
  exit 1
fi

# Post-process HTML safely (no sed). Inject:
# - <meta name="robots" content="noindex, nofollow">
# - <link rel="canonical" href="https://eee.buet.ac.bd/">
# - Banner right after <body ...> (once)
python3 - <<'PY'
import os, re, sys

out_dir = os.environ.get("OUT_DIR", "public")
primary_url = os.environ.get("PRIMARY_URL", "https://eee.buet.ac.bd/")
banner_html = os.environ.get("BANNER_HTML", "").strip("\n")

robots_meta = '<meta name="robots" content="noindex, nofollow">'
canonical = f'<link rel="canonical" href="{primary_url}">'

head_re = re.compile(r"<head\b[^>]*>", re.IGNORECASE)
body_re = re.compile(r"<body\b[^>]*>", re.IGNORECASE)

def inject_once(html: str) -> str:
    # Inject into <head>
    m = head_re.search(html)
    if m:
        head_tag = m.group(0)
        insert_lines = []
        if not re.search(r'<meta\s+name=["\']robots["\']', html, re.IGNORECASE):
            insert_lines.append(robots_meta)
        if not re.search(r'<link\s+rel=["\']canonical["\']', html, re.IGNORECASE):
            insert_lines.append(canonical)
        if insert_lines:
            injected = head_tag + "\n" + "\n".join(insert_lines)
            html = html[:m.start()] + injected + html[m.end():]

    # Inject banner into <body>
    if banner_html and not re.search(r'data-mirror-banner=["\']1["\']', html, re.IGNORECASE):
        m2 = body_re.search(html)
        if m2:
            body_tag = m2.group(0)
            injected_body = body_tag + "\n" + banner_html + "\n"
            html = html[:m2.start()] + injected_body + html[m2.end():]

    return html

count = 0
for root, _, files in os.walk(out_dir):
    for fn in files:
        if not fn.lower().endswith(".html"):
            continue
        path = os.path.join(root, fn)
        try:
            with open(path, "rb") as f:
                data = f.read()
            # Try utf-8; fall back to latin-1 to avoid crashing on odd encodings
            try:
                text = data.decode("utf-8")
                enc = "utf-8"
            except UnicodeDecodeError:
                text = data.decode("latin-1")
                enc = "latin-1"

            new_text = inject_once(text)
            if new_text != text:
                with open(path, "wb") as f:
                    f.write(new_text.encode(enc, errors="replace"))
            count += 1
        except Exception as e:
            print(f"Warning: failed to process {path}: {e}", file=sys.stderr)

print(f"Injected SEO tags + banner into {count} HTML files.")
PY
# pass variables to python via environment
export OUT_DIR PRIMARY_URL BANNER_HTML

# Optional: if wget failed with anything other than 0 or 8, fail the job
# (0 = perfect, 8 = some HTTP errors but usually usable mirror)
if [ "${WGET_RC}" -ne 0 ] && [ "${WGET_RC}" -ne 8 ]; then
  echo "wget failed with exit code ${WGET_RC}; refusing to deploy."
  exit 1
fi

echo "Mirror generated in: ${OUT_DIR}"