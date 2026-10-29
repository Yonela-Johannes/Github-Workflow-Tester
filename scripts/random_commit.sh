#!/bin/bash
# random_commit.sh
# Generates random commits to simulate workflow logging with error handling

set -e  # Exit on error

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config.sh"

# Initialize logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$SCRIPT_DIR/$DEBUG_LOG"
}

error() {
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2 | tee -a "$SCRIPT_DIR/$DEBUG_LOG"
}

# Trap errors
trap 'error "Script failed at line $LINENO"; exit 1' ERR

log "Starting workflow automation script"

# Verify git is configured
if ! git config user.name > /dev/null; then
  error "Git user not configured"
  exit 1
fi

log "Git configured as: $(git config user.name) <$(git config user.email)>"

# Generate number of commits
COMMITS=$(( ( RANDOM % ($MAX_COMMITS - $MIN_COMMITS + 1) ) + $MIN_COMMITS ))
log "Will create $COMMITS commits in this run"

# Main loop
for ((i=1; i<=COMMITS; i++)); do
  log "Processing commit $i/$COMMITS"
  
  # Randomly choose which file to update
  RAND_FILE=${COMMIT_FILES[$((RANDOM % ${#COMMIT_FILES[@]}))]}
  
  case $RAND_FILE in
    "random.txt")
      echo "$(date '+%Y-%m-%d %H:%M:%S') | Entry #$i: Random value=$RANDOM" >> "$SCRIPT_DIR/$RAND_FILE"
      log "Appended entry to $RAND_FILE"
      ;;
    "timestamps.log")
      echo "$(date '+%Y-%m-%d %H:%M:%S.%N') | Event $i processed" >> "$SCRIPT_DIR/$RAND_FILE"
      log "Appended timestamp to $RAND_FILE"
      ;;
  esac
  
  # Stage and commit
  git add "$SCRIPT_DIR/$RAND_FILE"
  
  COMMIT_MSG="$COMMIT_PREFIX: Entry $i - $(date '+%H:%M:%S')"
  git commit -m "$COMMIT_MSG"
  log "Commit created: $COMMIT_MSG"
  
  # Wait between commits (except on last one)
  if [ $i -lt $COMMITS ]; then
    SLEEP_TIME=$(( ( RANDOM % ($MAX_DELAY - $MIN_DELAY + 1) ) + $MIN_DELAY ))
    log "Waiting $SLEEP_TIME seconds before next commit..."
    sleep "$SLEEP_TIME"
  fi
done

# Push changes
log "Pushing $COMMITS commits to origin/$TARGET_BRANCH"
if git push origin "$TARGET_BRANCH"; then
  log "Successfully pushed commits"
else
  error "Failed to push commits"
  exit 1
fi

log "Workflow automation completed successfully"
