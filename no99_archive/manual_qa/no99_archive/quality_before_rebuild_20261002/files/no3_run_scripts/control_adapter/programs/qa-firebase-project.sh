#!/usr/bin/env bash
set -euo pipefail

QA_PLIST=""
QA_BUNDLE_ID=""
QA_GOOGLE_APP_ID=""
QA_FIREBASE_CONFIG_SHA256=""
ALLOWED_QA_GOOGLE_APP_ID="1:352034825841:ios:40c5c3bcfa630b4a6a1dd0"
ALLOWED_QA_FIREBASE_CONFIG_SHA256="8a349abb287abc45a2e4ad868d1fd93b373f4f878fe03aa4e805e97c31ac489f"

usage() {
  echo "usage: qa-firebase-project.sh --qa-plist PATH --qa-bundle-id ID --qa-google-app-id ID --qa-firebase-config-sha256 SHA256" >&2
  exit 2
}

fail() {
  echo "$1" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --qa-plist)
      [ -n "${2:-}" ] || usage
      QA_PLIST="$2"
      shift 2
      ;;
    --qa-bundle-id)
      [ -n "${2:-}" ] || usage
      QA_BUNDLE_ID="$2"
      shift 2
      ;;
    --qa-google-app-id)
      [ -n "${2:-}" ] || usage
      QA_GOOGLE_APP_ID="$2"
      shift 2
      ;;
    --qa-firebase-config-sha256)
      [ -n "${2:-}" ] || usage
      QA_FIREBASE_CONFIG_SHA256="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[ -n "$QA_PLIST" ] || usage
[ -n "$QA_BUNDLE_ID" ] || usage
[ -n "$QA_GOOGLE_APP_ID" ] || usage
[ -n "$QA_FIREBASE_CONFIG_SHA256" ] || usage
[ ! -L "$QA_PLIST" ] || fail "QA Firebase plist 不得為 symlink"
[ -f "$QA_PLIST" ] || fail "QA Firebase plist 不存在"
command -v plutil >/dev/null 2>&1 || fail "plutil 不存在"
command -v shasum >/dev/null 2>&1 || fail "shasum 不存在"

plist_value() {
  plutil -extract "$1" raw -o - "$2" 2>/dev/null || true
}

QA_PROJECT_ID="$(plist_value PROJECT_ID "$QA_PLIST")"
PLIST_BUNDLE_ID="$(plist_value BUNDLE_ID "$QA_PLIST")"
PLIST_GOOGLE_APP_ID="$(plist_value GOOGLE_APP_ID "$QA_PLIST")"
PLIST_SHA256="$(shasum -a 256 "$QA_PLIST" | awk '{print $1}')"

[ -n "$QA_PROJECT_ID" ] || fail "QA Firebase PROJECT_ID 為空"
[ "$QA_PROJECT_ID" != "susugigi-c4fb1" ] || fail "QA Firebase PROJECT_ID 不得為 Production project"
[ "$QA_PROJECT_ID" = "susugigi-qa" ] || fail "QA Firebase PROJECT_ID 必須為 susugigi-qa"
[ "$PLIST_BUNDLE_ID" = "$QA_BUNDLE_ID" ] || fail "QA Firebase BUNDLE_ID 不符"
[ -n "$PLIST_GOOGLE_APP_ID" ] || fail "QA Firebase GOOGLE_APP_ID 為空"
[ "$QA_GOOGLE_APP_ID" = "$ALLOWED_QA_GOOGLE_APP_ID" ] || fail "QA Google app id 必須為 allowlist 值"
[ "$PLIST_GOOGLE_APP_ID" = "$QA_GOOGLE_APP_ID" ] || fail "QA Firebase GOOGLE_APP_ID 不符"
[ "$QA_FIREBASE_CONFIG_SHA256" = "$ALLOWED_QA_FIREBASE_CONFIG_SHA256" ] || fail "QA Firebase config SHA-256 必須為 allowlist 值"
[ "$PLIST_SHA256" = "$QA_FIREBASE_CONFIG_SHA256" ] || fail "QA Firebase config SHA-256 不符"
case "$QA_BUNDLE_ID" in
  *.qa) ;;
  *) fail "QA bundle id 必須以 .qa 結尾" ;;
esac

printf '%s\n' "$QA_PROJECT_ID"
