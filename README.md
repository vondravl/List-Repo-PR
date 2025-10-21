# List Repo PRs

A bash script to list merged pull requests from a GitHub repository in an Excel-ready format.

## Features

- 📅 List PRs merged after a specific date
- 🔢 List the last N merged PRs
- 📋 Excel-ready output with hyperlinks
- 🏷️ Includes PR labels
- 🔒 **Read-only** - safe to run on any repository

## Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/) - installed and authenticated
- `jq` - JSON processor

```bash
# Install GitHub CLI (macOS)
brew install gh

# Install jq
brew install jq

# Authenticate GitHub CLI
gh auth login
```

## Usage

### List PRs merged since a specific date

```bash
./list_repo_pr.sh --since "2024-10-15T10:30Z"
```

### List the last N merged PRs

```bash
./list_repo_pr.sh --last 10
```

### Specify a repository

```bash
./list_repo_pr.sh --repo "owner/repo" --last 5
```

By default, the script auto-detects the repository from the current git directory or the `GITHUB_REPOSITORY` environment variable.

## Output Format

The script outputs data in a pipe-delimited format that can be copied directly into Excel:

```
ID|Description|Hyperlink
#123|Fix user authentication bug [bug, security]|https://github.com/owner/repo/pull/123
#124|Add dark mode feature [enhancement]|https://github.com/owner/repo/pull/124
```

Simply copy the output and paste it into Excel - the hyperlinks will be automatically detected.

## Date Format

Use ISO 8601 format for dates:
- `2024-10-15T10:30Z`
- `2024-10-15T10:30:00Z`

## Help

```bash
./list_repo_pr.sh --help
```

## Compatibility

- Tested with `bash` and `zsh`.
- Works on macOS and Linux.
- Requires network access for `gh` (GitHub CLI) API calls.

