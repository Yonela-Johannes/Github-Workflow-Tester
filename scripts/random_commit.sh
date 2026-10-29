#!/usr/bin/env bash
# random_commit.sh
# Appends random entries to the configured files, commits each entry and pushes
# the result. Designed to run unattended from GitHub Actions, so it errs on the
# side of failing loudly instead of hanging.

set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  # Logging must never break the run (e.g. read-only checkout)
  { echo "$msg" >> "$SCRIPT_DIR/$DEBUG_LOG"; } 2>/dev/null || true
}

error() {
  local msg="[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" >&2
  { echo "$msg" >> "$SCRIPT_DIR/$DEBUG_LOG"; } 2>/dev/null || true
}



# ---------------------------------------------------------------------------
# Load and validate configuration
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
  error "config.sh not found in $SCRIPT_DIR"
  exit 1
fi
# shellcheck source=../config.sh disable=SC1091
source "$SCRIPT_DIR/config.sh"

: "${DEBUG_LOG:=workflow.log}"

# Validated below, and also used for arithmetic, so must be plain integers.
require_int() {
  local name=$1 value=$2
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    error "$name must be a non-negative integer, got '$value'"
    exit 1
  fi
}

require_range() {
  local name=$1 min=$2 max=$3
  require_int "$name minimum" "$min"
  require_int "$name maximum" "$max"
  if (( min > max )); then
    error "$name: minimum ($min) is greater than maximum ($max)"
    exit 1
  fi
}

# Every required key must be present. Checking explicitly (rather than letting
# `set -u` abort mid-run) keeps the failure message pointing at the real cause:
# a typo like MIN_COMITS otherwise surfaces as a confusing error deep in the run.
missing=()
for key in MIN_COMMITS MAX_COMMITS MIN_DELAY MAX_DELAY COMMIT_PREFIX TARGET_BRANCH; do
  [[ -n "${!key:-}" ]] || missing+=("$key")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  error "Missing or empty config.sh setting(s): ${missing[*]}"
  exit 1
fi

if [[ ${#COMMIT_FILES[@]} -eq 0 ]]; then
  error "COMMIT_FILES is empty in config.sh"
  exit 1
fi

require_range MIN_COMMITS "$MIN_COMMITS" "$MAX_COMMITS"
require_range MIN_DELAY "$MIN_DELAY" "$MAX_DELAY"

# rand_between MIN MAX -> uniform integer in [MIN, MAX].
# The inclusive span is passed through a variable to avoid the classic
# "$(( x % (max - min + 1) ))" splitting that silently produces empty values.
rand_between() {
  local min=$1 max=$2 span=$(( $2 - $1 + 1 ))
  echo $(( (RANDOM % span) + min ))
}

# Portable microsecond timestamp: GNU date supports %N, BSD/macOS does not.
timestamp_us() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S.%N')
  [[ "$ts" =~ \.[0-9]{3,9}$ ]] || ts="$(date '+%Y-%m-%d %H:%M:%S').$(date '+%N' | cut -c1-6)000"
  echo "$ts"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
git rev-parse --git-dir >/dev/null 2>&1 || {
  error "$SCRIPT_DIR is not a git repository"
  exit 1
}

if ! git config user.name >/dev/null || ! git config user.email >/dev/null; then
  error "Git user not configured (set user.name and user.email)"
  exit 1
fi
log "Git configured as: $(git config user.name) <$(git config user.email)>"

# Guard against two invocations against the SAME checkout overlapping.
# The lock lives in the git metadata dir, not the work tree, so it can never
# leave a stray untracked file behind. Note that each GitHub Actions run gets a
# fresh clone, so this does not stop two concurrent *workflow* runs; the
# workflow's `concurrency:` block and the merge-before-push logic handle that.
LOCK_FILE="$(git rev-parse --git-dir)/random_commit.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "Another run is already in progress for this checkout; exiting."
    exit 0
  fi
else
  log "Warning: flock not available, skipping concurrency guard."
fi

# ---------------------------------------------------------------------------
# Generate commits
# ---------------------------------------------------------------------------
COMMITS=$(rand_between "$MIN_COMMITS" "$MAX_COMMITS")
log "Will create $COMMITS commit(s); target branch: $TARGET_BRANCH"

# Capture the starting point so the real number of commits is reported even if
# a sync-merge happens. Derived from the commit this run starts on.
BASE_COMMIT=$(git rev-parse HEAD)
merge_performed=false

commits_created=0
for ((i = 1; i <= COMMITS; i++)); do
  log "Processing commit $i/$COMMITS"

  # Pick a file that is actually reachable, so a bad config value can't make
  # the script append to an unexpected path.
  index=$(( RANDOM % ${#COMMIT_FILES[@]} ))
  RAND_FILE="${COMMIT_FILES[$index]}"

  case "$RAND_FILE" in
    "random.txt")
      # Append deliberately (>>), never truncate (>), so history is preserved.
      echo "$(date '+%Y-%m-%d %H:%M:%S') | Entry #$i: Random value=$RANDOM" >> "$SCRIPT_DIR/$RAND_FILE"
      log "Appended entry to $RAND_FILE"
      ;;
    "timestamps.log")
      echo "$(timestamp_us) | Event $i processed" >> "$SCRIPT_DIR/$RAND_FILE"
      log "Appended timestamp to $RAND_FILE"
      ;;
    *)
      error "Unsupported file in COMMIT_FILES: '$RAND_FILE'"
      exit 1
      ;;
  esac

  file_before="$(git rev-parse -q --verify "HEAD:$RAND_FILE" || true)"
  file_after="$(git hash-object "$SCRIPT_DIR/$RAND_FILE")"
  if [[ -n "$file_before" && "$file_before" == "$file_after" ]]; then
    # Nothing changed for this file, so `git commit` would fail. Skip instead of
    # treating it as a fatal error.
    log "No content change for $RAND_FILE; skipping commit"
    continue
  fi

  git add "$RAND_FILE"

  COMMIT_MSG="$COMMIT_PREFIX: Entry $i - $(date '+%H:%M:%S')"
  git commit -m "$COMMIT_MSG"
  log "Commit created: $COMMIT_MSG"
  commits_created=$((commits_created + 1))

  # Wait between commits (except on last one)
  if (( i < COMMITS )); then
    SLEEP_TIME=$(rand_between "$MIN_DELAY" "$MAX_DELAY")
    log "Waiting ${SLEEP_TIME}s before next commit..."
    sleep "$SLEEP_TIME"
  fi
done

# ---------------------------------------------------------------------------
# Integrate with remote (safe against a diverged history) and push
# ---------------------------------------------------------------------------
remote_ref="refs/remotes/origin/$TARGET_BRANCH"

if ! git fetch --quiet origin "$TARGET_BRANCH" 2>/dev/null || ! git rev-parse --verify -q "$remote_ref" >/dev/null; then
  log "Warning: could not fetch origin/$TARGET_BRANCH; attempting plain push"
else
  if ! git merge-base --is-ancestor "$remote_ref" HEAD; then
    # The remote moved (scheduled runs are frequently delayed, so a local run
    # can start behind). Merge instead of failing the push.
    log "Remote has moved ahead; merging origin/$TARGET_BRANCH before pushing"
    if ! git merge --no-edit "$remote_ref"; then
      error "Merge with origin/$TARGET_BRANCH failed; resolve conflicts manually"
      exit 1
    fi
    merge_performed=true
  fi
fi

log "Pushing to origin/$TARGET_BRANCH"
if ! git push origin "HEAD:$TARGET_BRANCH"; then
  error "Failed to push commits"
  exit 1
fi

# Report the number of commits this run added (merge commits excluded).
# NOTE: `git rev-list --count HEAD ^HEAD~1` is NOT useable here: after a merge
# it counts parents too and inflates the number.
if [[ "$merge_performed" == false ]]; then
  # No sync-merge, so every non-merge commit on top of the base is ours.
  made=$(git rev-list --count --no-merges "$BASE_COMMIT..HEAD")
else
  made=$commits_created
fi

log "Workflow automation completed: $made commit(s) added"

# Expose a machine-readable summary for the GitHub Actions step output.
# The push above already succeeded, so a bad $GITHUB_OUTPUT path must not turn
# this run into a failure.
# (`{ ... } >> file` reports a redirection failure by killing a subshell rather
#  than by returning non-zero, so the target path is checked explicitly.)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  if { : >> "$GITHUB_OUTPUT"; } 2>/dev/null; then
    {
      echo "count=$made"
      echo "branch=$TARGET_BRANCH"
    } >> "$GITHUB_OUTPUT"
  else
    error "Cannot write to GITHUB_OUTPUT ($GITHUB_OUTPUT); push already succeeded"
  fi
fi
