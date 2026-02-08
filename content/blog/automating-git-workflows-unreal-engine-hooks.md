---
title: "Automating Git Workflows for Unreal Engine Teams with Hooks"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "Ready-to-use Git hook scripts for Unreal Engine projects — prevent large file commits, enforce LFS, validate Blueprints, notify about locks, and clean up after merges."
categories: ["Development", "Game Development", "DevOps"]
tags: ["git", "unreal-engine", "automation", "game-development", "devops"]
keywords: ["Git hooks Unreal Engine", "pre-commit hook game dev", "Git LFS hooks", "Blueprint validation", "game development workflow", "UE5 Git automation"]
slug: "automating-git-workflows-unreal-engine-hooks"
---

# Automating Git Workflows for Unreal Engine Teams with Hooks

Unreal Engine projects present unique challenges for Git. Binary assets are huge, Blueprint files can't be merged, and forgetting to use Git LFS will bring your entire team to a halt. Git hooks — scripts that fire automatically at key moments — can catch these problems before they reach the remote.

This post provides production-ready hook scripts specifically designed for Unreal Engine workflows, covering the most common failure modes.

## Quick Setup

Git hooks live in `.git/hooks/` in your repository. To install one:

1. Create a file with the hook name (e.g., `.git/hooks/pre-commit`) — no file extension
2. Make it executable: `chmod +x .git/hooks/pre-commit`
3. Add the script content

For team-wide deployment, store the hooks in your repository (e.g., `git-hooks/`) and have everyone symlink or copy them. We'll cover a setup script for this at the end.

## Pre-Commit: Block Large Files

The single most common disaster in Unreal + Git projects is accidentally committing a large binary file directly instead of through LFS. Once it's in history, it's there forever (short of rewriting).

```bash
#!/bin/bash
# .git/hooks/pre-commit

MAX_SIZE=5242880  # 5 MB

files=$(git diff --cached --name-only --diff-filter=ACMRT)

large_files=()
for file in $files; do
    # Skip files already tracked by LFS
    if git check-attr filter "$file" | grep -q "filter: lfs"; then
        continue
    fi

    size=$(git cat-file -s ":$file" 2>/dev/null \
        || stat -f%z "$file" 2>/dev/null \
        || stat -c%s "$file" 2>/dev/null)

    if [[ $size -gt $MAX_SIZE ]]; then
        large_files+=("$file ($((size / 1024 / 1024)) MB)")
    fi
done

if [[ ${#large_files[@]} -gt 0 ]]; then
    echo "Error: Files exceed the ${MAX_SIZE} byte limit:"
    printf "  %s\n" "${large_files[@]}"
    echo "Add them to Git LFS or .gitignore"
    exit 1
fi
```

The `git check-attr filter` check is critical — it skips files that LFS is already handling, so the hook doesn't false-positive on legitimate tracked assets.

## Commit-Msg: Enforce Message Format

With multiple disciplines (art, design, engineering) committing to the same repo, consistent commit messages matter for filtering history:

```bash
#!/bin/bash
# .git/hooks/commit-msg

COMMIT_MSG=$(cat "$1")

VALID_PREFIXES="(Feature|Fix|Refactor|Content|Docs|Build|Test|Style|Chore|Performance)"
AREAS="(UI|Gameplay|Graphics|Physics|Audio|Input|Network|Tools|Core|Content|AI|Editor)"
REGEX="^\[$AREAS\] $VALID_PREFIXES: .{5,}"

if ! [[ $COMMIT_MSG =~ $REGEX ]]; then
    echo "ERROR: Invalid commit message format."
    echo "Use: [Area] Prefix: Description"
    echo ""
    echo "  [Gameplay] Feature: Add player movement system"
    echo "  [UI] Fix: Correct HUD scaling on ultrawide"
    echo "  [Graphics] Performance: Optimize shadow rendering"
    exit 1
fi
```

This gives you `git log --grep="\[Graphics\]"` for free.

## Post-Checkout: Warn About LFS Locks

After switching branches, developers need to know which files are locked — especially if they're about to modify one:

```bash
#!/bin/bash
# .git/hooks/post-checkout

# Only run on branch checkout, not file checkout
if [[ "$3" != "1" ]]; then exit 0; fi

echo "Checking for LFS locks..."
LOCKS=$(git lfs locks)

if [[ -n "$LOCKS" ]]; then
    echo "Currently locked files:"
    echo "$LOCKS"
    echo ""

    # Check if any locked files overlap with your working changes
    CHANGED_FILES=$(git diff --name-only)
    CONFLICTS=()

    for file in $CHANGED_FILES; do
        if echo "$LOCKS" | grep -q "$file"; then
            CONFLICTS+=("$file")
        fi
    done

    if [[ ${#CONFLICTS[@]} -gt 0 ]]; then
        echo "WARNING: These locked files are in your working area:"
        printf "  %s\n" "${CONFLICTS[@]}"
        echo "Coordinate with the lock owner before making changes."
    fi
fi
```

This won't block checkout — it just makes sure nobody is surprised.

## Post-Checkout: Auto-Generate Project Files

Switching branches in an Unreal project often changes `.uproject` or module configurations. Auto-regenerating project files prevents stale IDE state:

```bash
#!/bin/bash
# .git/hooks/post-checkout (append to existing hook or combine)

if [[ "$3" != "1" ]]; then exit 0; fi

PROJECT_ROOT=$(git rev-parse --show-toplevel)
UE_PROJECT_FILE=$(find "$PROJECT_ROOT" -maxdepth 2 -name "*.uproject" | head -n 1)

if [[ -z "$UE_PROJECT_FILE" ]]; then exit 0; fi

echo "Regenerating project files..."

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    "$PROJECT_ROOT/GenerateProjectFiles.bat" -project="$UE_PROJECT_FILE" -game
elif [[ "$OSTYPE" == "darwin"* ]]; then
    sh "$PROJECT_ROOT/GenerateProjectFiles.command" -project="$UE_PROJECT_FILE" -game
else
    sh "$PROJECT_ROOT/GenerateProjectFiles.sh" -project="$UE_PROJECT_FILE" -game
fi
```

## Pre-Push: Catch Conflict Markers

Merge conflict markers in binary-adjacent files are easy to miss. This hook catches them before they reach the remote:

```bash
#!/bin/bash
# .git/hooks/pre-push

if git diff --staged | grep -E '(<<<<<<<|=======|>>>>>>>)'; then
    echo "Error: Unresolved merge conflicts detected."
    echo "Resolve them before pushing."
    exit 1
fi
```

## Pre-Push: Verify LFS Content

Pushing LFS pointer files without the actual content behind them is another common failure. This check catches it:

```bash
#!/bin/bash
# .git/hooks/pre-push

lfs_files=$(git lfs ls-files | awk '{print $3}')

missing=()
for file in $lfs_files; do
    if [[ ! -f "$file" ]] || [[ $(wc -c < "$file") -lt 1000 ]]; then
        missing+=("$file")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: These LFS files are missing content:"
    printf "  %s\n" "${missing[@]}"
    echo "Run 'git lfs pull' first."
    exit 1
fi
```

## Post-Merge: Flag Changed Blueprints

Blueprints can't be text-merged, so after any merge, developers should know which Blueprints changed — they might need manual review in-editor:

```bash
#!/bin/bash
# .git/hooks/post-merge

blueprint_files=$(git diff-tree -r --name-only ORIG_HEAD HEAD | grep -E "\.uasset$")

actual_blueprints=()
for file in $blueprint_files; do
    [[ ! -f "$file" ]] && continue
    if head -c 100 "$file" 2>/dev/null | grep -q "Blueprint"; then
        actual_blueprints+=("$file")
    fi
done

if [[ ${#actual_blueprints[@]} -gt 0 ]]; then
    echo "Blueprints changed in this merge:"
    printf "  %s\n" "${actual_blueprints[@]}"
    echo "Review these in-editor for unexpected changes."
fi
```

## Post-Merge: Clean Stale Build Artifacts

Stale `Intermediate` files after a merge cause phantom build errors. Auto-cleaning prevents the "works on their machine" problem:

```bash
#!/bin/bash
# .git/hooks/post-merge

PROJECT_ROOT=$(git rev-parse --show-toplevel)

echo "Cleaning stale build artifacts..."

if [[ -d "$PROJECT_ROOT/Intermediate" ]]; then
    rm -rf "$PROJECT_ROOT/Intermediate"
    echo "Removed Intermediate/"
fi

if [[ -d "$PROJECT_ROOT/Saved/Autosaves" ]]; then
    rm -rf "$PROJECT_ROOT/Saved/Autosaves"
    echo "Removed Saved/Autosaves/"
fi

# Keep DerivedDataCache — rebuilding it is expensive
if [[ -d "$PROJECT_ROOT/Saved/DerivedDataCache" ]]; then
    echo "Note: DerivedDataCache preserved for build speed."
fi
```

## Server-Side: Enforce LFS for Binaries

If your hosting supports server-side hooks, this pre-receive hook is the ultimate safety net — it rejects pushes that contain binary files not tracked by LFS:

```bash
#!/bin/bash
# hooks/pre-receive (server-side)

BINARY_EXT="\.(uasset|umap|png|jpg|jpeg|psd|mp3|wav|mp4|mov|tga|exr|fbx|obj|sbs|sbsar|bmp|hdr)$"
zero="0000000000000000000000000000000000000000"

while read old_rev new_rev ref; do
    [[ "$new_rev" = "$zero" ]] && continue

    non_lfs=$(git diff --name-only --diff-filter=AM "$old_rev" "$new_rev" \
        | grep -iE "$BINARY_EXT" \
        | xargs -I{} git check-attr filter {} \
        | grep -v "filter: lfs" \
        | cut -d: -f1)

    if [[ -n "$non_lfs" ]]; then
        echo "Rejected: binary files not tracked by LFS:"
        echo "$non_lfs"
        echo "Run: git lfs track \"*.extension\""
        exit 1
    fi
done
```

## Windows: PowerShell Hooks

For Windows-only teams, here's the large file check as a PowerShell script:

```powershell
# .git/hooks/pre-commit.ps1
$MAX_SIZE = 5MB

$files = git diff --cached --name-only --diff-filter=ACMRT
$large_files = @()

foreach ($file in $files) {
    $lfs = git check-attr filter $file
    if ($lfs -match "filter: lfs") { continue }

    try {
        $size = (Get-Item $file).Length
        if ($size -gt $MAX_SIZE) {
            $large_files += "$file ($([math]::Round($size / 1MB, 1)) MB)"
        }
    } catch { continue }
}

if ($large_files.Count -gt 0) {
    Write-Host "Error: Files exceed $($MAX_SIZE / 1MB) MB limit:"
    $large_files | ForEach-Object { Write-Host "  $_" }
    exit 1
}
exit 0
```

Call it from a bash shim (Git on Windows still uses bash for hooks):

```bash
#!/bin/sh
# .git/hooks/pre-commit
powershell.exe -ExecutionPolicy Bypass -NoProfile -File .git/hooks/pre-commit.ps1
exit $?
```

## Team-Wide Installation Script

Store all hooks in a `git-hooks/` directory in your repo, then give the team this setup script:

```bash
#!/bin/bash
# setup-hooks.sh — run once per clone

PROJECT_ROOT=$(git rev-parse --show-toplevel)
HOOKS_SRC="$PROJECT_ROOT/git-hooks"
HOOKS_DST="$PROJECT_ROOT/.git/hooks"

install_hook() {
    local name=$1
    if [[ -f "$HOOKS_SRC/$name" ]]; then
        cp "$HOOKS_SRC/$name" "$HOOKS_DST/$name"
        chmod +x "$HOOKS_DST/$name"
        echo "Installed: $name"
    fi
}

install_hook "pre-commit"
install_hook "commit-msg"
install_hook "post-checkout"
install_hook "pre-push"
install_hook "post-merge"

echo "All hooks installed."
```

Alternatively, use `git config core.hooksPath git-hooks` to point Git at the directory directly — no copying needed.

## Which Hooks to Start With

If you're adding hooks to an existing project, don't install all of them at once. Start with the highest-impact, lowest-friction ones:

1. **Pre-commit: large file check** — prevents the most damaging mistake
2. **Pre-push: LFS content verification** — catches the second most damaging mistake
3. **Post-merge: Blueprint change notification** — information only, no friction

Add the rest once the team is comfortable with the workflow.

## References

- [Git Hooks Documentation](https://git-scm.com/docs/githooks)
- [Git LFS Documentation](https://git-lfs.com/)
- [Unreal Engine Version Control](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-perforce-as-source-control-for-unreal-engine)
- [core.hooksPath configuration](https://git-scm.com/docs/git-config#Documentation/git-config.txt-corehooksPath)
