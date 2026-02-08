---
title: "Branching Strategies for Game Teams: Small vs. Large"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "Git branching strategies that scale with team size — from 2-person indie studios to 30+ developer teams, including binary asset workflows and the Perforce hybrid approach."
categories: ["Development", "Game Development", "DevOps"]
tags: ["git", "game-development", "architecture", "team-management"]
keywords: ["Git branching strategy", "game development workflow", "Git LFS locking", "team branching model", "Perforce vs Git", "Unreal Engine branching", "binary asset workflow"]
slug: "branching-strategies-game-teams-small-vs-large"
---

# Branching Strategies for Game Teams: Small vs. Large

The branching strategy that works for a 3-person indie team will actively harm a 30-person studio. Game development adds unique constraints — binary assets that can't be merged, non-technical team members who need simple workflows, and repositories that can reach hundreds of gigabytes.

This post presents branching strategies at four team scales, along with the binary asset coordination workflows that make Git viable for game projects.

## Small Teams (2-5 Developers)

At this scale, coordination is verbal. The branching strategy should be dead simple:

```
main ─────────────────────────────────────→ (releases)
  │
  └── development ────────────────────────→ (integration)
        ├── feature/player-movement ──┘
        ├── feature/inventory-ui ─────┘
        └── feature/enemy-ai ─────────┘
```

**Rules:**
- `main` is always releasable
- `development` is the integration branch — features merge here first
- Feature branches are short-lived (days, not weeks)
- Hotfixes branch from `main` and merge back to both `main` and `development`

**Why it works:** Everyone knows what everyone else is working on. Conflicts are rare because the team is small enough to avoid stepping on each other. The overhead of a more complex strategy isn't justified.

**When to upgrade:** When features start conflicting regularly, or when you add non-engineering disciplines (art, design) who need their own integration space.

## Medium Teams (6-15 Developers)

At this scale, you typically have distinct disciplines — engineers and artists at minimum. They need separate integration spaces:

```
main
  └── development
        ├── art ─────────────────────────→ (art integration)
        │     ├── feature/character-model
        │     ├── feature/environment-textures
        │     └── feature/ui-sprites
        │
        └── tech ────────────────────────→ (engineering integration)
              ├── feature/gameplay-movement
              ├── feature/combat-system
              └── feature/save-system
```

**Rules:**
- `art` and `tech` branches integrate within their discipline first
- Cross-discipline integration happens at the `development` level
- Artists rarely need to touch code; engineers rarely need to touch assets
- Weekly merges from discipline branches into `development`

**Why it works:** Artists and engineers stop blocking each other. A broken shader experiment in `tech` doesn't prevent the art team from committing new textures. Integration issues surface at the `development` merge, not in individual feature branches.

**The key insight:** Separate integration branches by *conflict domain*, not by organizational chart. If two groups rarely modify the same files, they can work independently.

## Large Teams (15-30 Developers)

At this scale, even disciplines need subdivision:

```
main
  └── development
        ├── art/characters ───────────→ (character art)
        ├── art/environments ─────────→ (environment art)
        ├── art/vfx ──────────────────→ (visual effects)
        ├── tech/gameplay ────────────→ (gameplay engineering)
        ├── tech/ui ──────────────────→ (UI engineering)
        ├── tech/audio ───────────────→ (audio engineering)
        └── tech/tools ───────────────→ (tools/pipeline)
```

**Rules:**
- Each sub-team has its own integration branch
- Merges to `development` happen on a defined schedule (daily or bi-daily)
- A designated "merge master" handles cross-team integration
- Automated forward-merging (see [the forward-merge post](automated-forward-merge-game-studio-git-strategy.md)) keeps branches synchronized

**Why it works:** Sub-teams operate semi-independently. The character art team can iterate rapidly without worrying about environment art changes breaking their content. Integration happens at a controlled cadence.

## Very Large Teams (30+ Developers): The Hybrid Approach

At 30+ developers with heavy binary assets, pure Git starts to strain. The practical answer is often a hybrid:

```
┌─────────────────────┐     ┌──────────────────────┐
│   Perforce (P4V)    │     │     Git (GitHub)      │
│                     │     │                       │
│  Binary Assets      │────→│  Source Code          │
│  - Textures         │     │  - C++ / Blueprints   │
│  - Models           │     │  - Build scripts      │
│  - Audio            │     │  - Configuration      │
│  - Animations       │     │  - Documentation      │
│                     │     │                       │
│  Native locking     │     │  Branching & merging  │
│  Efficient binary   │     │  Code review (PRs)    │
│  handling           │     │  CI/CD integration    │
└─────────────────────┘     └──────────────────────┘
```

**When to go hybrid:**
- Repository exceeds 100GB of binary assets
- Git LFS performance degrades with thousands of locked files
- You have a team of artists who don't want to learn Git
- Perforce's native file locking is genuinely better for binary-only workflows

**When to stay pure Git:**
- Your team is willing to learn Git LFS locking workflows
- Your CI/CD is built around Git (GitHub Actions, Azure DevOps)
- You want a single source of truth rather than two systems to maintain

## Binary Asset Coordination

Regardless of team size, binary assets require explicit coordination because they can't be text-merged. Here's the workflow:

### The Locking Protocol

```
Developer A:
  1. git lfs locks                              # Check what's locked
  2. git lfs lock Content/Characters/Hero.uasset # Claim the file
  3. [Edit in Unreal Engine]
  4. git add && git commit && git push
  5. git lfs unlock Content/Characters/Hero.uasset
  6. [Slack notification: "Hero.uasset unlocked"]

Developer B (wants same file):
  1. git lfs locks                              # Sees Hero.uasset is locked
  2. [Coordinates with Developer A or works on something else]
```

### Reducing Lock Contention

The best way to handle binary locking is to need it less often:

1. **Decompose assets**: One Blueprint per actor, not one monolithic Blueprint per system
2. **Use sub-levels**: Split world content across multiple level files
3. **Split data tables**: Category-specific tables instead of one large one
4. **Keep Blueprints thin**: Business logic in C++ (mergeable), visual wiring in Blueprints (lockable)

### Performance Tips for Large Repositories

Artists working with large repos benefit from shallow clones and selective LFS:

```bash
# Shallow clone — limited history, faster initial setup
git clone --depth=1 https://github.com/studio/game.git

# Only pull LFS files you actually need
git lfs pull --include="Content/Characters/*"

# Prune old LFS files to reclaim disk space
git lfs prune
```

This is especially important for onboarding — a full clone of a 200GB Unreal project takes hours. A shallow clone with selective LFS takes minutes.

## Choosing Your Strategy

| Team Size | Strategy | Key Feature |
|-----------|----------|-------------|
| 2-5 | Simple feature branches | Minimal overhead |
| 6-15 | Discipline branches (art/tech) | Isolation by conflict domain |
| 15-30 | Sub-team branches + automation | Scheduled integration + forward-merge |
| 30+ | Hybrid Git + Perforce | Right tool for each file type |

The guiding principle: **add complexity only when simpler approaches break down**. Start with the simplest strategy that could work. Upgrade when you feel the pain, not before.

## References

- [Git LFS](https://git-lfs.com/)
- [Perforce Helix Core](https://www.perforce.com/products/helix-core)
- [Unreal Engine Source Control](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-perforce-as-source-control-for-unreal-engine)
- [Git Branching Models](https://nvie.com/posts/a-successful-git-branching-model/)
