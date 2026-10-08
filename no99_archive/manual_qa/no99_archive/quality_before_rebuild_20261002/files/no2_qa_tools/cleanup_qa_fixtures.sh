#!/bin/bash

set -u

umask 077

if [ -n "$(declare -F)" ]; then
    printf '%s\n' 'QA fixture cleanup rejected' >&2
    exit 2
fi

CANONICAL_QA_PROJECT='susugigi-qa'
PRODUCTION_PROJECT='susugigi-c4fb1'
project=''
read_uid_from_stdin=0
case "$0" in
    */*) script_parent=${0%/*} ;;
    *) script_parent='.' ;;
esac
SCRIPT_DIR=$(cd -P -- "$script_parent" 2>/dev/null && pwd -P) || {
    printf '%s\n' 'QA fixture cleanup failed' >&2
    exit 1
}
DELETE_HELPER="$SCRIPT_DIR/delete_qa_fixture_subtree.py"
SYSTEM_ENV='/usr/bin/env'
SYSTEM_PYTHON='/usr/bin/python3'

reject_input() {
    printf '%s\n' 'QA fixture cleanup rejected' >&2
    exit 2
}

fail_closed() {
    printf '%s\n' 'QA fixture cleanup failed' >&2
    exit 1
}

trap 'exit 1' HUP INT TERM

for override_name in \
    FIRESTORE_EMULATOR_HOST \
    FIRESTORE_URL \
    FIREBASE_EMULATOR_HUB \
    FIREBASE_AUTH_EMULATOR_HOST \
    FIREBASE_AUTH_URL \
    FIREBASE_AUTHPROXY_URL \
    FIREBASE_AUTH_MANAGEMENT_URL \
    FIREBASE_IDENTITY_URL \
    FIREBASE_API_URL \
    FIREBASE_GOOGLE_URL \
    FIREBASE_TOKEN_URL \
    CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH \
    CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
    CLOUDSDK_PROXY_TYPE \
    CLOUDSDK_PROXY_ADDRESS \
    CLOUDSDK_PROXY_PORT \
    CLOUDSDK_PROXY_USERNAME \
    CLOUDSDK_PROXY_PASSWORD \
    CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
    CLOUDSDK_AUTH_TOKEN_HOST \
    CLOUDSDK_CONFIG \
    CLOUDSDK_ACTIVE_CONFIG_NAME \
    GCE_METADATA_HOST \
    GCE_METADATA_ROOT \
    GOOGLE_API_USE_MTLS_ENDPOINT \
    SSL_CERT_FILE \
    SSL_CERT_DIR \
    SSLKEYLOGFILE \
    REQUESTS_CA_BUNDLE \
    CURL_CA_BUNDLE \
    NODE_EXTRA_CA_CERTS \
    GRPC_DEFAULT_SSL_ROOTS_FILE_PATH \
    PYTHONPATH \
    PYTHONHOME \
    PYTHONSTARTUP \
    PYTHONINSPECT \
    PYTHONBREAKPOINT \
    BASH_ENV \
    ENV \
    DYLD_INSERT_LIBRARIES \
    DYLD_LIBRARY_PATH \
    LD_PRELOAD \
    LD_LIBRARY_PATH \
    HTTP_PROXY \
    HTTPS_PROXY \
    ALL_PROXY \
    http_proxy \
    https_proxy \
    all_proxy \
    NO_PROXY \
    no_proxy; do
    [ -z "${!override_name:-}" ] || reject_input
done

while [ "$#" -gt 0 ]; do
    case "$1" in
        --project)
            [ -z "$project" ] || reject_input
            [ "$#" -ge 2 ] || reject_input
            case "$2" in
                --*) reject_input ;;
            esac
            project="$2"
            shift 2
            ;;
        --session-uid-stdin)
            [ "$read_uid_from_stdin" -eq 0 ] || reject_input
            read_uid_from_stdin=1
            shift
            ;;
        *)
            reject_input
            ;;
    esac
done

[ "$project" != "$PRODUCTION_PROJECT" ] || reject_input
[ "$project" = "$CANONICAL_QA_PROJECT" ] || reject_input
[ "$read_uid_from_stdin" -eq 1 ] || reject_input

session_uid=''
IFS= read -r session_uid || reject_input
extra_input=''
IFS= read -r extra_input
extra_status=$?
if [ "$extra_status" -eq 0 ] || [ -n "$extra_input" ]; then
    reject_input
fi
if [[ ! "$session_uid" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
    reject_input
fi

[ -x "$SYSTEM_ENV" ] || fail_closed
[ -x "$SYSTEM_PYTHON" ] || fail_closed
[ -f "$DELETE_HELPER" ] && [ ! -L "$DELETE_HELPER" ] || fail_closed

printf '%s\n' "$session_uid" | \
    "$SYSTEM_ENV" -u FIRESTORE_EMULATOR_HOST \
        -u FIRESTORE_URL \
        -u FIREBASE_EMULATOR_HUB \
        -u FIREBASE_AUTH_EMULATOR_HOST \
        -u FIREBASE_AUTH_URL \
        -u FIREBASE_AUTHPROXY_URL \
        -u FIREBASE_AUTH_MANAGEMENT_URL \
        -u FIREBASE_IDENTITY_URL \
        -u FIREBASE_API_URL \
        -u FIREBASE_GOOGLE_URL \
        -u FIREBASE_TOKEN_URL \
        -u CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH \
        -u CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE \
        -u CLOUDSDK_PROXY_TYPE \
        -u CLOUDSDK_PROXY_ADDRESS \
        -u CLOUDSDK_PROXY_PORT \
        -u CLOUDSDK_PROXY_USERNAME \
        -u CLOUDSDK_PROXY_PASSWORD \
        -u CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE \
        -u CLOUDSDK_AUTH_TOKEN_HOST \
        -u CLOUDSDK_CONFIG \
        -u CLOUDSDK_ACTIVE_CONFIG_NAME \
        -u GCE_METADATA_HOST \
        -u GCE_METADATA_ROOT \
        -u GOOGLE_API_USE_MTLS_ENDPOINT \
        -u SSL_CERT_FILE \
        -u SSL_CERT_DIR \
        -u SSLKEYLOGFILE \
        -u REQUESTS_CA_BUNDLE \
        -u CURL_CA_BUNDLE \
        -u NODE_EXTRA_CA_CERTS \
        -u GRPC_DEFAULT_SSL_ROOTS_FILE_PATH \
        -u PYTHONPATH \
        -u PYTHONHOME \
        -u PYTHONSTARTUP \
        -u PYTHONINSPECT \
        -u PYTHONBREAKPOINT \
        -u BASH_ENV \
        -u ENV \
        -u SHELLOPTS \
        -u BASHOPTS \
        -u BASH_XTRACEFD \
        -u PS4 \
        -u DYLD_INSERT_LIBRARIES \
        -u DYLD_LIBRARY_PATH \
        -u LD_PRELOAD \
        -u LD_LIBRARY_PATH \
        -u HTTP_PROXY \
        -u HTTPS_PROXY \
        -u ALL_PROXY \
        -u http_proxy \
        -u https_proxy \
        -u all_proxy \
        -u NO_PROXY \
        -u no_proxy \
        PATH=/usr/bin:/bin \
        "$SYSTEM_PYTHON" -I "$DELETE_HELPER" \
        --project "$project" \
        --session-uid-stdin \
        >/dev/null 2>&1
delete_status=$?
session_uid=''

# Only fixed, documented statuses cross this boundary. Child output stays hidden.
case "$delete_status" in
    0) ;;
    20|21|22|24|25|26|27|75|76)
        printf '%s\n' 'QA fixture cleanup failed' >&2
        exit "$delete_status"
        ;;
    *) fail_closed ;;
esac
printf '%s\n' 'QA fixture cleanup completed'
