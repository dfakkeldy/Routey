# Branch and Worktree Audit

Captured July 1, 2026 after `git fetch --all --prune`.

## Current Live Branches

| Branch/worktree | State | Action |
| --- | --- | --- |
| `origin/main` | GitHub Pages source and stable branch; behind `nightly`. | Keep. Use docs-only PRs here when the public website must deploy before a full promotion. |
| `origin/nightly` | Current integration train at PR #25. | Keep. Normal feature work targets this branch. |
| `origin/weekly` | Last promoted beta branch. | Keep for promotion ladder. |
| `codex/docs-site-sync` | This docs/site/Fastlane-docs branch, based on `origin/main`. | Keep until docs PR is merged or closed. |
| `codex/docs-sync-app-store` | Empty safety branch created from `origin/nightly` before switching to the main-based docs branch. | Delete after confirming no commits land on it. |

## Local Worktrees

| Path | Branch/HEAD | Finding | Action |
| --- | --- | --- | --- |
| `/Users/dfakkeldy/Developer/Routey` | `codex/promote-weekly-main-testflight` | Promotion branch is already merged as PR #12. | Remove the worktree or switch it to a current branch when no local edits remain. |
| `/Users/dfakkeldy/.codex/worktrees/9a5f/Routey` | detached `ac44261` | Older detached `nightly` snapshot before PRs #23-#25. | Remove if no untracked files are needed. |
| `/Users/dfakkeldy/.codex/worktrees/bbb7/Routey` | `codex/docs-site-sync` | Active docs-sync worktree. | Keep until current PR work is done. |
| `/Users/dfakkeldy/.codex/worktrees/da36/Routey` | `codex/testflight-fastlane-metadata` | PR #25 merged; remote branch was pruned. | Save any uncommitted local-only files, then remove the worktree and delete the local branch. |
| `/Users/dfakkeldy/.codex/worktrees/routey-app-icon-fix` | `codex/routey-app-icon-testflight` | PR #22 merged; remote branch was pruned. | Save any uncommitted local-only files, then remove the worktree and delete the local branch. |
| `/Users/dfakkeldy/.codex/worktrees/routey-devlog-automation` | `codex/devlog-automation` | PR #4 merged; remote branch was pruned. | Remove worktree and delete local branch if clean. |
| `/Users/dfakkeldy/Developer/Routey/.claude/worktrees/todays-run-ui` | `claude/todays-run-ui` | Ahead 2/behind 24; appears superseded by merged PR #24 plus PR #23 docs/spec work. | Inspect for unique commits before deleting. If unique, cherry-pick onto a fresh `codex/` branch or archive as a note. |

## Remote Branches Worth Keeping

These branches still have remote refs and can stay until their authors clean
them up or they are deliberately pruned:

- `origin/codex/routey-encrypted-handoff`
- `origin/codex/routey-history-domain`
- `origin/codex/routey-ocr-core`
- `origin/codex/routey-report-builder`
- `origin/codex/routey-search-freshness`
- `origin/codex/routey-todays-run-domain`
- `origin/codex/routey-v1-m0-hardening`
- `origin/codex/testflight-match-setup`
- `origin/codex/internal-nightly-testers`
- `origin/codex/promote-nightly-weekly-testflight`
- `origin/codex/promote-weekly-main-testflight`
- `origin/claude/focused-easley-451da5`

Most correspond to merged PRs. They are not blocking current work, but they can
be deleted remotely once branch cleanup is desired.

## Cleanup Commands

Run these only after checking each worktree is clean with
`git -C <path> status --short`:

```sh
git worktree remove /Users/dfakkeldy/.codex/worktrees/9a5f/Routey
git worktree remove /Users/dfakkeldy/.codex/worktrees/da36/Routey
git worktree remove /Users/dfakkeldy/.codex/worktrees/routey-app-icon-fix
git worktree remove /Users/dfakkeldy/.codex/worktrees/routey-devlog-automation
git branch -d codex/testflight-fastlane-metadata
git branch -d codex/routey-app-icon-testflight
git branch -d codex/devlog-automation
```

Do not remove `.claude/worktrees/todays-run-ui` until its two ahead commits are
inspected against current `origin/nightly`.
