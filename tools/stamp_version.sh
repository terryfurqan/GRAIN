#!/usr/bin/env bash
# stamp_version.sh — tulis GRAIN/VERSION.txt untuk keterangan versi di title bar GUI.
#
#   Format: "<hash> | build <yyyy-MM-dd HH:mm>"
#     hash        = commit HEAD saat ini (parent dari commit yang akan dibuat)
#     build-time  = kapan stamp dijalankan (= saat commit dibuat)
#
#   TUJUAN: user bisa cek "PC-2 sudah versi terbaru atau belum" dengan
#   membandingkan build-time / hash di title bar. GUI membaca berkas ini (INSTAN,
#   tanpa memanggil git) lewat pivui.grainVersion -> tak ada risiko hang saat window
#   dibuka. PC-2 (git reset --hard origin/main) selalu dapat VERSION.txt terbaru.
#
#   PAKAI: jalankan MANUAL tepat sebelum commit (bukan git hook otomatis):
#     GRAIN/tools/stamp_version.sh && git add GRAIN/VERSION.txt && git commit ...
set -e
cd "$(dirname "$0")/.."          # -> folder GRAIN
hash="$(git rev-parse --short HEAD 2>/dev/null || echo '-------')"
now="$(date '+%Y-%m-%d %H:%M')"
printf '%s | build %s\n' "$hash" "$now" > VERSION.txt
echo "[stamp] GRAIN/VERSION.txt = $hash | build $now"
