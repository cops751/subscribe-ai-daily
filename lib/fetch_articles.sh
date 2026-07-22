#!/usr/bin/env bash
# Fetch one source; emit NDJSON article lines to stdout.
# For method=fetch (JS-rendered SPA), emit a marker JSON for the host LLM to WebFetch.
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

fetch_source() {
  local src="$1"
  local url method category selector
  url=$(echo "$src" | jq -r '.url')
  method=$(echo "$src" | jq -r '.method')
  category=$(echo "$src" | jq -r '.category // "blog"')
  selector=$(echo "$src" | jq -r '.selector // ""')

  case "$method" in
    rss)
      local tmp
      tmp=$(mktemp)
      curl -fsSL -H "User-Agent: $UA" --max-time 20 "$url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
      # Parse <item>/<entry>: title, link, pubDate/updated
      python3 - "$tmp" "$category" <<'PY'
import sys, re, json, html
from xml.etree import ElementTree as ET
path, category = sys.argv[1], sys.argv[2]
try:
    tree = ET.parse(path)
except Exception:
    sys.exit(0)
root = tree.getroot()
ns = {'a':'http://www.w3.org/2005/Atom'}
items = root.findall('.//item')
if not items: items = root.findall('.//a:entry', ns)
for it in items:
    def g(tag):
        el = it.find(tag)
        if el is None: el = it.find('a:'+tag, ns)
        return (el.text or '').strip() if el is not None else ''
    title = g('title')
    link = g('link')
    if not link:
        le = it.find('a:link', ns)
        if le is not None: link = le.get('href','')
    pub = g('pubDate') or g('updated') or g('published')
    print(json.dumps({'title':title,'url':link,'pubDate':pub,'category':category,'excerpt':''}))
PY
      rm -f "$tmp"
      ;;
    html)
      local tmp
      tmp=$(mktemp)
      curl -fsSL -H "User-Agent: $UA" --max-time 20 "$url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
      python3 - "$tmp" "$url" "$category" "$selector" <<'PY'
import sys, json, re
from html.parser import HTMLParser
path, base_url, category, selector = sys.argv[1:5]
href_prefix = re.match(r'a\[href\^="([^"]+)"', selector)
prefix = href_prefix.group(1) if href_prefix else ''
with open(path, encoding='utf-8', errors='ignore') as f:
    html_txt = f.read()
# Crude anchor extraction: href matching prefix, anchor text as title
pat = re.compile(r'<a[^>]+href="(' + re.escape(prefix) + r'[^"]*)"[^>]*>(.*?)</a>', re.S)
seen = set()
for m in pat.finditer(html_txt):
    href, inner = m.group(1), re.sub(r'<[^>]+>','', m.group(2))
    title = re.sub(r'\s+',' ', inner).strip()
    if not title or href in seen: continue
    seen.add(href)
    if href.startswith('/'):
        from urllib.parse import urljoin
        href = urljoin(base_url, href)
    print(json.dumps({'title':title,'url':href,'pubDate':'','category':category,'excerpt':''}))
PY
      rm -f "$tmp"
      ;;
    fetch)
      # Marker: host LLM will WebFetch url and extract articles itself.
      echo "{\"title\":\"\",\"url\":\"$url\",\"pubDate\":\"\",\"category\":\"$category\",\"method\":\"fetch\"}"
      ;;
    *)
      echo "ERROR: unknown method $method" >&2
      ;;
  esac
}
