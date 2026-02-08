---
title: "Threading and Synchronization Patterns in Production .NET Libraries"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "Practical threading patterns from production .NET code — lock objects as parameters, thread dispatch queues, ReaderWriterLockSlim vs Lock, and how to actually test for thread safety."
categories: ["Development", "C#", "Architecture"]
tags: ["csharp", "dotnet", "threading", "concurrency", "design-patterns"]
keywords: ["C# threading patterns", "synchronization .NET", "ConcurrentQueue", "ReaderWriterLockSlim", "Lock type .NET 9", "thread safety testing", "Interlocked", "Parallel.ForEach"]
slug: "csharp-threading-synchronization-patterns-production-libraries"
---

# Threading and Synchronization Patterns in Production .NET Libraries

Threading bugs are the kind that make you question your career choices. They're intermittent, hard to reproduce, and often only surface under load in production. After maintaining dozens of .NET libraries that need to be thread-safe, I've settled on a set of patterns that make concurrency explicit, testable, and — most importantly — boring.

This post walks through the threading patterns I use across the ktsu.dev library ecosystem, with real code from production libraries.

## Pattern 1: Lock Objects as Parameters

The most common threading mistake is hiding synchronization inside a class where callers can't see or coordinate with it. The ktsu.dev libraries take a different approach: **make the lock object a parameter**.

```csharp
public static TDest DeepClone<TItem, TDest>(
    this IEnumerable<TItem> items, object lockObj)
    where TItem : class, IDeepCloneable<TItem>
    where TDest : ICollection<TItem>, new()
{
    ArgumentNullException.ThrowIfNull(items);
    ArgumentNullException.ThrowIfNull(lockObj);
    lock (lockObj)
    {
        return DeepClone<TItem, TDest>(items);
    }
}
```

Why pass the lock object in? Because the **caller** knows what else needs to be synchronized with this operation. If you bury the lock inside the method, you force callers to trust that your internal lock covers everything they need — and it usually doesn't.

This pattern makes threading contracts explicit:
- The method signature tells you: "this operation requires synchronization"
- The caller decides which lock to use, enabling coordination across multiple operations
- Null validation on the lock object catches mistakes immediately

The naming convention reinforces this — methods that accept a lock object use names like `ForEach(lockObj, action)` or `DeepClone<T>(items, lockObj)`, making the threading requirement visible at every call site.

## Pattern 2: Thread Dispatch Queues

When you need to ensure operations run on a specific thread (UI updates, resource access), a dispatch queue is cleaner than scattering `Invoke` calls everywhere. The [Invoker](https://github.com/ktsu-dev/Invoker) library implements this:

```csharp
public class Invoker
{
    private int ThreadId { get; } = Environment.CurrentManagedThreadId;
    internal ConcurrentQueue<Task> TaskQueue { get; } = new();

    public async Task InvokeAsync(Action func)
    {
        Ensure.NotNull(func);

        if (ThreadId == Environment.CurrentManagedThreadId)
        {
            func();  // Same thread — execute immediately
            return;
        }

        Task task = new(func);
        TaskQueue.Enqueue(task);
        await task.ConfigureAwait(false);
    }

    public void DoInvokes()
    {
        if (ThreadId != Environment.CurrentManagedThreadId)
        {
            throw new InvalidOperationException(
                "This method must be called on the thread that created the Invoker instance.");
        }

        while (TaskQueue.TryDequeue(out Task? task))
        {
            task.RunSynchronously();
        }
    }
}
```

The pattern is:
1. **Capture the thread ID** at construction time
2. **Same-thread calls execute immediately** — no queueing overhead
3. **Cross-thread calls enqueue** and await completion
4. **The owning thread drains the queue** when it's ready (typically in an update loop)

The `ConcurrentQueue<Task>` handles the producer-consumer synchronization. `ConfigureAwait(false)` avoids deadlocks by not trying to resume on the original context. And the thread ID check in `DoInvokes` prevents accidental misuse.

This is used throughout the [ImGuiApp](https://github.com/ktsu-dev/ImGuiApp) framework to marshal operations onto the render thread:

```csharp
public static Invoker Invoker { get; internal set; } = null!;

// From any thread:
await ImGuiApp.Invoker.InvokeAsync(() => UpdateTexture(newData));
```

## Pattern 3: Preventing Overlapping Execution

The [IntervalAction](https://github.com/ktsu-dev/IntervalAction) library runs an action on a timer — but it must guarantee that slow executions don't overlap. Here's the core of the pattern:

```csharp
public class IntervalAction
{
    private Lock Lock { get; } = new();
    internal bool ShouldPoll { get; set; }
    internal Task? ActionTask { get; set; }
    internal DateTimeOffset LastRunTime { get; set; } = DateTimeOffset.MinValue;

    internal bool TryRun()
    {
        // Check if previous task completed (and propagate exceptions)
        if (ActionTask?.IsCompleted ?? false)
        {
            if (ActionTask.Exception is not null)
                throw ActionTask.Exception.GetBaseException();
            ActionTask = null;
        }

        DateTimeOffset lastRunTime;
        lock (Lock) { lastRunTime = LastRunTime; }

        if (ActionInterval >= TimeSpan.Zero
            && ActionTask is null
            && DateTimeOffset.Now - lastRunTime > ActionInterval)
        {
            ActionTask = Task.Run(() =>
            {
                if (IntervalType == IntervalType.FromLastStart)
                    lock (Lock) { LastRunTime = DateTimeOffset.Now; }

                Action();

                if (IntervalType == IntervalType.FromLastCompletion)
                    lock (Lock) { LastRunTime = DateTimeOffset.Now; }
            });

            return true;
        }
        return false;
    }
}
```

Key decisions here:

- **`ActionTask is null` guards against overlap** — if a task is still running, `TryRun` is a no-op
- **Lock scopes are minimal** — only protecting reads and writes of `LastRunTime`, not the action itself
- **Two interval modes**: `FromLastStart` timestamps before the action, `FromLastCompletion` timestamps after. This matters when actions have variable duration
- **Exceptions propagate on the next poll** rather than being silently swallowed

## Pattern 4: ReaderWriterLockSlim to Lock Migration

.NET 9 introduced the `Lock` type — simpler, faster, and doesn't need disposal. But if you're multi-targeting, you need both. The [MachineMonitor](https://github.com/ktsu-dev/MachineMonitor) project shows this with conditional compilation:

```csharp
public record MetricHistory(TimeSpan Duration, string Unit = "") : IDisposable
{
#if NET9_0_OR_GREATER
    private readonly Lock _lock = new();
#else
    private readonly ReaderWriterLockSlim _lock = new();
#endif

    public float Current
    {
        get
        {
#if NET9_0_OR_GREATER
            lock (_lock) { return Values.Count > 0 ? Values.Back() : 0; }
#else
            try
            {
                _lock.EnterReadLock();
                return Values.Count > 0 ? Values.Back() : 0;
            }
            finally { _lock.ExitReadLock(); }
#endif
        }
    }

    public void Add(float value)
    {
#if NET9_0_OR_GREATER
        lock (_lock) { /* write logic */ }
#else
        try
        {
            _lock.EnterWriteLock();
            // same write logic
        }
        finally { _lock.ExitWriteLock(); }
#endif
    }
}
```

When to choose which:
- **`Lock` (.NET 9+)**: Simpler, no disposal needed, good enough for most cases
- **`ReaderWriterLockSlim`**: When you have many concurrent readers and infrequent writers, the read/write distinction can improve throughput
- **`lock` on `object`**: Still fine for simple cases, but `Lock` is strictly better on .NET 9+

The `try/finally` pattern with `ReaderWriterLockSlim` is verbose but necessary — if the protected code throws, you *must* release the lock.

## Pattern 5: Thread-Safe Singletons

The [CredentialCache](https://github.com/ktsu-dev/CredentialCache) library uses a singleton with a twist — it must be configurable *before* first access:

```csharp
public sealed class CredentialCache : IDisposable
{
    private static readonly object _lock = new();
    private static CredentialCache? _instance;
    private static IPersistenceProvider<string>? _persistenceProvider;

    public static CredentialCache Instance
    {
        get
        {
            lock (_lock)
            {
                if (_instance is null)
                {
                    _persistenceProvider ??= CreateDefaultPersistenceProvider();
                    _instance = new CredentialCache(_persistenceProvider);
                }
                return _instance;
            }
        }
    }

    public static void ConfigurePersistenceProvider(
        IPersistenceProvider<string> persistenceProvider)
    {
        lock (_lock)
        {
            if (_instance is not null)
                throw new InvalidOperationException(
                    "Cannot configure after instance has been created.");
            _persistenceProvider = persistenceProvider;
        }
    }
}
```

The interesting part is the `ConfigurePersistenceProvider` method — it shares the same lock as `Instance` and throws if you try to configure after the instance exists. This makes the initialization ordering explicit and enforced rather than relying on documentation.

For the data itself, the class uses `ConcurrentDictionary` rather than manual locking:

```csharp
private ConcurrentDictionary<PersonaGUID, Credential> Credentials { get; }

public bool TryGet(PersonaGUID guid, out Credential? credential) =>
    Data.Credentials.TryGetValue(guid, out credential);
```

Use `ConcurrentDictionary` when individual operations are independent. Use explicit locking when you need atomic multi-step operations.

## Testing for Thread Safety

Thread safety that isn't tested is thread safety that doesn't exist. Here are two patterns that catch real bugs:

### Concurrent Access Stress Tests

```csharp
[TestMethod]
public void CredentialCacheIsThreadSafeUnderConcurrentAccess()
{
    var cache = CredentialCache.Instance;
    int numberOfThreads = 10;
    int operationsPerThread = 100;
    List<Task> tasks = [];

    for (int i = 0; i < numberOfThreads; i++)
    {
        tasks.Add(Task.Run(() =>
        {
            for (int j = 0; j < operationsPerThread; j++)
            {
                var guid = CredentialCache.CreatePersonaGUID();
                var credential = factory.Create();
                cache.AddOrReplace(guid, credential);
                bool result = cache.TryGet(guid, out var retrieved);
                Assert.IsTrue(result);
                Assert.AreEqual(credential, retrieved);
            }
        }));
    }

    Task.WaitAll([.. tasks]);
}
```

### No-Overlap Verification

```csharp
[TestMethod]
public async Task NoOverlappingExecutions()
{
    int executions = 0;
    var options = new IntervalActionOptions
    {
        PollingInterval = TimeSpan.FromMilliseconds(50),
        ActionInterval = TimeSpan.FromMilliseconds(100),
        Action = () =>
        {
            Interlocked.Increment(ref executions);
            Thread.Sleep(500);  // Simulate slow work
        }
    };

    var action = IntervalAction.Start(options);
    await Task.Delay(1200);
    action.Stop();

    // If overlapping occurred, executions would be much higher
    Assert.IsTrue(executions <= 3);
}
```

`Interlocked.Increment` is essential here — a bare `executions++` in a multi-threaded context is itself a race condition.

### Parallel Clone Independence

```csharp
[TestMethod]
public void ConcurrentDeepClone_ProducesIndependentCopies()
{
    var original = new ComplexObject { Id = 1, Name = "Parent" };
    ConcurrentBag<ComplexObject> results = [];

    Parallel.For(0, 100, _ =>
    {
        var clone = original.DeepClone();
        results.Add(clone);
    });

    Assert.AreEqual(100, results.Count);
    foreach (var clone in results)
    {
        clone.Id = 999;  // Mutate clone
    }
    Assert.AreEqual(1, original.Id);  // Original unchanged
}
```

`ConcurrentBag<T>` is the right collection here — it's optimized for scenarios where the same thread that adds items also consumes them, and it handles concurrent adds without locking.

## Summary of Patterns

| Pattern | When to Use | Key Type |
|---------|------------|----------|
| Lock as parameter | Caller needs to coordinate multiple operations | `object` + `lock` |
| Thread dispatch queue | Operations must run on a specific thread | `ConcurrentQueue<Task>` |
| Overlap prevention | Periodic actions that shouldn't stack | `Task` null-check + `Lock` |
| ReaderWriterLockSlim | Many readers, few writers | `ReaderWriterLockSlim` |
| Lock (.NET 9+) | General-purpose mutual exclusion | `Lock` |
| Thread-safe singleton | Lazy init with pre-configuration | `lock` + null check |
| Interlocked | Simple counters and flags | `Interlocked.Increment` |

The common thread (no pun intended) across all of these is **making threading visible**. Lock parameters in method signatures, thread ID checks that throw, naming conventions that call out synchronization — these all fight the natural tendency for threading concerns to become invisible and therefore broken.

## References

- [ktsu.dev Invoker library](https://github.com/ktsu-dev/Invoker)
- [ktsu.dev IntervalAction library](https://github.com/ktsu-dev/IntervalAction)
- [ktsu.dev CredentialCache library](https://github.com/ktsu-dev/CredentialCache)
- [System.Threading.Lock (.NET 9)](https://learn.microsoft.com/en-us/dotnet/api/system.threading.lock)
- [ReaderWriterLockSlim](https://learn.microsoft.com/en-us/dotnet/api/system.threading.readerwriterlockslim)
- [ConcurrentDictionary<TKey,TValue>](https://learn.microsoft.com/en-us/dotnet/api/system.collections.concurrent.concurrentdictionary-2)
