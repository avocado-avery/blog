#!/usr/bin/env bash

# tools/new-post.sh: create a new Chirpy post from _templates/post-template.md
#
# Usage:
#   tools/new_post.sh YYYY-MM-DD-slug.md [--banner path/to/image.png]
#
# Creates:
#   _posts/YYYY-MM-DD-slug.md
#   assets/img/posts/slug/
#   assets/img/posts/slug/banner.*
# Without --banner, the template's image: block is removed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/_templates/post-template.md"

usage() {
  echo "Usage: $(basename "$0") YYYY-MM-DD-slug.md [--banner path/to/image]" >&2
  exit 1
}

die() { echo "Error: $*" >&2; exit 1; }

# --- parse args ---
FILE=""
BANNER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --banner)
      [[ $# -ge 2 ]] || die "--banner needs a path"
      BANNER="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) die "unknown option: $1" ;;
    *)
      [[ -z "$FILE" ]] || die "only one file name allowed"
      FILE="$(basename "$1")"; shift ;;
  esac
done
[[ -n "$FILE" ]] || usage

[[ "$FILE" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-([a-z0-9][a-z0-9-]*)\.md$ ]] \
  || die "file name must look like YYYY-MM-DD-some-title.md (lowercase letters, numbers, dashes)"
DATE="${BASH_REMATCH[1]}"
SLUG="${BASH_REMATCH[2]}"
date -d "$DATE" >/dev/null 2>&1 || die "$DATE is not a real date"

[[ -f "$TEMPLATE" ]] || die "template not found at $TEMPLATE"

POST="$ROOT/_posts/$FILE"
IMG_DIR="$ROOT/assets/img/posts/$SLUG"
[[ ! -e "$POST" ]] || die "$POST already exists"

if [[ -n "$BANNER" ]]; then
  [[ -f "$BANNER" ]] || die "banner not found: $BANNER"
  EXT="${BANNER##*.}"
  EXT="${EXT,,}"
  [[ "$EXT" =~ ^(png|jpg|jpeg|webp|gif)$ ]] || die "banner must be png, jpg, jpeg, webp or gif"
fi

mkdir -p "$ROOT/_posts" "$IMG_DIR"
cp "$TEMPLATE" "$POST"

sed -i "s|^date: .*|date: $DATE $(date +'%H:%M:%S %z')|" "$POST"

if [[ -n "$BANNER" ]]; then
  cp "$BANNER" "$IMG_DIR/banner.$EXT"
  sed -i "s|^  path: .*|  path: banner.$EXT|" "$POST"
else
  sed -i '/^image:/,/^  alt:/d' "$POST"
fi

echo "Created  _posts/$FILE"
echo "Images   assets/img/posts/$SLUG/"
[[ -n "$BANNER" ]] && echo "Banner   assets/img/posts/$SLUG/banner.$EXT"
echo "URL      /blog/posts/$SLUG/"
