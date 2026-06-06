#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$HOME/Desktop"
PUBLIC="$ROOT_DIR/public"

command -v ffmpeg >/dev/null || {
  echo "需要先安装 ffmpeg: brew install ffmpeg" >&2
  exit 1
}
command -v sips >/dev/null || {
  echo "需要 sips (macOS 自带)。当前不是 macOS 环境?" >&2
  exit 1
}

SRC_VIDEO="$SRC_DIR/录屏2026-06-06 18.28.43.mov"

if [[ ! -f "$SRC_VIDEO" ]]; then
  echo "未找到源视频: $SRC_VIDEO" >&2
  exit 1
fi

mkdir -p "$PUBLIC/screenshots"

echo "=== Compressing hero video (mp4) ==="
ffmpeg -y -i "$SRC_VIDEO" \
  -vf "scale=1920:-2,fps=30" \
  -c:v libx264 -preset slow -crf 24 \
  -movflags +faststart \
  -an \
  "$PUBLIC/hero-demo.mp4"

echo "=== Compressing hero video (webm) ==="
ffmpeg -y -i "$SRC_VIDEO" \
  -vf "scale=1920:-2,fps=30" \
  -c:v libvpx-vp9 -crf 32 -b:v 0 \
  -an \
  "$PUBLIC/hero-demo.webm"

echo "=== Generating hero poster ==="
ffmpeg -y -i "$SRC_VIDEO" \
  -ss 1 -frames:v 1 \
  -vf "scale=1920:-2" \
  -q:v 3 \
  "$PUBLIC/hero-demo-poster.jpg"

SHOTS=(
  "截屏2026-06-06 14.31.09.png:hero-main-window.png"
  "截屏2026-06-06 14.29.52.png:scenario1-overlay.png"
  "截屏2026-06-06 10.52.08.png:scenario1-alt.png"
  "截屏2026-06-06 11.30.04.png:scenario1-zec-detail.png"
  "截屏2026-06-06 10.52.12.png:scenario2-intent.png"
  "截屏2026-06-06 14.31.35.png:module-research.png"
  "截屏2026-06-06 14.30.47.png:module-risk.png"
  "截屏2026-06-06 14.30.36.png:module-floating.png"
)

echo "=== Compressing screenshots ==="
for pair in "${SHOTS[@]}"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  if [[ ! -f "$SRC_DIR/$src" ]]; then
    echo "  跳过 (源不存在): $src"
    continue
  fi
  sips -s format png -Z 2400 \
       "$SRC_DIR/$src" \
       --out "$PUBLIC/screenshots/$dst" \
       >/dev/null
  echo "  $src -> screenshots/$dst"
done

echo "=== Generating OG image ==="
if [[ -f "$PUBLIC/screenshots/hero-main-window.png" ]]; then
  sips -c 630 1200 \
       "$PUBLIC/screenshots/hero-main-window.png" \
       --out "$PUBLIC/og-image.png" \
       >/dev/null
fi

echo ""
echo "=== Output ==="
ls -lh "$PUBLIC/hero-demo".{mp4,webm} "$PUBLIC/hero-demo-poster.jpg" "$PUBLIC/og-image.png" 2>/dev/null || true
echo ""
ls -lh "$PUBLIC/screenshots/"
