---
title: "Managing 79+ .NET Projects: Build Infrastructure at Scale"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "How a custom MSBuild SDK, topological dependency sorting, automated versioning, and cross-repo synchronization keep 79+ independent .NET libraries building and publishing consistently."
categories: ["Development", "C#", "Architecture"]
tags: ["dotnet", "msbuild", "nuget", "architecture", "devops"]
keywords: ["MSBuild SDK", ".NET monorepo", "NuGet package management", "semantic versioning automation", "topological sort dependencies", "multi-project build system"]
slug: "managing-79-dotnet-projects-build-infrastructure-at-scale"
---

# Managing 79+ .NET Projects: Build Infrastructure at Scale

The ktsu.dev ecosystem is a collection of 79+ independent .NET libraries and applications, each in its own repository with its own solution, CI pipeline, and NuGet package. Keeping them consistent, buildable, and correctly versioned is a non-trivial infrastructure problem.

This post describes the three pillars that make it work: a custom MSBuild SDK that standardizes build configuration, a dependency-aware build orchestrator, and an automated versioning system driven by git history.

## The Problem: 79 Copies of Everything

Without shared infrastructure, each project needs its own:
- `.csproj` configuration (target frameworks, package metadata, analyzer settings)
- CI/CD workflow (build, test, pack, publish)
- Version calculation logic
- License, changelog, and metadata generation

At 79+ projects, copy-pasting this configuration is unsustainable. One change — say, adding .NET 10 as a target framework — requires 79 separate PRs. Configuration drift is inevitable.

## Pillar 1: A Custom MSBuild SDK

The solution is a custom MSBuild SDK (`ktsu.Sdk`) that every project imports with a single line:

```xml
<Project Sdk="ktsu.Sdk">
  <!-- That's it. No target frameworks, no metadata, no analyzer config. -->
</Project>
```

The SDK provides:

### Automatic Multi-Targeting

```xml
<!-- Sdk/Sdk.props -->
<PropertyGroup>
  <TargetFrameworks>net10.0;net9.0;net8.0;net7.0;net6.0;net5.0;netstandard2.0;netstandard2.1</TargetFrameworks>
</PropertyGroup>
```

Every library automatically targets all supported frameworks. Test projects override this to target only the latest:

```xml
<!-- Test projects detect automatically -->
<PropertyGroup Condition="'$(IsTestProject)' == 'true'">
  <TargetFramework>net10.0</TargetFramework>
</PropertyGroup>
```

### Metadata From Markdown Files

Instead of embedding package metadata in `.csproj`, the SDK reads it from markdown files at the solution root:

```xml
<!-- Sdk/Sdk.props — reads VERSION.md, DESCRIPTION.md, AUTHORS.md, TAGS.md -->
<PropertyGroup>
  <Version>$([System.IO.File]::ReadAllText('$(SolutionDir)VERSION.md').Trim())</Version>
  <Description>$([System.IO.File]::ReadAllText('$(SolutionDir)DESCRIPTION.md').Trim())</Description>
  <Authors>$([System.IO.File]::ReadAllText('$(SolutionDir)AUTHORS.md').Trim())</Authors>
  <PackageTags>$([System.IO.File]::ReadAllText('$(SolutionDir)TAGS.md').Trim())</PackageTags>
</PropertyGroup>
```

This means `README.md`, `DESCRIPTION.md`, `AUTHORS.md`, and `TAGS.md` are the single source of truth for package metadata. Updating a description is just editing a markdown file — no XML involved.

### Sub-SDKs for Application Types

Libraries use the base `ktsu.Sdk`. GUI applications use `ktsu.Sdk.App`:

```xml
<!-- Sdk.App/Sdk.props -->
<PropertyGroup>
  <OutputType Condition="$([MSBuild]::IsOSPlatform('Windows'))">WinExe</OutputType>
  <OutputType Condition="!$([MSBuild]::IsOSPlatform('Windows'))">Exe</OutputType>
</PropertyGroup>
```

Console apps use `ktsu.Sdk.ConsoleApp`. The SDK handles the platform-specific differences so individual projects don't have to.

## Pillar 2: Dependency-Aware Build Ordering

With 79+ projects that depend on each other, build order matters. If library A depends on library B, you must build B first and publish it to NuGet before A can resolve its dependency.

The `CrossRepoActions` tool solves this with a topological sort:

```csharp
internal static Collection<Solution> SortSolutionsByDependencies(
    ICollection<Solution> solutions)
{
    var unsatisfied = solutions.ToCollection();
    var sorted = new Collection<Solution>();

    while (unsatisfied.Count != 0)
    {
        // Find all packages from unsatisfied solutions
        var unsatisfiedPackages = unsatisfied
            .SelectMany(s => s.Packages)
            .ToCollection();

        // A solution is "satisfied" if none of its dependencies
        // are produced by other unsatisfied solutions
        var satisfied = unsatisfied
            .Where(s => !s.Dependencies
                .IntersectBy(unsatisfiedPackages.Select(p => p.Name), p => p.Name)
                .Any())
            .ToCollection();

        foreach (var solution in satisfied)
        {
            unsatisfied.Remove(solution);
            sorted.Add(solution);
        }
    }

    return sorted;
}
```

This produces a build order where every project's dependencies are already built and published before it starts building. The algorithm:

1. Find all solutions whose dependencies are *not* produced by any remaining unbuild solution
2. Those solutions can build in parallel (their deps are already available)
3. Remove them from the unsatisfied set
4. Repeat until everything is built

The result is a layered build: `Abstractions` builds first (no dependencies), then `Common` implementations, then consumer libraries, then applications.

## Pillar 3: Git-Driven Versioning

Versions are calculated automatically from git history by `make-version.ps1`. The rules:

1. **Find the last git tag** (format: `vX.Y.Z` or `vX.Y.Z-pre.N`)
2. **Scan commits since that tag** for version markers:
   - `[major]` in a commit message → bump major version
   - `[minor]` → bump minor
   - `[patch]` → bump patch
   - `[pre]` → bump pre-release number
3. **If no markers found**, auto-detect from changed files:
   - `.cs` files changed → minor bump (new functionality assumed)
   - Only docs/CI changed → patch bump
   - No substantive changes → pre-release bump

### Example Commit Messages

```
[major] Rename IProvider to IBaseProvider (breaking change)
[minor] Add async overloads to HashProvider
[patch] Fix null reference in FileSystemProvider
[pre] Experimental compression algorithm support
```

### The Release Pipeline

```
Push to main
  → make-version.ps1 calculates version from git history
  → make-changelog.ps1 generates CHANGELOG.md from commits
  → make-license.ps1 ensures LICENSE.md is current
  → commit-metadata.ps1 commits the generated files
  → dotnet build → dotnet test → dotnet pack
  → Publish to NuGet
  → Create GitHub release with version tag
```

The entire pipeline is hands-off after the initial push. No manual version bumping, no changelog editing, no release creation.

## Cross-Repository Synchronization

With 79+ repositories, CI workflows and scripts need to stay in sync. The `SyncFileContents` tool handles this:

- `.github/workflows/project.yml` — the standard build/test/publish workflow
- `.github/workflows/dependabot-merge.yml` — auto-merge for dependency updates
- Common scripts (`make-version.ps1`, `make-changelog.ps1`, etc.)

When a template file changes in the SDK repository, `SyncFileContents` propagates it to all 79+ repos. This is the mechanism that makes "add .NET 10 targeting" a single change rather than 79.

## The ProjectDirector GUI

For day-to-day management, the `ProjectDirector` application provides a visual dashboard:

- **Repository status**: which repos have uncommitted changes, pending PRs, or failed builds
- **Dependency graph**: visual representation of which libraries depend on which
- **Batch operations**: trigger builds, sync files, or update dependencies across multiple repos
- **Visual diff**: compare configuration across repositories to spot drift

This is the "control plane" for the ecosystem — it makes the scale manageable for a single maintainer.

## Lessons Learned

**What works well:**
- The custom SDK eliminates configuration drift completely
- Git-based versioning means versions are always deterministic and reproducible
- Topological build ordering handles complex dependency chains automatically
- Markdown-based metadata is easy to read and edit

**What's still hard:**
- MSBuild caching can be aggressive — changes to the SDK sometimes require `--no-incremental` builds
- Circular dependencies would break the topological sort (so they're structurally prevented)
- Multi-targeting across 8 frameworks means build times are significant
- NuGet package propagation takes time — a change in `Abstractions` can cascade through 20+ dependent packages

**The key insight:** at this scale, the build system *is* the product. The individual libraries are simple. The complexity lives in keeping 79+ of them consistent, correctly versioned, and building in the right order. Investing in build infrastructure pays dividends on every subsequent change.

## References

- [Custom MSBuild SDKs](https://learn.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk)
- [Central Package Management](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management)
- [Topological Sorting](https://en.wikipedia.org/wiki/Topological_sorting)
- [Semantic Versioning](https://semver.org/)
- [GitHub Actions](https://docs.github.com/en/actions)
