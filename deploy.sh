#!/usr/bin/env bash
# Деплой сайта «Сколько баксов» на Cloudflare:
#   1) сжимает видео (если riba.mp4 ещё нет)
#   2) создаёт R2-бакет и заливает туда видео
#   3) включает публичную ссылку r2.dev и подставляет её в сайт
#   4) создаёт проект Cloudflare Pages и публикует сайт
#
# Нужно один раз: Node.js и ffmpeg, затем `npx wrangler login`.
# Запуск из папки сайта:  bash deploy.sh
set -euo pipefail

BUCKET="skolko-baksov-video"
PROJECT="skolko-baksov"
SRC_VIDEO="${1:-CONCEPT.mp4}"   # исходник, если нужно сжать заново

# 1. Сжатие: 1280p, H.264, faststart (видео начинает играть до полной загрузки)
if [ ! -f riba.mp4 ]; then
  echo "→ Сжимаю $SRC_VIDEO"
  ffmpeg -y -i "$SRC_VIDEO" -vf "scale=1280:-2" \
    -c:v libx264 -preset slow -crf 26 -maxrate 1200k -bufsize 2400k -pix_fmt yuv420p \
    -c:a aac -b:a 128k -ac 2 -movflags +faststart riba.mp4
fi

# 2. R2-бакет и загрузка видео
echo "→ Создаю R2-бакет $BUCKET"
npx wrangler r2 bucket create "$BUCKET" || echo "  (бакет уже есть, продолжаю)"

echo "→ Заливаю видео в R2"
npx wrangler r2 object put "$BUCKET/riba.mp4" --file riba.mp4 \
  --content-type video/mp4 --cache-control "public, max-age=31536000, immutable" --remote

# 3. Публичная ссылка r2.dev
echo "→ Включаю публичный доступ r2.dev"
npx wrangler r2 bucket dev-url enable "$BUCKET" -y || true
R2_URL=$(npx wrangler r2 bucket dev-url get "$BUCKET" | grep -oE 'https://pub-[a-z0-9]+\.r2\.dev' | head -1)
if [ -z "$R2_URL" ]; then
  echo "Не удалось получить ссылку r2.dev. Включи Public access у бакета в дашборде Cloudflare и запусти скрипт ещё раз."
  exit 1
fi
echo "  Видео: $R2_URL/riba.mp4"

# 4. Сборка папки для Pages (видео не кладём, оно в R2)
rm -rf dist && mkdir dist
cp index.html hero.jpg casino.jpg shot-on-iphone.svg dist/
sed -i.bak "s#src=\"riba.mp4\"#src=\"$R2_URL/riba.mp4\"#" dist/index.html && rm -f dist/index.html.bak

echo "→ Публикую на Cloudflare Pages"
npx wrangler pages project create "$PROJECT" --production-branch main || echo "  (проект уже есть, продолжаю)"
npx wrangler pages deploy dist --project-name "$PROJECT" --branch main

echo "Готово. Сайт: https://$PROJECT.pages.dev"
