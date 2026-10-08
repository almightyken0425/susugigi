#!/usr/bin/env bash

set -u

scene=""
case_id=""
operation=""
seed=""

reject() {
  printf '%s\n' QA_FIXTURE_WRITE_POLICY_REJECTED >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || reject
  case "$1" in
    --scene)
      [ -z "$scene" ] || reject
      scene="$2"
      ;;
    --case)
      [ -z "$case_id" ] || reject
      case_id="$2"
      ;;
    --operation)
      [ -z "$operation" ] || reject
      operation="$2"
      ;;
    --seed)
      [ -z "$seed" ] || reject
      seed="$2"
      ;;
    *) reject ;;
  esac
  shift 2
done

case "$scene:$case_id:$operation:$seed" in
  R03:CS-02:prepare:r02_end|R13:RC-06:prepare:r09_stale_schedule)
    printf '%s\n' 'QA_FIXTURE_WRITE_POLICY remote=1 reseed=1'
    ;;
  R06:HD-07:prepare:r06_large_history|R06:HD-07:prepare:r06_large_history_cleanup)
    printf '%s\n' 'QA_FIXTURE_WRITE_POLICY remote=0 reseed=0'
    ;;
  *) reject ;;
esac
