#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK پیدا نشد. ابتدا Flutter را نصب و به PATH اضافه کنید."
  exit 1
fi
flutter create --platforms=android --org com.hamedhn --project-name darma "$TMP/darma" >/dev/null
mkdir -p "$ROOT/android"
cp -R "$TMP/darma/android/." "$ROOT/android/"
cp "$TMP/darma/.metadata" "$ROOT/.metadata"
echo "پوشه Android ساخته شد. حالا در ریشه پروژه اجرا کنید: flutter pub get"
