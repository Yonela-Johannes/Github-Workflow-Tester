#!/bin/bash
# config.sh
# Configuration file for the workflow tester

# Commit settings
MIN_COMMITS=2
MAX_COMMITS=4

# Delay settings (in seconds)
MIN_DELAY=30
MAX_DELAY=300

# Files to commit
COMMIT_FILES=("random.txt" "timestamps.log")

# Commit message prefix
COMMIT_PREFIX="Auto-commit"

# Branch to push to
TARGET_BRANCH="main"

# Log file for debugging
DEBUG_LOG="workflow.log"

# Enable debug mode (true/false)
DEBUG_MODE=true
