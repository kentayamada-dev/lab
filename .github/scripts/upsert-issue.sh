#!/usr/bin/env bash
#
# Opens an issue titled <title>, or acts on the one already open under that title
# instead of opening a second one. This is how the scheduled workflows report a failing
# check; close-issues-by-title.sh retracts it once the check passes.
#
# What to do with an issue that is already open is the caller's choice, because the
# three workflows want different things out of it:
#   skip     leave it alone (the report would say the same thing again)
#   comment  add --comment-file to it (every run's output is worth keeping)
#   edit     replace its body with --body-file (only the latest state matters)
#
# The label is applied after creation rather than through gh issue create --label, so
# that a label that no longer exists costs a warning instead of the issue itself. An
# issue that was already open keeps whatever labels it has.
#
# Usage:
#   ./.github/scripts/upsert-issue.sh --title <title> --body-file <path> --label <label> \
#     --on-existing skip|comment|edit [--comment-file <path>]
#
# Environment variables:
#   GH_TOKEN  a token with issues write access (gh reads it itself)
#   GH_REPO   target repository (default: derived from the checkout)
#
set -euo pipefail

TITLE=""
BODY_FILE=""
COMMENT_FILE=""
LABEL=""
ON_EXISTING=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --body-file)
      BODY_FILE="${2:-}"
      shift 2
      ;;
    --comment-file)
      COMMENT_FILE="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --on-existing)
      ON_EXISTING="${2:-}"
      shift 2
      ;;
    -h | --help)
      awk 'NR>1 && !/^#/{exit} NR>1{sub(/^# ?/, ""); print}' "$0"
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$TITLE" || -z "$BODY_FILE" || -z "$LABEL" || -z "$ON_EXISTING" ]]; then
  echo "--title, --body-file, --label and --on-existing are all required" >&2
  exit 2
fi

case "$ON_EXISTING" in
  skip | edit)
    if [[ -n "$COMMENT_FILE" ]]; then
      echo "--comment-file applies to --on-existing comment only" >&2
      exit 2
    fi
    ;;
  comment)
    if [[ -z "$COMMENT_FILE" ]]; then
      echo "--on-existing comment needs --comment-file" >&2
      exit 2
    fi
    ;;
  *)
    echo "unknown --on-existing value: ${ON_EXISTING} (skip, comment or edit)" >&2
    exit 2
    ;;
esac

# Both files are checked before either is used, because only one of them is used per
# run: a --comment-file that is not there would otherwise go unnoticed until a run
# finds the issue already open. With no --comment-file the body file is checked twice.
for file in "$BODY_FILE" "${COMMENT_FILE:-$BODY_FILE}"; do
  if [[ ! -f "$file" ]]; then
    echo "no such file: $file" >&2
    exit 2
  fi
done

existing="$(gh issue list --state open --limit 100 --json number,title |
  jq -r --arg t "$TITLE" 'map(select(.title == $t)) | if length > 0 then .[0].number else empty end')"

if [[ -n "$existing" ]]; then
  case "$ON_EXISTING" in
    skip)
      echo "issue #${existing} already exists, not creating another"
      ;;
    comment)
      gh issue comment "$existing" --body-file "$COMMENT_FILE"
      echo "issue #${existing} already exists, added the latest output as a comment"
      ;;
    edit)
      gh issue edit "$existing" --body-file "$BODY_FILE"
      echo "updated the body of issue #${existing}"
      ;;
  esac
  exit 0
fi

url="$(gh issue create --title "$TITLE" --body-file "$BODY_FILE")"
gh issue edit "$url" --add-label "$LABEL" ||
  echo "::warning::Could not add the ${LABEL} label. Check whether it still exists (./scripts/sync-repo-config.sh can create it)"
