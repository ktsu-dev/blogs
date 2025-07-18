---
title: "C# Using Directives: IDE0055 Format Violations Don't Always Trigger as Expected"
author: "Matt Edmondson"
created: 2025-07-18
modified: 2025-07-18
status: published
description: "A deep dive into C# IDE0055 formatting rule's unexpected behavior with using directives, explaining why some formatting issues don't trigger violations and how to handle this quirk."
categories: ["Development", "C#"]
tags: ["csharp", "formatting", "roslyn", "ide0055", "using-directives"]
keywords: ["C# formatting rules", "IDE0055", "using directives", "C# code analysis", "dotnet code style", "editorconfig"]
slug: "csharp-using-directives-inconsistent-formatting-rules"
---

# C# Using Directives: IDE0055 Format Violations Don't Always Trigger as Expected

When setting up code formatting rules in C# projects, many developers rely on analyzer rules like IDE0055 to enforce consistent code style. However, there's an undocumented quirk with how this rule handles using directive formatting that can lead to confusing results.

## The Unexpected Behavior

I recently discovered and [reported an issue](https://github.com/dotnet/roslyn/issues/77831) in the Roslyn compiler regarding the IDE0055 formatting rule. The issue occurs specifically when configuring using directive formatting with the `dotnet_separate_import_directive_groups` option.

**Here's the surprising discovery**: IDE0055 will only enforce the separation of using directive groups if those directives are already in alphabetical order.

Let me demonstrate this with a simple example:

### Example 1: Alphabetically Sorted Directives (Triggers IDE0055)

```csharp
namespace MyNamespace;

using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using NuGet.Versioning;
using System.Diagnostics;
```

In this case, when `dotnet_separate_import_directive_groups = true` is set in the `.editorconfig` file, the analyzer will correctly flag an IDE0055 violation because the using directives should be separated into groups.

### Example 2: Non-Alphabetically Sorted Directives (No IDE0055 Violation)

```csharp
namespace MyNamespace;

using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using System.Diagnostics;
using NuGet.Versioning;
```

Surprisingly, this code **won't trigger an IDE0055 violation**, even though the using directives still aren't separated into groups. The only difference is that these directives aren't alphabetically sorted.

## Why This Happens

After investigating the Roslyn source code, I found the cause in the `TokenBasedFormattingRule.AdjustNewLinesAfterSemicolonToken()` method. The relevant code contains this conditional check:

```csharp
if (usings.IsSorted(UsingsAndExternAliasesDirectiveComparer.SystemFirstInstance) ||
    usings.IsSorted(UsingsAndExternAliasesDirectiveComparer.NormalInstance))
{
    // Only apply the formatting rule if usings are sorted
    // ...
}
```

This code reveals that the formatting rule intentionally checks if the using directives are already sorted before enforcing group separation. The comment above this code in the Roslyn source even hints at this behavior:

> "if the user is separating using-groups, and we're between two usings, and these usings *should* be separated, then do so (if the usings were already properly sorted)."

## The Documentation Gap

The problem is that this behavior isn't documented anywhere in the official Microsoft documentation for the `dotnet_separate_import_directive_groups` option. The [formatting options documentation](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/dotnet-formatting-options#dotnet%5Fseparate%5Fimport%5Fdirective%5Fgroups) makes no mention of this prerequisite.

## Impact and Implications

This behavior creates several unexpected consequences:

1. **Inconsistent Enforcement**: Code that violates the intended formatting rule might not be flagged if the using directives aren't alphabetically sorted.

2. **Silent Non-Compliance**: Files that appear to follow your team's coding standards might actually violate them without triggering any warnings, leading to codebase inconsistency that's difficult to detect.

3. **Misleading Configuration**: Developers might believe they've correctly configured their project to enforce consistent using directive grouping, only to discover later that some files don't follow the intended pattern.

## Real-World Impact Scenarios

While this might seem like a minor quirk, it can create significant issues in several common development scenarios:

### 1. Enforcing Corporate Coding Standards

For enterprises with strict coding standards enforced through automated tools, this behavior creates a gap in validation. Code that appears compliant might actually violate standards but fly under the radar due to this condition.

### 2. Code Review Inconsistencies and Team Onboarding

When some files trigger violations and others don't for the same logical issue, it creates confusion during code reviews. Reviewers might enforce standards inconsistently across the codebase, leading to arguments and lost productivity.

Similarly, new team members struggle to understand why seemingly identical code patterns are flagged in some files but not others. This increases the learning curve and can lead to frustration and decreased confidence in the tooling.

### 3. Build Server Validation

Many organizations use a "break the build on style violations" approach to ensure code quality. This issue means your build might pass locally but fail on the build server (or vice versa) if different tools or versions are involved in formatting validation.

### 4. Legacy Code Migration

When migrating legacy code to modern standards, relying on automated tooling to find and fix issues becomes problematic if some violations aren't detected. This creates pockets of technical debt that persist through migration efforts.

### 5. Cross-Project Consistency

In solutions with multiple projects that share code or developers, inconsistent formatting rule enforcement leads to subtle differences in formatting patterns across projects, making code navigation and maintenance more difficult.

## The Core Issue

What makes this problem particularly tricky is that standard remediation approaches don't address it:

1. **Combining Rules Doesn't Help**: Even if you configure both `dotnet_sort_system_directives_first` and `dotnet_separate_import_directive_groups` in your `.editorconfig`, the issue persists. The rule still won't trigger on non-alphabetically sorted using directives. While `dotnet_sort_system_directives_first` helps order System namespaces before others, without overall alphabetical order within each group, the separation violation still won't trigger.

2. **Code Cleanup Doesn't Fix It**: Visual Studio's Code Cleanup feature only addresses triggered violations. Since the rule doesn't trigger in the first place for non-sorted usings, Code Cleanup won't detect or fix the issue.

3. **Format Document Won't Catch It**: Similarly, the Format Document command won't identify or fix these non-triggering violations.

## Working Around the Issue

Since typical remediation approaches don't work, here are some practical workarounds:

### 1. Manual Inspection

Until this issue is resolved, you may need to manually review codebases for this specific formatting issue or create custom tooling to check for it.

### 2. Custom Roslyn Analyzer

Consider creating a custom Roslyn analyzer that specifically checks for using directive grouping regardless of sorting order.

### 3. Report and Track the Issue

Follow and engage with the [GitHub issue](https://github.com/dotnet/roslyn/issues/77831) to encourage resolution in a future Roslyn release.

### 4. Documentation and Team Awareness

Make sure your team is aware of this quirk to avoid confusion when formatting issues seem inconsistently enforced.

### 5. Comprehensive EditorConfig

While it won't fully solve the issue, having a comprehensive `.editorconfig` that enforces both sorting and grouping can minimize occurrences when used with manual or automated formatting tools:

```ini
# .editorconfig
# Enforce using directive sorting and grouping
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = true

# Make the rule an error to catch it during build
dotnet_diagnostic.IDE0055.severity = error

# Other related formatting options
csharp_using_directive_placement = outside_namespace

# Note: Sorting order must be applied manually or via tools; this config alone won't enforce grouping unless sorted
```

Then use manual formatting or automated tools (like Code Cleanup) to ensure usings are properly sorted *before* the IDE0055 rule can effectively enforce grouping.

## Affected Tools and Automation

This issue doesn't just affect Visual Studio users—it impacts a wide range of tools and automation systems that rely on .editorconfig and Roslyn analyzers to enforce code standards. Here are some examples:

### 1. CI/CD Pipeline Tools

* **GitHub Actions workflows** that run `dotnet format` to validate pull requests
* **Azure DevOps build pipelines** using tasks that check code formatting 
* **Jenkins jobs** with .NET code quality gates
* **TeamCity build configurations** that fail on code style violations

These systems might inconsistently enforce standards, causing builds to pass that should fail, or creating mysterious failures that are difficult to reproduce locally.

### 2. Code Analysis Tools

* **SonarQube/SonarCloud** analysis might miss these violations in its .NET code style checks
* **NDepend** code rules that incorporate style validation
* **StyleCop Analyzers** may have inconsistent interaction with built-in analyzers
* **JetBrains ReSharper/Rider** code cleanup and inspections

Different analysis tools might report conflicting results based on how they interpret and apply the rules, causing confusion when moving between tools.

### 3. Git Hooks and Pre-Commit Validation

* **Husky.NET** pre-commit hooks running code formatting checks
* **Git pre-commit hooks** using `dotnet format --verify-no-changes`
* **Commitizen** or similar tools that validate code before commit
* **Local git hooks** enforcing company standards

These systems may fail to catch formatting issues that should be fixed before committing.

### 4. Documentation and Code Generation Tools

* **DocFX** or similar tools parsing code comments
* **API documentation generators** that analyze code structure
* **Code generators** that expect specific formatting patterns
* **Markdown documentation** with embedded code examples

Documentation tools might inconsistently format code examples or generate incorrect snippets if they assume consistent formatting rules are applied.

### 5. IDE Extensions and Plugins

* **Visual Studio extensions** for code cleanup and formatting
* **VS Code extensions** like C# Dev Kit
* **Custom IDE plugins** developed for company-specific standards
* **Third-party formatting tools** integrated with IDEs

IDE plugins might apply inconsistent fixes or fail to identify violations properly.

The inconsistency of IDE0055's behavior means these tools can't reliably enforce the intended standards, undermining automated workflows and code quality initiatives throughout the development lifecycle.

## Technical Explanation

The issue occurs because the IDE0055 rule's implementation for `dotnet_separate_import_directive_groups` has a hidden dependency on the sorting state of the using directives.

In the Roslyn codebase, the `UsingsAndExternAliasesOrganizer.NeedsGrouping()` method determines if two namespaces should belong to different groups based on their first token. However, the actual enforcement of group separation only happens if the using directives are already sorted either:

1. Alphabetically, or
2. With `System` namespaces first, followed by other namespaces alphabetically

This implementation detail contradicts the documented behavior of both `dotnet_separate_import_directive_groups` and `dotnet_sort_system_directives_first`.

## Conclusion

This undocumented behavior in IDE0055's handling of using directive formatting represents a gap between expected and actual functionality. While it might be intentional from the Roslyn team's perspective, the lack of documentation leads to confusion and inconsistent code formatting.

For now, awareness of this quirk is the best defense against inconsistent using directive formatting. Hopefully, this issue will be addressed in future versions of the .NET SDK, either by changing the behavior or properly documenting the existing requirements.

> **Note**: The behavior described in this article was verified with .NET SDK version 9.0.201 and Visual Studio 2022 (17.13.5). Future versions of the Roslyn compiler may change this behavior. Readers should re-verify behavior in newer SDK or IDE versions as updates may address or change this behavior.

If you're interested in following the progress on this issue, you can track it on GitHub at [dotnet/roslyn issue #77831](https://github.com/dotnet/roslyn/issues/77831).

## References

- [My Issue Report: Undocumented requirement for import directives to be alphabetically sorted to trigger IDE0055](https://github.com/dotnet/roslyn/issues/77831)
- [Microsoft Docs: .NET formatting options](https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/dotnet-formatting-options)
- [Roslyn GitHub Repository](https://github.com/dotnet/roslyn) 