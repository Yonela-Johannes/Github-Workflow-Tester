# Workflow Tester

An automated GitHub Actions workflow project that performs periodic random commits to simulate continuous activity and test workflow automation.

## Overview

This project demonstrates automated commit workflows using GitHub Actions. It runs on a scheduled interval (hourly) to automatically generate and push commits with random log entries to the repository.

> **Warning — read before enabling.** This workflow writes directly to your default branch every hour. At 2-4 commits per run that is roughly **48-96 commits per day** of synthetic history. Enable it on a dedicated test repository, not on a repository you care about. See [Caveats](#caveats-and-disclaimer).

## Features

- **Automated Commits**: Automatically generates commits on a configurable schedule
- **Random Entry Generation**: Creates random log entries with timestamps
- **Scheduled Execution**: Runs via GitHub Actions on a cron schedule (hourly)
- **Manual Trigger**: Supports manual workflow dispatch for on-demand execution
- **Error Handling**: Robust error detection and logging
- **Multi-file Support**: Can commit changes to multiple files
- **Debug Logging**: Comprehensive logging for troubleshooting
- **Configuration Management**: Easy customization via `config.sh` with validation
- **Concurrent-safe Pushes**: Merges the remote branch before pushing, so a run that starts behind does not fail
- **Accurate Reporting**: Reports the real number of commits added per run
- **Run Locking**: Overlapping runs exit cleanly instead of racing

## Project Structure

```
workflow-tester/
├── .github/
│   └── workflows/
│       └── auto-committer.yml      # GitHub Actions workflow configuration
├── scripts/
│   └── random_commit.sh            # Main automation script with error handling
├── config.sh                        # Customizable configuration file
├── random.txt                       # Log file for commit entries
├── timestamps.log                   # Microsecond-precision event log
├── .gitignore                       # Git ignore patterns
└── README.md                        # This file
```

`workflow.log` is created at runtime and is intentionally not committed.

## How It Works

### Workflow Execution

The GitHub Actions workflow (`auto-committer.yml`) triggers automatically every hour. When executed, it:

1. **Checks out** the repository using the GitHub token, from the latest remote state
2. **Validates** repository state and git configuration
3. **Configures Git** with author information and safety settings
4. **Runs** the `random_commit.sh` script (failing the job if it fails)
5. **Commits** each generated entry and **pushes** to the target branch
6. **Uploads** `workflow.log` as a build artifact
7. **Reports** the job status and the number of commits actually made

### Random Commit Script

The improved `random_commit.sh` script now includes:

- **Error handling** - Exits immediately with a clear message on any failure
- **Configuration validation** - Rejects missing keys, non-integer values, and inverted ranges before committing anything
- **Comprehensive logging** - Writes all actions to `workflow.log`
- **Multi-file support** - Can update different files (`random.txt`, `timestamps.log`)
- **Random delays** - Configurable delays between commits
- **Concurrency guard** - A second run exits instead of racing the first
- **Remote sync** - Merges `origin/<branch>` before pushing if the remote moved ahead
- **Push verification** - The run fails if the push fails

Each log entry includes:
- Current date and time
- Random values for uniqueness
- Operation type and file information

## Configuration

### Using config.sh

The `config.sh` file provides easy customization without modifying the main script:

```bash
# Commit settings (inclusive range)
MIN_COMMITS=2           # Minimum commits per run
MAX_COMMITS=4           # Maximum commits per run

# Delay settings (in seconds)
MIN_DELAY=30            # Minimum delay between commits
MAX_DELAY=300           # Maximum delay between commits

# Files to commit
COMMIT_FILES=("random.txt" "timestamps.log")

# Commit message prefix
COMMIT_PREFIX="Auto-commit"

# Branch to push to
TARGET_BRANCH="main"

# Debug logging
DEBUG_MODE=true         # Enable/disable debug output
DEBUG_LOG="workflow.log"
```

### Workflow Schedule

Edit the cron expression in [.github/workflows/auto-committer.yml](.github/workflows/auto-committer.yml):

```yaml
on:
  schedule:
    - cron: "0 * * * *"  # Every hour, on the hour
```

**Cron Format**: `minute hour day month dayofweek`
- `0 * * * *` = Every hour (current setting)
- `*/5 * * * *` = Every 5 minutes
- `*/15 * * * *` = Every 15 minutes
- `0 */2 * * *` = Every 2 hours
- `0 0 * * *` = Daily at midnight
- `0 */6 * * *` = Every 6 hours

### Git Configuration

Update the Git user details in the workflow file:

```yaml
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Requirements

- GitHub repository with Actions enabled
- Write permissions on the repository
- `GITHUB_TOKEN` secret (automatically provided by GitHub)

## Usage

### Automatic Execution

The workflow runs automatically based on the configured schedule (hourly by default).

### Manual Trigger

To trigger the workflow manually:

1. Go to your repository on GitHub
2. Click **Actions**
3. Select **Auto Committer**
4. Optionally enter an exact **commit count**, then click **Run workflow**
   (leave it empty to use the random range from `config.sh`)

### Local Testing

To test the script locally:

```bash
./scripts/random_commit.sh
```

This really commits **and pushes**. Against an unimportant branch or a scratch
clone only. Set `MIN_COMMITS`/`MAX_COMMITS` temporarily to keep a test short.

## Files

| File | Purpose |
|------|---------|
| `.github/workflows/auto-committer.yml` | GitHub Actions workflow with validation and logging |
| `scripts/random_commit.sh` | Enhanced automation script with error handling |
| `config.sh` | Configuration file for easy customization |
| `random.txt` | Log file where commit entries are appended |
| `.gitignore` | Git ignore patterns for logs and temp files |
| `README.md` | Project documentation |

## Use Cases

- Testing GitHub Actions workflows
- Simulating continuous repository activity
- Learning GitHub Actions automation
- Maintaining contribution streaks
- Demo/testing purposes for CI/CD pipelines

## Security Notes

- The workflow uses `secrets.GITHUB_TOKEN` which is automatically provided by GitHub Actions
- Git credentials are configured within the workflow context
- No sensitive information is committed to the repository
- `.gitignore` excludes logs and temporary files
- Ensure appropriate branch protection rules are in place
- Consider using environment secrets for sensitive data
- Review workflow logs for troubleshooting

## Customization

### Change Commit Frequency

Modify the cron schedule in `auto-committer.yml` to adjust how often commits are generated.

### Adjust Commit Count and Delays

Edit `config.sh`:

```bash
# Generate 3-6 commits per run instead of 2-4
MIN_COMMITS=3
MAX_COMMITS=6

# Change delays to 1-5 minutes between commits
MIN_DELAY=60
MAX_DELAY=300
```

> Keep `MIN_COMMITS * MAX_DELAY` comfortably below the job's 20-minute timeout,
> otherwise the workflow will be cancelled mid-run.

### Add More Files to Commit

Modify the `COMMIT_FILES` array in `config.sh`:

```bash
COMMIT_FILES=("random.txt" "timestamps.log" "metrics.csv")
```

Then add a matching branch to the `case` statement in `scripts/random_commit.sh`.
A file listed in `COMMIT_FILES` without a matching branch aborts the run (this
prevents a typo from writing outside the repository).

### Customize Commit Messages

Edit `COMMIT_PREFIX` in `config.sh`:

```bash
COMMIT_PREFIX="chore: automated update"
```

### Change Target Branch

Update `TARGET_BRANCH` in `config.sh`:

```bash
TARGET_BRANCH="develop"  # Push to develop instead of main
```

## Troubleshooting

**Workflow not running?**
- Ensure GitHub Actions is enabled in repository settings
- Check workflow syntax in the Actions tab
- Verify branch exists and is accessible
- Review cron schedule for correctness

**Commits not pushing?**
- Verify push permissions and branch protection rules
- Check that the target branch exists
- Review workflow run logs for error messages
- Ensure token has appropriate permissions

**Script permissions errors?**
- The workflow handles `chmod +x` automatically
- For local testing, run: `chmod +x scripts/random_commit.sh`
- Check file permissions: `ls -la scripts/`

**Missing config.sh?**
- Ensure `config.sh` exists in the root directory
- Run: `git pull` to get the latest version
- Check `.gitignore` doesn't exclude it

**Debug logging not working?**
- Enable `DEBUG_MODE=true` in `config.sh`
- Check `workflow.log` file for details
- Ensure write permissions to the repository

## Workflow Logs

View workflow execution logs in GitHub:

1. Go to repository **Actions** tab
2. Select **Auto Committer** workflow
3. Click on a specific run to see detailed logs
4. Check the step logs for detailed execution information
5. Download workflow logs for offline analysis

Check local logs:

```bash
# View debug logs from the script
cat workflow.log

# View recent commits
git log --oneline -10
```

## Caveats and Disclaimer

- **Scheduled runs are unreliable by design.** GitHub delays `schedule` triggers
  under load and **disables scheduled workflows after 60 days** of repository
  inactivity. Every run does write a commit, which resets that timer, but a
  delayed run shows up as a burst of commits rather than an even spread.
- **Commit-count accuracy.** The reported count reflects commits added by the
  script. It excludes merge commits created while syncing with the remote.
- **History inflation.** Thousands of synthetic commits make `git log`, blame
  and pull requests hard to use. Do not enable this on a working codebase.
- **Branch protection.** `main` usually rejects direct pushes. Configure the
  target branch to allow the Actions bot, or point `TARGET_BRANCH` at a
  scratch branch and set the `AUTO_COMMIT_BRANCH` repository variable to match.

## License

This project is provided as-is for educational and testing purposes.

## Author

Created by RensithUdara

---

**Last Updated**: October 2026
**Version**: 2.1 (Hardened push/counting, validated config, accurate docs)
