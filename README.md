# ktsu.dev Blog

Welcome to the ktsu.dev technical blog. This is where I share my experiences, insights, and deep dives into software development, debugging adventures, and architectural discoveries.

## Latest Posts

### [Eliminating Primitive Obsession in C# with Semantic Types](./content/blog/csharp-eliminating-primitive-obsession-with-semantic-types.md)

**Published:** February 8, 2026

**Status:** published

**Categories:** Development, C#, Architecture

**Tags:** csharp, type-safety, design-patterns, architecture, dotnet, strong-typing

How wrapping strings and paths in semantic types catches entire categories of bugs at compile time, and a look at the CRTP-based approach used in the ktsu.dev Semantics library.

---

### [C# Object Initializers Run After Code in the Default Constructor](./content/blog/csharp-object-initializers-run-after-code-in-the-default-constructor.md)

**Published:** July 18, 2025

**Status:** published

**Categories:** Development, C#

**Tags:** csharp, object-initializers, constructors

A deep dive into C# object initialization order, explaining why object initializers run after the default constructor and how to handle this behavior effectively.

---

### [C# Using Directives: IDE0055 Format Violations Don't Always Trigger as Expected](./content/blog/csharp-using-directives-inconsistent-formatting-rules.md)

**Published:** July 18, 2025

**Status:** published

**Categories:** Development, C#

**Tags:** csharp, formatting, roslyn, ide0055, using-directives

A deep dive into C# IDE0055 formatting rule's unexpected behavior with using directives, explaining why some formatting issues don't trigger violations and how to handle this quirk.

---

### [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

**Published:** June 14, 2025

**Status:** published

**Categories:** Development, Debugging, Architecture

**Tags:** dotnet, debugging, nuget, msbuild, troubleshooting, build-server, project-guid, visual-studio, git-worktrees, architecture, design-flaw

A deep dive into debugging a cryptic .NET restore error that reveals a fundamental design flaw in MSBuild's GUID-based project identity system and its impact on modern development workflows.

---

## Posts by Category

### Architecture
- [Eliminating Primitive Obsession in C# with Semantic Types](./content/blog/csharp-eliminating-primitive-obsession-with-semantic-types.md)
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

### C#
- [Eliminating Primitive Obsession in C# with Semantic Types](./content/blog/csharp-eliminating-primitive-obsession-with-semantic-types.md)
- [C# Object Initializers Run After Code in the Default Constructor](./content/blog/csharp-object-initializers-run-after-code-in-the-default-constructor.md)
- [C# Using Directives: IDE0055 Format Violations Don't Always Trigger as Expected](./content/blog/csharp-using-directives-inconsistent-formatting-rules.md)

### Debugging
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

### Development
- [Eliminating Primitive Obsession in C# with Semantic Types](./content/blog/csharp-eliminating-primitive-obsession-with-semantic-types.md)
- [C# Object Initializers Run After Code in the Default Constructor](./content/blog/csharp-object-initializers-run-after-code-in-the-default-constructor.md)
- [C# Using Directives: IDE0055 Format Violations Don't Always Trigger as Expected](./content/blog/csharp-using-directives-inconsistent-formatting-rules.md)
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

## Posts by Tags

### .NET and C#
- [C# Object Initializers Run After Code in the Default Constructor](./content/blog/csharp-object-initializers-run-after-code-in-the-default-constructor.md)
- [C# Using Directives: IDE0055 Format Violations Don't Always Trigger as Expected](./content/blog/csharp-using-directives-inconsistent-formatting-rules.md)
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)
- [Eliminating Primitive Obsession in C# with Semantic Types](./content/blog/csharp-eliminating-primitive-obsession-with-semantic-types.md)

### Troubleshooting and Debugging
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

### Development Tools
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

### Architecture and Design
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)
- [Eliminating Primitive Obsession in C# with Semantic Types](./content/blog/csharp-eliminating-primitive-obsession-with-semantic-types.md)

### Build Systems and MSBuild
- [Debugging the Mysterious 'Unable to find a project to restore' Error in .NET](./content/blog/dotnet-project-guid-conflicts-build-server-debugging.md)

## Blog Stats

- **Total Posts:** 4
- **Categories:** 4 (Architecture, C#, Debugging, Development)
- **Most Recent:** February 8, 2026

## About This Blog

This blog focuses on:
- **Deep Technical Dives**: Thorough investigations into complex problems
- **Real-World Debugging**: Actual troubleshooting experiences from development work
- **Architecture Insights**: Analysis of design patterns, flaws, and improvements
- **Developer Tools**: Exploration of development tooling and best practices

## Search and Navigation

All blog posts are written in Markdown and include comprehensive frontmatter with:
- **Categories**: High-level topic groupings
- **Tags**: Specific technology and concept tags
- **Keywords**: SEO and searchability terms
- **Status**: Draft, review, published tracking
- **Dates**: Created and modified timestamps

## Connect

Feel free to open issues or discussions if you have questions about any of the blog posts or want to suggest topics for future articles.

## Automation

This blog index is automatically regenerated when new posts are pushed to the repository, using GitHub Actions.
The workflow runs the scripts/Rebuild-BlogIndex.ps1 PowerShell script to parse all markdown files and rebuild this index.

---

*This blog is maintained as a Git repository to track changes, encourage collaboration, and provide version history for all content.*
