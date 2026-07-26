#!/usr/bin/env bash
# Build Android release APKs for institute distribution.
#
# ⚠️  DO NOT run:  flutter build apk --release
#     That includes x86/x86_64 → ~127 MB and is NOT needed on real phones.
#
# Modes:
#   universal — ONE APK, 32+64-bit phones, under 100 MB (default; share with all institutes)
#   release   — ~88 MB, 64-bit only (Android 8+; smallest single file)
#   split     — ~52 MB + ~59 MB (smallest total; pick file per phone)
#   aab       — Play Store bundle
#
# RAM (2–8 GB): same APK works on all — RAM affects speed, not install size.
#
# Usage:
#   ./scripts/build_android_apk.sh
#   ./scripts/build_android_apk.sh universal

set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-universal}"

SYMBOLS_DIR="build/app/outputs/symbols"
RELEASE_FLAGS=(
  --release
  --obfuscate
  "--split-debug-info=${SYMBOLS_DIR}"
)

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: *//' | tr -d ' ')
OUT_NAME="MSCE_Attendance_${VERSION}_universal.apk"

flutter pub get

case "$MODE" in
  aab|bundle)
    echo "Building Play Store AAB (arm32 + arm64)..."
    flutter build appbundle --release "${RELEASE_FLAGS[@]}" \
      --target-platform android-arm,android-arm64
    ls -lh build/app/outputs/bundle/release/app-release.aab
    echo "Upload app-release.aab in Google Play Console."
    ;;
  under90|arm64|release)
    echo "Building arm64-only release APK (~88 MB, under 100 MB)..."
    flutter build apk "${RELEASE_FLAGS[@]}" --target-platform android-arm64
    APK="build/app/outputs/flutter-apk/app-release.apk"
    ls -lh "$APK"
    BYTES=$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK")
    if [ "$BYTES" -gt 104857600 ]; then
      echo "WARNING: APK is over 100 MB."
    else
      echo "OK: Under 100 MB — 64-bit phones (Android 8+)."
    fi
    ;;
  split)
    echo "Building per-CPU APKs (arm32 + arm64, no x86)..."
    flutter build apk "${RELEASE_FLAGS[@]}" --split-per-abi \
      --target-platform android-arm,android-arm64
    ls -lh build/app/outputs/flutter-apk/app-*-release.apk
    echo "Most phones: app-arm64-v8a-release.apk"
    echo "Old 32-bit-only: app-armeabi-v7a-release.apk"
    ;;
  universal|*)
    echo "Building universal APK (32-bit + 64-bit, no x86 emulator libs)..."
    flutter build apk "${RELEASE_FLAGS[@]}" \
      --target-platform android-arm,android-arm64
    APK="build/app/outputs/flutter-apk/app-release.apk"
    cp -f "$APK" "build/app/outputs/flutter-apk/${OUT_NAME}"
    ls -lh "$APK" "build/app/outputs/flutter-apk/${OUT_NAME}"
    BYTES=$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK")
    MB=$(echo "scale=1; $BYTES / 1048576" | bc)
    if [ "$BYTES" -gt 104857600 ]; then
      echo "WARNING: APK is ${MB} MB (over 100 MB)."
      echo "Try: ./scripts/build_android_apk.sh split  OR re-bundle anti-spoof models."
    else
      echo "OK: ${MB} MB — share build/app/outputs/flutter-apk/${OUT_NAME}"
      echo "Works on 2–8 GB RAM phones (same app; more RAM = smoother camera)."
    fi
    ;;
esac
