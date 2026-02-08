---
title: "Eliminating Primitive Obsession in C# with Semantic Types"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: published
description: "How wrapping strings and paths in semantic types catches entire categories of bugs at compile time, and a look at the CRTP-based approach used in the ktsu.dev Semantics library."
categories: ["Development", "C#", "Architecture"]
tags: ["csharp", "type-safety", "design-patterns", "architecture", "dotnet", "strong-typing"]
keywords: ["primitive obsession", "strong typing C#", "semantic types", "CRTP pattern", "type-safe strings", "domain-driven design", "value objects"]
slug: "csharp-eliminating-primitive-obsession-with-semantic-types"
---

# Eliminating Primitive Obsession in C# with Semantic Types

Most C# codebases are riddled with a code smell so common we barely notice it: **primitive obsession**. We pass `string` where we mean an email address, a file path, a repository name, or a URL. We pass `double` where we mean meters, kilograms, or seconds. The type system sees them all the same way, so the compiler can't help us when we accidentally pass a username where a password was expected.

This post explores what primitive obsession costs us in practice, and how a technique built on the **Curiously Recurring Template Pattern (CRTP)** can eliminate entire categories of bugs at compile time.

## The Problem: When Everything Is a String

Consider a method signature you might see in any codebase:

```csharp
public void CloneRepository(string name, string remotePath, string localPath)
{
    // ...
}
```

Nothing stops a caller from writing:

```csharp
// Oops — arguments in the wrong order
CloneRepository(remotePath, name, localDirectory);
```

The compiler is perfectly happy. The types all match: `string`, `string`, `string`. The bug won't surface until runtime — maybe not until production.

This isn't a contrived example. Anytime a method takes two or more parameters of the same primitive type, the door is open for transposition bugs. And the more parameters you have, the worse it gets.

### The Same Problem With Paths

Paths are especially treacherous. A `string` can hold an absolute path, a relative path, a directory path, or a file path. The compiler doesn't know or care which one you meant:

```csharp
string configDir = @"C:\app\config";
string logFile = @"logs\app.log";

// This compiles fine but is semantically wrong —
// we're treating a relative path as an absolute one
File.Delete(logFile);

// And this silently produces garbage —
// combining two absolute paths doesn't do what you'd expect
string combined = Path.Combine(configDir, @"C:\other\path");
// Result: "C:\other\path" — the first argument is silently discarded
```

## The Solution: Semantic Types

The fix is to make the type system carry the semantic meaning that `string` throws away. Instead of `string`, use distinct types that the compiler can distinguish:

```csharp
public sealed record GitRepositoryName : SemanticString<GitRepositoryName> { }
public sealed record GitRepositoryWebURI : SemanticString<GitRepositoryWebURI> { }
public sealed record GitRepositoryRemotePath : SemanticString<GitRepositoryRemotePath> { }
```

Each of these is a one-line declaration, but it creates a completely distinct type. Now the method signature becomes self-documenting *and* compiler-enforced:

```csharp
public void CloneRepository(
    GitRepositoryName name,
    GitRepositoryRemotePath remotePath,
    AbsoluteDirectoryPath localPath)
{
    // ...
}
```

Try transposing the arguments now — the compiler will refuse to build.

This is exactly the approach used in the [ktsu.dev Semantics library](https://github.com/ktsu-dev/Semantics). The `GitRepository` class from the ktsu.dev ecosystem looks like this in practice:

```csharp
public class GitRepository
{
    public GitRepositoryName Name { get; init; } = new();
    public GitRepositoryWebURI WebURI { get; init; } = new();
    public GitRepositoryRemotePath RemotePath { get; init; } = new();
    public AbsoluteDirectoryPath LocalPath { get; init; } = new();

    public bool IsCloned => Directory.Exists(LocalPath);
}
```

Every property has a distinct type. You can't accidentally assign a `GitRepositoryName` to a `GitRepositoryWebURI` — the compiler won't let you.

## How It Works: The Curiously Recurring Template Pattern

The foundation of this approach is a base class that uses CRTP (sometimes called the "self-referencing generic" pattern in C#):

```csharp
public abstract record SemanticString<TDerived> : ISemanticString
    where TDerived : SemanticString<TDerived>
{
    public string WeakString { get; init; } = string.Empty;

    // Factory method — creates an instance of any semantic string type
    public static TDest Create<TDest>(string? value)
        where TDest : SemanticString<TDest>
    {
        TDest newInstance = FromStringInternal<TDest>(value);
        return PerformValidation(newInstance);
    }

    // Implicit conversion back to string — no ceremony needed
    public static implicit operator string(SemanticString<TDerived>? value)
        => value?.WeakString ?? string.Empty;
}
```

The `TDerived` type parameter is the key. It means the base class knows the *exact* derived type, so factory methods like `Create` can return the correct concrete type without casting. Creating a semantic string looks like this:

```csharp
var repoName = GitRepositoryName.Create("my-project");
```

And because of the implicit conversion to `string`, you can pass it to any API that expects a regular string with zero friction:

```csharp
Console.WriteLine($"Cloning {repoName}...");  // Just works
```

The property name `WeakString` is deliberately chosen — accessing the raw string is an escape hatch that breaks type safety, and the name makes that cost visible in code reviews.

### The `.As<T>()` Extension Method

The `Create` factory method works, but the library provides something even more fluent: an `As<T>()` extension method on `string` itself:

```csharp
public static class SemanticStringExtensions
{
    public static TDerived As<TDerived>(this string? value)
        where TDerived : SemanticString<TDerived>
        => SemanticString<TDerived>.Create<TDerived>(value);
}
```

This lets you write:

```csharp
var repoName = "my-project".As<GitRepositoryName>();
```

The string literal reads first, followed by the type you're casting it *into*. It flows like natural language: "take this string *as* a GitRepositoryName." Compare:

```csharp
// Factory method — type comes first, then the value
var repoName = GitRepositoryName.Create("my-project");

// Extension method — value comes first, then the type
var repoName = "my-project".As<GitRepositoryName>();
```

Both do the same thing — canonicalization and validation run either way. But `.As<T>()` shines when you're chaining or working inline:

```csharp
repository.Name = config["repo-name"].As<GitRepositoryName>();
```

The same `.As<T>()` pattern works for converting between semantic types too. If you already have one semantic string and need to view it as another type, the instance method on the base class does the same thing:

```csharp
var repoName = "my-project".As<GitRepositoryName>();
var displayLabel = repoName.As<DisplayLabel>();  // re-validates for the target type
```

From here on, we'll use `.As<T>()` as the primary way to create semantic values.

## A Richer Example: Type-Safe Paths

Semantic strings really shine when you build a type hierarchy on top of them. The Semantics library defines a path type system with validation baked in:

```
SemanticString<T>
  └─ SemanticPath<T>          [IsPath]
       ├─ SemanticDirectoryPath<T>
       │    ├─ AbsoluteDirectoryPath  [IsAbsolutePath]
       │    └─ RelativeDirectoryPath  [IsRelativePath]
       └─ SemanticFilePath<T>
            ├─ AbsoluteFilePath       [IsAbsolutePath]
            └─ RelativeFilePath       [IsRelativePath]
```

Each level in the hierarchy adds validation through attributes. `[IsPath]` ensures no invalid path characters; `[IsAbsolutePath]` ensures the path is fully qualified. The validation happens automatically at creation time — you can't construct an `AbsoluteDirectoryPath` from a relative path string.

### Operator Overloading for Natural Path Composition

The path types overload the `/` operator for path combination, and the return type changes based on what you're combining:

```csharp
var outputDir = @"C:\output".As<AbsoluteDirectoryPath>();
var logFile = @"logs\app.log".As<RelativeFilePath>();
var readme = "README.md".As<FileName>();

// Directory / RelativeFile → AbsoluteFilePath
AbsoluteFilePath fullLogPath = outputDir / logFile;

// Directory / FileName → AbsoluteFilePath
AbsoluteFilePath readmePath = outputDir / readme;

// Directory / RelativeDirectory → AbsoluteDirectoryPath
var subDir = "subdir".As<RelativeDirectoryPath>();
AbsoluteDirectoryPath nested = outputDir / subDir;

// Convert between semantic types with the instance .As<T>()
AbsolutePath genericPath = fullLogPath.As<AbsolutePath>();
```

Each `/` overload returns the correct result type. Combining an absolute directory with a relative file gives you an absolute file — not a `string` that you have to hope is correct.

Compare this to `Path.Combine`:

```csharp
// Path.Combine returns string — no type information about what kind of path this is
string result = Path.Combine(@"C:\output", @"logs\app.log");
// Is this a file? A directory? Absolute? Relative? The type doesn't say.
```

### Relationship Queries

Because the types carry semantic meaning, the library can provide operations that would be meaningless on raw strings:

```csharp
var project = @"C:\projects\myapp".As<AbsoluteDirectoryPath>();
var src = @"C:\projects\myapp\src".As<AbsoluteDirectoryPath>();

bool isChild = src.IsChildOf(project);        // true
bool isParent = project.IsParentOf(src);       // true

// Walk up the directory tree
foreach (var ancestor in src.GetAncestors())
{
    Console.WriteLine(ancestor);
}

// Get a relative path between two absolute paths
RelativeDirectoryPath relative = project.GetRelativePathTo(src);
```

These methods use span-based comparison internally for performance, but the type system ensures you can only call `IsChildOf` with another `AbsoluteDirectoryPath` — not with a file path, a relative path, or an arbitrary string.

## Validation: Compile-Time + Runtime

Semantic types work at two levels:

1. **Compile-time**: The type system prevents mixing incompatible types entirely. You can't pass an `AbsoluteFilePath` where an `AbsoluteDirectoryPath` is expected.

2. **Runtime**: Validation attributes check constraints that can't be expressed in the type system alone (valid path characters, fully qualified paths, etc.).

The validation uses an attribute-based system:

```csharp
[IsPath]
public abstract record SemanticPath<TDerived> : SemanticString<TDerived>
    where TDerived : SemanticPath<TDerived>
{ }

[IsAbsolutePath]
public sealed record AbsoluteDirectoryPath : SemanticDirectoryPath<AbsoluteDirectoryPath>
{ }
```

The `[IsPath]` attribute validates that the string contains no invalid path characters and has a reasonable length. The `[IsAbsolutePath]` attribute validates that the path is fully qualified. These checks run automatically when you call `.As<T>()` or `Create` — if the string doesn't meet the requirements, you get an exception immediately, not a silent failure at some later point.

There's also a `TryCreate` method for cases where you're dealing with user input or external data:

```csharp
if (AbsoluteDirectoryPath.TryCreate(userInput, out var path))
{
    // path is guaranteed to be valid
}
else
{
    // handle invalid input
}
```

## The Cost and the Tradeoff

Semantic types aren't free. Here's what they cost:

- **One-line type declarations** for each semantic concept in your domain
- **`.As<T>()` calls** instead of raw string assignment (though implicit conversion back to string is free)
- **A dependency** on the base library

But consider what you get:
- Transposition bugs become **compile errors** instead of runtime mysteries
- Method signatures become **self-documenting** — the types *are* the documentation
- Invalid values are caught **at the boundary** where they enter your system, not deep in your business logic
- Path operations are **type-safe** — no more guessing whether a string is a file or directory, absolute or relative

In my experience maintaining a monorepo of 79+ .NET libraries, the upfront cost of defining semantic types pays for itself quickly. The bugs that *don't happen* are the ones you never have to debug.

## Getting Started

If you want to try this approach in your own codebase, you don't need to go all-in. Start with the areas where primitive obsession causes the most pain:

1. **Method signatures with multiple string parameters** — these are transposition bugs waiting to happen
2. **File path handling** — the distinction between absolute/relative and file/directory is worth encoding in types
3. **Domain identifiers** — user IDs, order numbers, API keys — anything where mixing them up would be a bug

Define a semantic type for each concept:

```csharp
public sealed record UserId : SemanticString<UserId> { }
public sealed record OrderNumber : SemanticString<OrderNumber> { }
public sealed record ApiKey : SemanticString<ApiKey> { }
```

Three lines. Now the compiler is working for you.

## References

- [ktsu.dev Semantics library on GitHub](https://github.com/ktsu-dev/Semantics)
- [Primitive Obsession — Refactoring Guru](https://refactoring.guru/smells/primitive-obsession)
- [Curiously Recurring Template Pattern](https://en.wikipedia.org/wiki/Curiously_recurring_template_pattern)
- [Domain-Driven Design: Value Objects](https://martinfowler.com/bliki/ValueObject.html)
- [C# Record Types](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record)
