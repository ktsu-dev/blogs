---
title: "Automated Forward-Merge: A Game Studio's Git Strategy"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "How a 20-person game studio eliminated merge debt by automating forward-merges from main to every feature branch, with Azure DevOps pipelines and Slack-based conflict notifications."
categories: ["Development", "Game Development", "DevOps"]
tags: ["git", "devops", "automation", "game-development", "case-study"]
keywords: ["Git forward merge", "automated merge strategy", "game development Git", "Azure DevOps pipeline", "merge conflict automation", "Unreal Engine Git workflow"]
slug: "automated-forward-merge-game-studio-git-strategy"
---

# Automated Forward-Merge: A Game Studio's Git Strategy

Merge debt is the silent killer of game development velocity. Feature branches that diverge from main for weeks accumulate conflicts that take hours or days to resolve at integration time. The longer you wait, the worse it gets.

This post documents how a 20-person game studio working with Unreal Engine — eliminated merge debt entirely by automating forward-merges from main into every active feature branch, with immediate Slack notifications when conflicts arise.

## The Problem: Week-Long Merge Sessions

Before automation, the team followed a conventional Git workflow: feature branches, code review, merge to main. The problem wasn't the workflow — it was the *timing* of conflict detection.

A typical scenario:
1. Artist creates branch, works on character assets for two weeks
2. Programmer creates branch, refactors the animation system
3. Both merge to main the same day
4. The second merge discovers two weeks of conflicting changes
5. Resolution takes a day because the changes are deeply interleaved

The core insight: **conflict detection should happen continuously, not at merge time**. If you find out about a conflict the same day it's introduced, it's a five-minute fix. Two weeks later, it's a full-day archaeology project.

## The Solution: Forward-Merge on Every Push

The team built an Azure DevOps pipeline that triggers on every push to main. It automatically merges main into *every* active feature branch. If a merge succeeds, it pushes the result. If it fails (conflict), it posts to Slack with the exact files and the developers involved.

### Why This Works

The pipeline's effectiveness comes from three properties:

1. **Immediacy**: Conflicts are detected within minutes of the push that causes them, not days or weeks later
2. **Accountability**: The Slack notification tags the specific developers who own the conflicting files, based on `git log` authorship
3. **Low friction**: Clean merges are automatic — developers only get involved when there's an actual conflict

## The "One File Per Actor" Strategy

The team also restructured their Unreal project to minimize the *possibility* of conflicts. In Unreal, Blueprint files are binary and cannot be text-merged. Two people editing the same Blueprint simultaneously guarantees a conflict.

Their solution: decompose Blueprints into the smallest possible units.

- Each actor gets its own Blueprint file
- Shared logic lives in parent classes that change infrequently
- Level layout uses separate sub-levels per area
- Data tables are split by category rather than having one monolithic table

This "one file per actor" approach means that locking a single file blocks only one specific piece of content, not an entire system.

### The Locking Protocol

//TODO: rewrite this section to be about the git lfs plugin

For files that can't be merged (Blueprints, textures, audio), the team uses Git LFS locking with a notification workflow:

1. Developer checks `git lfs locks` before starting work
2. Locks the file: `git lfs lock Content/Characters/Hero.uasset`
3. Edits in Unreal Engine
4. Commits, pushes, and unlocks: `git lfs unlock Content/Characters/Hero.uasset`
5. A post-push hook posts to the team's Slack channel

The lock check is also automated — a post-checkout hook warns if any files in your working directory are locked by someone else.

## Results and Trade-offs

After six months with the automated forward-merge pipeline:

**What improved:**
- Zero surprise conflicts at PR merge time
- Average conflict resolution time dropped from hours to minutes
- Branch lifespan no longer correlated with merge pain
- New team members could see exactly how their changes interacted with others

**What didn't:**
- The file locking plugin caused performance issues with thousands of locked files
- Artists still had to coordinate on shared assets manually
- The pipeline occasionally created merge commits that cluttered branch history

**The fundamental trade-off:** The team chose *continuous small pain* (resolving conflicts daily) over *deferred large pain* (resolving them at integration time). For a game studio where binary assets make retroactive conflict resolution especially painful, this was the right call.

## When This Pattern Applies

Automated forward-merging works best when:
- **Branches are long-lived** (more than a few days)
- **Binary files prevent text merging** (game assets, images, design files)
- **The team is large enough** that multiple people regularly touch the same areas
- **You have CI infrastructure** (Azure DevOps, GitHub Actions, Jenkins) that can run on push

It's overkill for:
- Small teams (2-3 people) who can coordinate verbally
- Short-lived branches that merge within a day
- Codebases that are purely text (where Git's merge capabilities handle most conflicts automatically)

## Implementing It Yourself

If you want to adopt this pattern:

1. **Start with notification only** — don't auto-push the merge results. Let developers see the conflicts and merge manually for the first month.
2. **Exclude release branches** — only forward-merge into active feature branches, not stabilization or release branches.
3. **Set up the Slack integration early** — the notification system is the most valuable part. Without it, auto-merging is just creating work that nobody notices.
4. **Restructure your assets first** — if you're in Unreal or Unity, the "one file per actor" decomposition reduces conflict frequency more than any automation.

## References

- [Git LFS Locking](https://git-lfs.com/)
- [Azure DevOps Pipelines](https://learn.microsoft.com/en-us/azure/devops/pipelines/)
- [Unreal Engine Source Control](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-perforce-as-source-control-for-unreal-engine)
