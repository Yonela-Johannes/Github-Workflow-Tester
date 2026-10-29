#!/usr/bin/env bash
# config.sh
# Configuration for the auto-committer. Sourced by scripts/random_commit.sh,
# which validates every value below and refuses to run if anything is invalid.

# Commit settings (inclusive range)
MIN_COMMITS=2
MAX_COMMITS=4

# Delay settings (in seconds, inclusive range)
# Keep MAX_DELAY small enough that MIN_COMMITS * MAX_DELAY stays well below the
# job's 20-minute timeout in .github/workflows/auto-committer.yml.
MIN_DELAY=30
MAX_DELAY=300

# Files the script may append to. Only files with a matching case branch in
# scripts/random_commit.sh are supported; anything else aborts the run.
COMMIT_FILES=("random.txt" "timestamps.log")

# Commit message prefix
COMMIT_PREFIX="Auto-commit"

# Branch to push to
TARGET_BRANCH="main"

# Log file for debugging (ignored by git)
DEBUG_LOG="workflow.log"

# Enable debug mode (true/false)
DEBUG_MODE=true
