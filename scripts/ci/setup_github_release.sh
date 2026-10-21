#!/usr/bin/env bash
# One-time GitHub setup for the mobile and desktop release workflows
# (.github/workflows/mobile-release.yml here, desktop-release.yml in
# Chessever/chessever_frontend_desktop). Read docs/ci/github-actions-release.md
# first.
#
#   scripts/ci/setup_github_release.sh <values-dir>           # plan only
#   scripts/ci/setup_github_release.sh <values-dir> --apply   # write to GitHub
#
# <values-dir> is a private directory outside every git checkout holding one
# file per value: the file name is the GitHub secret name, the content is the
# value.
#
#   org-shared/       organization secrets for both repositories
#   org-mobile/       organization secrets for chessever-frontend only
#   org-desktop/      organization secrets for chessever_frontend_desktop only
#   release-mobile/   `release` environment secrets, chessever-frontend
#   release-desktop/  `release` environment secrets, chessever_frontend_desktop
#
# For names ending in _B64, drop in the raw file (keystore, .p12, plist, json);
# the script encodes it. Values go to `gh` on stdin and are never printed.
#
# Needs `gh` logged in with the admin:org scope
# (gh auth refresh -h github.com -s admin:org) and admin on both repositories.
set -euo pipefail

ORG=Chessever
MOBILE_REPO=chessever-frontend
DESKTOP_REPO=chessever_frontend_desktop
ENVIRONMENT=release
MOBILE_RELEASE_BRANCH=stable
DESKTOP_RELEASE_BRANCH=main
# GitHub logins allowed to approve a release job. Override with
# RELEASE_REVIEWERS="login1 login2" (at most six).
read -r -a REVIEWERS <<< "${RELEASE_REVIEWERS:-devberkay}"

# Values compiled into the shipped apps. Codemagic held them as non-secure
# variables; they become organization variables, not secrets.
CLOUDFLARE_API_BASE=https://chessever-cloudflare.young-sun-69a8.workers.dev
GOOGLE_WEB_CLIENT_ID=882734779574-4pttdbmj67d2044ag6kcq9n3rsao6k29.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=882734779574-8v68and9jcueedkvk0dl2ftse6dn8kt3.apps.googleusercontent.com

# group | required names | optional names
VALUE_GROUPS=(
  "org-shared|SUPABASE_URL SUPABASE_ANON_KEY SENTRY_FLUTTER|"
  "org-mobile|REVENUECAT_API_KEY AMPLITUDE CLARITY_PROJECT_ID ONESIGNAL_APP_ID APPSFLYER_DEV_KEY GAMEBASE_API_KEY GOOGLE_SERVICES_JSON_B64 GOOGLE_SERVICE_INFO_PLIST_B64|"
  "org-desktop|GOOGLE_DESKTOP_CLIENT_ID GOOGLE_DESKTOP_CLIENT_SECRET|"
  "release-mobile|ANDROID_KEYSTORE_B64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_PASSWORD GOOGLE_PLAY_SERVICE_ACCOUNT_JSON APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY IOS_DISTRIBUTION_CERTIFICATE_KEY|"
  "release-desktop|APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY MACOS_DEVELOPER_ID_P12_B64 MACOS_DEVELOPER_ID_P12_PASSWORD R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID|R2_BUCKET SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT"
)

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit "${1:-0}"
}

VALUES_DIR=""
APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h | --help) usage ;;
    -*) die "unknown option $arg" ;;
    *)
      [ -z "$VALUES_DIR" ] || die "only one values directory"
      VALUES_DIR="$arg"
      ;;
  esac
done
[ -n "$VALUES_DIR" ] || usage 1
[ -d "$VALUES_DIR" ] || die "$VALUES_DIR is not a directory"
VALUES_DIR="$(cd "$VALUES_DIR" && pwd)"

if git -C "$VALUES_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  die "$VALUES_DIR is inside a git checkout; keep release values outside every repository"
fi
if [ "$(uname)" = Darwin ]; then
  mode="$(stat -f '%Lp' "$VALUES_DIR")"
else
  mode="$(stat -c '%a' "$VALUES_DIR")"
fi
if [ "$mode" != "700" ]; then
  echo "warning: $VALUES_DIR is mode $mode; run: chmod -R go-rwx '$VALUES_DIR'" >&2
fi

# Cheap shape checks so a swapped file fails here, not halfway through a
# release. They read the file but never print it.
check_shape() {
  local name="$1" file="$2"
  case "$name" in
    APP_STORE_CONNECT_PRIVATE_KEY | IOS_DISTRIBUTION_CERTIFICATE_KEY)
      grep -q -- '-----BEGIN .*PRIVATE KEY-----' "$file" || {
        echo "PEM private key expected"
        return
      }
      ;;
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON)
      python3 -I -c 'import json,sys; assert json.load(open(sys.argv[1]))["type"] == "service_account"' "$file" 2> /dev/null || {
        echo "service-account JSON expected"
        return
      }
      ;;
    GOOGLE_SERVICES_JSON_B64)
      python3 -I -c 'import json,sys; assert "project_info" in json.load(open(sys.argv[1]))' "$file" 2> /dev/null || {
        echo "raw google-services.json expected"
        return
      }
      ;;
    GOOGLE_SERVICE_INFO_PLIST_B64)
      plutil -lint "$file" > /dev/null 2>&1 || {
        echo "raw GoogleService-Info.plist expected"
        return
      }
      ;;
    *_B64) ;;
    *)
      if [ "$(wc -l < "$file" | tr -d ' ')" -gt 1 ]; then
        echo "single-line value expected"
        return
      fi
      ;;
  esac
}

missing=0
invalid=0
echo "Values directory: $VALUES_DIR"
for group in "${VALUE_GROUPS[@]}"; do
  IFS='|' read -r dir required optional <<< "$group"
  echo
  echo "$dir/"
  for name in $required $optional; do
    file="$VALUES_DIR/$dir/$name"
    kind=required
    case " $optional " in *" $name "*) kind=optional ;; esac
    if [ ! -s "$file" ]; then
      if [ "$kind" = required ]; then
        status="MISSING"
        missing=1
      else
        status="not set (optional)"
      fi
    else
      problem="$(check_shape "$name" "$file")"
      if [ -n "$problem" ]; then
        status="INVALID: $problem"
        invalid=1
      else
        status="ok"
      fi
    fi
    printf '  %-34s %s\n' "$name" "$status"
  done
  if [ -d "$VALUES_DIR/$dir" ]; then
    for file in "$VALUES_DIR/$dir"/*; do
      [ -e "$file" ] || continue
      name="$(basename "$file")"
      case " $required $optional " in
        *" $name "*) ;;
        *) printf '  %-34s %s\n' "$name" "UNEXPECTED (typo?) - ignored" ;;
      esac
    done
  fi
done

echo
echo "Organization variables (public values, also in the shipped apps):"
echo "  CHESSEVER_CLOUDFLARE_API_BASE  -> $MOBILE_REPO, $DESKTOP_REPO"
echo "  GOOGLE_WEB_CLIENT_ID           -> $MOBILE_REPO"
echo "  GOOGLE_IOS_CLIENT_ID           -> $MOBILE_REPO"
echo
echo "Environment '$ENVIRONMENT': $MOBILE_REPO deploys from '$MOBILE_RELEASE_BRANCH',"
echo "$DESKTOP_REPO from '$DESKTOP_RELEASE_BRANCH'; reviewers: ${REVIEWERS[*]}"

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "Plan only. Re-run with --apply to write to GitHub."
  exit 0
fi

[ "$missing" -eq 0 ] || die "required values are missing (see above)"
[ "$invalid" -eq 0 ] || die "some values do not look right (see above)"
command -v gh > /dev/null || die "gh is not installed"
gh api "orgs/$ORG/actions/secrets?per_page=1" > /dev/null 2>&1 ||
  die "gh cannot manage $ORG organization secrets; it needs an org admin and: gh auth refresh -h github.com -s admin:org"

org_repos() {
  case "$1" in
    org-shared) echo "$MOBILE_REPO,$DESKTOP_REPO" ;;
    org-mobile) echo "$MOBILE_REPO" ;;
    org-desktop) echo "$DESKTOP_REPO" ;;
  esac
}

sorted_csv() {
  tr ',' '\n' | LC_ALL=C sort | paste -sd, -
}

# Current scope of an organization secret or variable: empty when it does not
# exist, the sorted repository list when it is "selected", otherwise
# "visibility:<all|private>".
org_scope() {
  local kind="$1" name="$2" visibility
  visibility="$(gh api "orgs/$ORG/actions/$kind/$name" --jq .visibility 2> /dev/null)" || return 0
  if [ "$visibility" = selected ]; then
    gh api --paginate "orgs/$ORG/actions/$kind/$name/repositories" --jq '.repositories[].name' |
      LC_ALL=C sort | paste -sd, -
  else
    echo "visibility:$visibility"
  fi
}

# Organization names are shared by every repository in the org, and setting
# one replaces both its value and its repository list. Refuse to touch a name
# that already exists with another scope; a rerun of this script finds exactly
# its own scope and carries on.
planned=(
  "variables|CHESSEVER_CLOUDFLARE_API_BASE|$MOBILE_REPO,$DESKTOP_REPO"
  "variables|GOOGLE_WEB_CLIENT_ID|$MOBILE_REPO"
  "variables|GOOGLE_IOS_CLIENT_ID|$MOBILE_REPO"
)
for group in "${VALUE_GROUPS[@]}"; do
  IFS='|' read -r dir required optional <<< "$group"
  case "$dir" in org-*) ;; *) continue ;; esac
  for name in $required $optional; do
    if [ -s "$VALUES_DIR/$dir/$name" ]; then
      planned+=("secrets|$name|$(org_repos "$dir")")
    fi
  done
done
clashes=0
for item in "${planned[@]}"; do
  IFS='|' read -r kind name repos <<< "$item"
  current="$(org_scope "$kind" "$name")"
  if [ -n "$current" ] && [ "$current" != "$(sorted_csv <<< "$repos")" ]; then
    echo "error: organization ${kind%s} $name already exists, scope: $current" >&2
    clashes=1
  fi
done
if [ "$clashes" -ne 0 ]; then
  die "nothing was changed. Check what uses the names above, delete them under
Organization settings -> Secrets and variables -> Actions, then run again."
fi

secret_value() {
  local name="$1" file="$2"
  case "$name" in
    *_B64) base64 < "$file" | tr -d '\n' ;;
    *) printf '%s' "$(cat "$file")" ;;
  esac
}

set_org_secret() {
  local name="$1" file="$2" repos="$3"
  secret_value "$name" "$file" |
    gh secret set "$name" --org "$ORG" --visibility selected --repos "$repos" > /dev/null
  echo "  org secret $name -> $repos"
}

set_env_secret() {
  local name="$1" file="$2" repo="$3"
  secret_value "$name" "$file" |
    gh secret set "$name" --repo "$ORG/$repo" --env "$ENVIRONMENT" > /dev/null
  echo "  $repo/$ENVIRONMENT secret $name"
}

# Environment body; $1 adds extra JSON fields. Reads reviewers_json from the
# caller.
environment_body() {
  cat << JSON
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [${reviewers_json%,}],
  "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}$1
}
JSON
}

bypass_left_on=()
configure_environment() {
  local repo="$1" branch="$2" ids=() reviewers_json existing bypass
  for login in "${REVIEWERS[@]}"; do
    ids+=("$(gh api "users/$login" --jq .id)")
  done
  reviewers_json="$(printf '{"type":"User","id":%s},' "${ids[@]}")"
  # `can_admins_bypass` is not in the documented REST schema, so fall back to
  # the documented body if GitHub rejects it, and check the result below.
  if ! environment_body ', "can_admins_bypass": false' |
    gh api -X PUT "repos/$ORG/$repo/environments/$ENVIRONMENT" --input - > /dev/null 2>&1; then
    environment_body "" |
      gh api -X PUT "repos/$ORG/$repo/environments/$ENVIRONMENT" --input - > /dev/null
  fi
  existing="$(gh api "repos/$ORG/$repo/environments/$ENVIRONMENT/deployment-branch-policies" \
    --jq '.branch_policies[] | select(.type == "branch") | .name')"
  if ! grep -qx "$branch" <<< "$existing"; then
    gh api -X POST "repos/$ORG/$repo/environments/$ENVIRONMENT/deployment-branch-policies" \
      -f name="$branch" -f type=branch > /dev/null
  fi
  bypass="$(gh api "repos/$ORG/$repo/environments/$ENVIRONMENT" --jq '.can_admins_bypass')"
  [ "$bypass" = "false" ] || bypass_left_on+=("$repo")
  echo "  $repo: environment '$ENVIRONMENT' (branch $branch, reviewers ${REVIEWERS[*]}, admin bypass $bypass)"
}

echo
echo "Applying..."
gh variable set CHESSEVER_CLOUDFLARE_API_BASE --org "$ORG" --visibility selected \
  --repos "$MOBILE_REPO,$DESKTOP_REPO" --body "$CLOUDFLARE_API_BASE"
gh variable set GOOGLE_WEB_CLIENT_ID --org "$ORG" --visibility selected \
  --repos "$MOBILE_REPO" --body "$GOOGLE_WEB_CLIENT_ID"
gh variable set GOOGLE_IOS_CLIENT_ID --org "$ORG" --visibility selected \
  --repos "$MOBILE_REPO" --body "$GOOGLE_IOS_CLIENT_ID"
echo "  organization variables set"

configure_environment "$MOBILE_REPO" "$MOBILE_RELEASE_BRANCH"
configure_environment "$DESKTOP_REPO" "$DESKTOP_RELEASE_BRANCH"

for group in "${VALUE_GROUPS[@]}"; do
  IFS='|' read -r dir required optional <<< "$group"
  for name in $required $optional; do
    file="$VALUES_DIR/$dir/$name"
    [ -s "$file" ] || continue
    case "$dir" in
      org-*) set_org_secret "$name" "$file" "$(org_repos "$dir")" ;;
      release-mobile) set_env_secret "$name" "$file" "$MOBILE_REPO" ;;
      release-desktop) set_env_secret "$name" "$file" "$DESKTOP_REPO" ;;
    esac
  done
done

echo
if [ "${#bypass_left_on[@]}" -eq 0 ]; then
  echo "Done. Admins cannot bypass the '$ENVIRONMENT' environment in either repository."
else
  echo "Done. GitHub kept admin bypass on for: ${bypass_left_on[*]}. In each, open"
  echo "Settings -> Environments -> $ENVIRONMENT and untick"
  echo "\"Allow administrators to bypass configured protection rules\"."
fi
