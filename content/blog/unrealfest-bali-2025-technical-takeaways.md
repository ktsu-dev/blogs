---
title: "UnrealFest Bali 2025: Technical Takeaways"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "Key technical insights from UnrealFest Bali 2025 — greyboxing best practices, PCG workflows, Nintendo Switch porting lessons, networked movement synchronization, and cross-platform scalability."
categories: ["Development", "Game Development"]
tags: ["unreal-engine", "game-development", "performance", "conference-notes"]
keywords: ["UnrealFest 2025", "Unreal Engine 5.5", "Nintendo Switch porting", "PCG procedural generation", "networked movement", "cross-platform optimization", "CMC networking"]
slug: "unrealfest-bali-2025-technical-takeaways"
---

# UnrealFest Bali 2025: Technical Takeaways

UnrealFest Bali 2025 packed two days of sessions covering everything from greyboxing workflows to Nintendo Switch porting to networked movement prediction. These are the technical insights I found most actionable — organized by topic rather than by session order.

## Level Design: Work in Instances, Not the Main World

The single most emphasized point across multiple talks: **do not work in the main world**. Even with One File Per Actor (OFPA) and World Partition enabled, working directly in the persistent level creates contention and merge conflicts.

Instead:
- Every developer works in **level instances**
- Instances can embed logic to auto-match terrain height
- **Data layers** organize content by discipline (art, design, audio) so teams don't see or interfere with each other's work
- Runtime layers separate gameplay data from editor-only data

This workflow change alone eliminates the most common source of level-related merge conflicts.

## Procedural Content Generation (PCG): More Than Scatter

PCG in UE 5.5+ is no longer just a mesh scatter tool. Key insights:

- **PCG can replace construction scripts** — and should, for better performance and cleaner assets
- Significantly optimized in 5.6, approaching Blender's geometry nodes in flexibility
- **Use PCG for parametric assets** — buildings with configurable dimensions, procedural terrain decoration, modular environment pieces
- The **Actor Palette** lets you reference another level containing prebuilt assets, enabling asset discovery without rebuilding from scratch
- PCG as part of the production workflow produces cleaner, more performant assets than hand-placed equivalents

## Greyboxing: The Technical Design Toolkit

The greyboxing session introduced a practical pipeline:

1. Use a **cube grid** to define scale standards
2. Knock out basic shapes as **static meshes** (not BSP — those days are over)
3. Use **Packed Level Actors** to bring prebuilt level geometry into worlds (the recommended workflow going forward)
4. Combine multiple static meshes into single actors — individual static mesh actors are overhead-heavy because each one is a full actor

**New in 5.5+:** Convex decomposition in Mesh-to-Collision. Use this instead of "Complex as Simple" for better physics performance.

## State Trees: Use Them for Everything

State Trees were presented as a universal solution, not just for AI:

- Gameplay logic and objective systems
- Door and interactable state management
- Save/load state tracking
- Menu and UI flow management

They're positioned as a superior alternative to traditional state machines, with better debugging tools and cleaner transition logic.

## Camera Best Practices

A clear directive on camera architecture:

- **Don't** put camera logic in PlayerController or Pawn
- **Do** use `PlayerCameraManager` for all camera logic
- Override `BlueprintUpdateCamera` for custom behavior
- Support multiple camera modes through the manager, not through pawn switching
- An experimental **node-based camera plugin** is available for complex camera rigs

## Nintendo Switch Porting: The 33ms Budget

The Switch porting session was a masterclass in constraint-driven development.

### Memory: 3GB is All You Get

- Only 3GB of RAM is usable (out of 4GB total)
- Start development on SDEV (development kit with extra RAM), but test on retail hardware early
- Use **soft references** and **sub-levels** — hard references load everything into memory
- Maximum texture size: 1024 (set via device profiles)
- Maximum 3 concurrent videos, H.264 only
- 64MB save file limit
- Only 1 async operation at a time for load/save (queue if needed, or make synchronous)

### GPU: The Optimization Checklist

With a 33ms frame budget (30 FPS target), every setting matters:

| Setting | Recommended Value |
|---------|------------------|
| Anti-aliasing | FXAA (not MSAA) |
| Texture format | ASTC |
| Forward shading | Off |
| Screen percentage | 66.66% |
| Resolution | 1920x1280 |
| Bloom quality | 2 |
| Temporal AA | 0 |
| Shadow quality | 3, max resolution 1024 |
| Early Z pass | 1 |

Additional constraints:
- Shaders must be under 300 instructions
- Point lights don't have shadows on Switch
- Some material functions aren't available on Switch
- Color output is slightly different from other consoles
- Transform calculations differ slightly — watch for Z-fighting

**Fixing render settings alone resolves 30-40% of GPU bottlenecks.**

### Race Conditions and Execution Order

The Switch's slower CPU and I/O surface race conditions that don't appear on PC:

- Blueprint and C++ execution order may need adjustment
- Operations that complete instantly on PC take measurable time on Switch
- Unreal's hang detection may need disabling for legitimately slow operations
- Test with **4-finger tap on the Nintendo screen** to activate the on-device profiler

### Submission Requirements

The session emphasized: **do not lose submission artifacts**. Keep all master and patch artifacts. A rejection means a 1+ week delay.

Pre-submission checklist:
- Text visibility standards
- Localization compliance
- Button images match Nintendo standards
- Distribution and Shipping configuration
- Run pre-submission check via Nintendo Authoring Tools Editor

## Cross-Platform Scalability

The cross-platform session from the Japanese studio had one overriding message: **profile on real hardware or your results are meaningless**.

### Do Not

- Develop only on PC and test on console late
- Simulate target platforms with PCs matching console specs (drivers, OS, and SDKs differ fundamentally)
- Profile only the lead SKU
- Optimize in editor only

### Do

- Use the **lowest-spec target platform as the lead development SKU**
- Boost quality on higher-spec platforms rather than degrading on lower-spec ones
- Profile all platforms early and continuously
- Automate nightly performance testing for critical areas
- **If performance requirements are met, stop optimizing**

### Scalability Features to Use

UE provides extensive scalability infrastructure that's underutilized:

- **BaseScalability.ini**: Overridable per project, continually refined in new releases
- **DeviceProfiles.ini**: Custom CVars per platform
- **Preview Platform** (updated in 5.6): Includes texture streaming and texture group preview
- **Material Quality Switch**: Different material nodes for different scalability tiers
- **Niagara Scalability**: Per-platform particle budgets
- **Platform Override**: Per-platform LODs for static mesh, skeletal mesh, textures

The challenge isn't the features — it's that artists don't want to manually check each platform. Broader settings (scalability groups) are preferred over per-asset adjustment.

### Nanite/Lumen on Lower Platforms

- Use **Distance Field Ambient Occlusion** instead of Lumen for dynamic skylight on lower-spec platforms
- Combine with SSAO and post-processing for acceptable results
- Fallback polygon meshes (when Nanite can't be used) introduce performance and memory concerns
- **Mesh Streaming** helps mitigate the memory impact

## Networked Movement: The Hardest Problem in Game Development

The networked movement session covered Character Movement Component (CMC) networking in depth.

### The Core Challenge

Movement must be simultaneously:
- **Responsive** — player input feels instant
- **Synchronized** — all clients see the same thing
- **Fair** — no advantage from latency
- **Resistant to exploitation** — cheating is detectable

These goals conflict. Responsiveness requires client-side prediction; synchronization requires server authority. The engineering is in the trade-offs.

### CMC Networking Model

- **Client** records inputs as "saved moves" and sends them to the server
- **Server** performs the same move authoritatively
- On mismatch, the server sends a **correction** and the client **replays** saved moves from the corrected state
- **Move combining** merges similar consecutive inputs before sending (reduces bandwidth, introduces slight delay)
- Disable with `p.NetEnableMoveCombining 0` for testing

### Debugging Network Movement

- Set **fixed latency** in PIE to reproduce server-only corrections
- Add **variable latency** to test RPCs arriving out of order
- Test with **packet loss** for moves that never arrive
- Console command: `p.NetShowCorrections 1` to visualize corrections
- Use **Visual Logger** to add events and play back with a timeline

### Best Practices

- All movement logic must live inside `PerformMovement()` — self-contained, no external tick modifications
- Verify all RPC parameters — accept, reject, or clamp
- Don't predict when there's a high chance of correction
- Don't predict movement effects on other players
- Getting corrected **forward** is less jarring than backward
- **Wind-up animations** smooth over corrections naturally
- Add leniency to correction accounting for jitter, dropped inputs, and the fact that there's no true shared timeline

## Key Takeaways

1. **Work in level instances**, not the main world
2. **PCG is a production tool** now, not just for prototyping
3. **State Trees** are the recommended pattern for all state management
4. **Profile on real hardware** from day one
5. **Lowest-spec platform first** — boost up, don't degrade down
6. **Render settings** fix 30-40% of Switch GPU issues
7. **Automated forward-merging** and CI/CD across all platforms is underutilized but high-impact
8. **Networked movement** is about managing trade-offs, not eliminating latency

## References

- [Unreal Engine 5.5 Release Notes](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5.5-release-notes)
- [PCG Framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-overview)
- [State Trees](https://dev.epicgames.com/documentation/en-us/unreal-engine/state-tree-in-unreal-engine)
- [Character Movement Component](https://dev.epicgames.com/documentation/en-us/unreal-engine/character-movement-component-in-unreal-engine)
- [Nintendo Switch Development](https://developer.nintendo.com/)
