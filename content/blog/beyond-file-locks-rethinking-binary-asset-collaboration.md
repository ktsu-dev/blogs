---
title: "Beyond File Locks: Rethinking Binary Asset Collaboration"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "A proposal for eliminating file locking in game development through asset decomposition, semantic binary diffing, and automated merge resolution — and the trade-offs involved."
categories: ["Development", "Game Development", "Architecture"]
tags: ["git", "architecture", "game-development", "design-patterns"]
keywords: ["Git LFS locking alternatives", "binary asset merging", "asset decomposition", "game development workflow", "lock-free collaboration", "Unreal Engine asset management"]
slug: "beyond-file-locks-rethinking-binary-asset-collaboration"
---

# Beyond File Locks: Rethinking Binary Asset Collaboration

File locking is the accepted solution for binary assets in game development. You lock a Blueprint, edit it, commit, and unlock. It works — but it serializes work. Two artists who need the same material can't work in parallel. A locked file that someone forgot to unlock blocks an entire team. The question is: can we do better?

This post explores an alternative approach — asset decomposition combined with semantic binary diffing — that could reduce locking by 90% or more. It's a proposal, not a proven solution, and I'll be upfront about the trade-offs and unknowns.

## Why Locking Exists

Binary files (`.uasset`, `.umap`, textures, audio) can't be text-merged. Git sees them as opaque blobs. When two people change the same binary file on different branches, there's no automated way to reconcile the differences — one person's work gets overwritten.

Locking prevents this by making concurrent edits impossible. It's the nuclear option: guaranteed correctness at the cost of parallelism.

The costs are real:
- **Waiting**: Developer B can't touch a file while Developer A has it locked
- **Forgotten locks**: A developer goes on vacation with files locked
- **Lock granularity**: Locking a Blueprint locks *everything in it*, even if two people are editing unrelated parts
- **Performance**: At thousands of locked files, Git LFS lock tracking becomes slow

## The Alternative: Decompose, Diff, Merge

The proposal has three parts:

### 1. Asset Decomposition

Instead of one monolithic Blueprint per system, break it into the smallest meaningful components:

**Before:**
```
Content/
  Characters/
    Hero.uasset          (5 MB — movement, combat, animation, UI, audio)
```

**After:**
```
Content/
  Characters/
    Hero/
      Hero_Base.uasset         (core actor, references the others)
      Hero_Movement.uasset     (movement component)
      Hero_Combat.uasset       (combat logic)
      Hero_Animation.uasset    (animation Blueprint)
      Hero_UI.uasset           (HUD elements)
      Hero_Audio.uasset        (sound cues)
```

Now two developers can work on `Hero_Combat.uasset` and `Hero_Animation.uasset` simultaneously — no locking needed because they're different files.

This isn't just a theoretical improvement. Unreal Engine already supports this architecture through:
- **Blueprint Interfaces** for decoupling components
- **Actor Components** for modular functionality
- **Data Assets** for separating configuration from logic
- **Sub-levels** for separating world content

The discipline required is decomposing assets *before* they become monolithic, not after.

### 2. Semantic Binary Diffing

For the remaining cases where two people do edit the same file, a semantic diff tool could identify whether the changes actually conflict:

**True conflict** (needs manual resolution):
- Both developers changed the same node in a Blueprint graph
- Both modified the same material parameter

**False conflict** (auto-resolvable):
- Developer A added a new node; Developer B modified an existing node
- Developer A changed a texture reference; Developer B changed a mesh reference

A tool that understands the internal structure of `.uasset` files could distinguish these cases. Epic's Blueprint diff tool (`BPDiff`) already does this for visualization — the challenge is making it work for automated merging.

### The Technical Components

A full implementation would need:

1. **Asset Decomposition Service**: Analyzes monolithic assets, extracts components, maintains references between them
2. **Binary Differencing Engine**: Parses UAsset format, detects property-level changes, understands Blueprint graph structure
3. **Merge Resolution System**: Applies rule-based automatic merging for non-conflicting changes, flags true conflicts for manual resolution
4. **Workflow Integration**: Git hooks that run decomposition checks, editor plugins that enforce the component structure

### Implementation Phases

**Phase 1 — Foundation (1-2 months):** Prototype asset decomposition for the most common asset types. Build basic binary diffing that can identify changed properties in a UAsset.

**Phase 2 — Core Systems (2-3 months):** Complete the differencing engine for all major asset types. Implement automated merge for the "easy" cases (non-overlapping changes).

**Phase 3 — Integration (2-3 months):** Hook into Git workflows. Build the Unreal Editor plugin. Migrate existing assets to decomposed structure.

## Expected Outcomes

If the approach works as designed:
- **90-95% reduction in locked files** — most files become small enough that concurrent edits are rare
- **80% reduction in merge conflicts** — semantic diffing resolves false conflicts automatically
- **70% decrease in waiting time** — developers can work in parallel on related content
- **50% improvement in parallel development capacity** — the team does more work simultaneously

## The Trade-offs

This proposal has significant costs and risks:

### Complexity

A decomposed asset structure is harder to navigate. Instead of opening one `Hero.uasset`, you're managing six files. Tooling can mitigate this (an editor extension that opens all related components), but it's additional infrastructure.

### Binary Format Dependency

Semantic diffing requires intimate knowledge of the `.uasset` format. Epic doesn't guarantee format stability across engine versions. A major format change could break the differencing engine and require significant rework.

### Merge Correctness

Automated binary merging is inherently risky. Text merge has decades of battle-testing; binary merge is novel. A merge that produces a structurally valid but semantically broken Blueprint is worse than a merge conflict — at least conflicts are visible.

### Migration Cost

Converting existing monolithic assets to a decomposed structure is a significant project. Every Blueprint, every material, every data table needs to be analyzed and potentially restructured. For a project in production, this may not be feasible.

## When This Makes Sense

**Good fit:**
- New projects that can adopt decomposed architecture from the start
- Teams where lock contention is a measurable bottleneck (>30% of asset work involves waiting for locks)
- Studios investing in custom tooling anyway

**Poor fit:**
- Projects in late production (migration cost too high)
- Small teams (2-5 people can coordinate verbally)
- Teams without engine-level C++ expertise to build and maintain the tooling

## What You Can Do Today

Even without the full tooling, the asset decomposition strategy works with existing tools:

1. **Use Actor Components** for modular Blueprint logic
2. **Split Blueprints** along functional boundaries (movement, combat, UI)
3. **Use Data Assets** to separate tuning values from logic
4. **Split levels into sub-levels** by area and discipline
5. **Keep Blueprints thin** — put complex logic in C++ (which *can* be text-merged)

These practices reduce lock contention immediately, without any custom tooling.

## References

- [Unreal Engine Blueprint Best Practices](https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-best-practices-in-unreal-engine)
- [Git LFS File Locking](https://git-lfs.com/)
- [Actor Components](https://dev.epicgames.com/documentation/en-us/unreal-engine/components-in-unreal-engine)
- [Data Assets in UE](https://dev.epicgames.com/documentation/en-us/unreal-engine/data-assets-in-unreal-engine)
