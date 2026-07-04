# PR Playbook

Rules of the road for opening branches and PRs in this repo. Applies to humans and to background workers.

## The 6 rules

1. **One PR = one outcome.** One untracked directory, one focused change, or one feature. Never mix.
2. **Branch naming.** `feat/<pkg>-<change>` for features, `fix/<pkg>-<issue>` for fixes, `chore/<what>` for cleanup. `<pkg>` is the top-level directory the change targets (e.g. `slack-bot`, `voice-bridge`, `calendar`).
3. **Baseline discipline.** Every branch starts fresh off `origin/main` — never off an existing WIP branch, never on an unclean tree. Verify with `git status --short` before you branch.
4. **Auto-merge default.** Every PR opened via `gh pr create` MUST be followed by `gh pr merge --auto --squash --delete-branch` so the PR lands the moment CI checks pass. No manual "poke someone to click merge."
5. **Stage explicitly.** `git add <path>` for each file the branch actually changed. Never `git add -A` or `git add .` — they pick up unrelated files.
6. **No mega-diffs.** If a PR exceeds ~500 net lines or touches more than 3 top-level directories, stop and split.

## Why

A 2026-07-04 investigation found a worker's committed diff was +2897 lines because it inherited an uncommitted WIP tree as its baseline. That single dump bundled 16+ independent PRs' worth of work into one non-mergeable commit. These rules exist to prevent that failure mode.

## For workers

Background workers spawned via `~/.agent/scripts/spawn-worker.sh` should be launched with `WORKER_WORKTREE=1` when they will commit code. That creates a fresh `git worktree` at `~/.agent/workers/worktrees/<worker-id>/` off `origin/main`, so the worker cannot accidentally capture unrelated in-flight work.

Every worker's `[DONE:]` marker on a git-committing task must include the PR URL and confirmation that `gh pr merge --auto --squash --delete-branch` was set.
