---
title: "Object Pooling and Memory Management in High-Performance .NET"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "Practical techniques for reducing GC pressure in .NET — object pooling, Span<T>, ArrayPool, LOH management, and continuous memory monitoring with real benchmarks."
categories: ["Development", "C#", "Architecture"]
tags: ["csharp", "dotnet", "performance", "memory-management", "design-patterns"]
keywords: ["object pooling C#", ".NET memory management", "Span T", "ArrayPool", "GC pressure", "Large Object Heap", "BenchmarkDotNet", "high-performance .NET"]
slug: "dotnet-object-pooling-memory-management-high-performance"
---

# Object Pooling and Memory Management in High-Performance .NET

The .NET garbage collector is excellent — until it isn't. In data-intensive applications, naive allocations create GC pauses that destroy throughput predictability. The fix isn't to avoid allocations entirely (that way lies unreadable code), but to eliminate the *unnecessary* ones.

This post covers the memory management patterns I use in production .NET systems that process thousands of records per second: object pooling, `Span<T>`, `ArrayPool<T>`, Large Object Heap awareness, and continuous memory monitoring.

## Start With Targets, Not Optimization

Before touching any allocation code, define what "fast enough" means:

```csharp
public static class PerformanceTargets
{
    public const int MinRecordsPerSecond = 5000;
    public const int MaxProcessingLatencyMs = 100;
    public const long MaxMemoryUsageBytes = 2L * 1024 * 1024 * 1024; // 2 GB
    public const double MaxGCTimePercent = 5.0;
}
```

These targets make performance regressions testable:

```csharp
[TestMethod]
[TestCategory("Performance")]
public async Task ProcessBatch_MeetsMinimumThroughput()
{
    var stopwatch = Stopwatch.StartNew();
    var result = await _processor.ProcessBatchAsync(_testRecords);
    stopwatch.Stop();

    double recordsPerSecond = _testRecords.Count / stopwatch.Elapsed.TotalSeconds;
    Assert.IsTrue(recordsPerSecond > PerformanceTargets.MinRecordsPerSecond,
        $"Throughput {recordsPerSecond:F0} r/s below target {PerformanceTargets.MinRecordsPerSecond}");
}
```

Without targets, "optimization" becomes bikeshedding. With them, you know exactly when to stop.

## Object Pooling: Stop Creating What You Already Have

The most impactful optimization in allocation-heavy code is pooling objects that are created and discarded in tight loops.

### StringBuilder Pooling

`StringBuilder` is the classic example — every string concatenation in a loop creates a new one:

```csharp
// Before: new StringBuilder per iteration
foreach (var record in records)
{
    var sb = new StringBuilder();  // GC pressure
    sb.Append(record.Name);
    sb.Append(',');
    sb.Append(record.Value);
    output.Add(sb.ToString());
}

// After: pooled StringBuilder, reused across iterations
private static readonly ObjectPool<StringBuilder> _sbPool =
    new DefaultObjectPoolProvider().CreateStringBuilderPool();

foreach (var record in records)
{
    var sb = _sbPool.Get();
    try
    {
        sb.Append(record.Name);
        sb.Append(',');
        sb.Append(record.Value);
        output.Add(sb.ToString());
    }
    finally
    {
        _sbPool.Return(sb);  // Cleared and returned to pool
    }
}
```

`Microsoft.Extensions.ObjectPool` provides `CreateStringBuilderPool()` which automatically clears the builder on return. For custom objects, implement `IPooledObjectPolicy<T>`.

### ArrayPool for Byte Buffers

Any code that allocates temporary byte arrays (file I/O, serialization, network) benefits from `ArrayPool<T>`:

```csharp
// Before: allocates on every call
public byte[] ReadChunk(Stream stream, int size)
{
    var buffer = new byte[size];  // Allocated, used once, GC'd
    stream.Read(buffer, 0, size);
    return buffer;
}

// After: rented from shared pool
public void ProcessChunk(Stream stream, int size)
{
    byte[] buffer = ArrayPool<byte>.Shared.Rent(size);
    try
    {
        int bytesRead = stream.Read(buffer, 0, size);
        ProcessData(buffer.AsSpan(0, bytesRead));
    }
    finally
    {
        ArrayPool<byte>.Shared.Return(buffer, clearArray: true);
    }
}
```

`Rent` may return a buffer *larger* than requested — always track the actual data length separately. The `clearArray: true` parameter zeros the buffer on return, which matters for security-sensitive data.

### The 80KB File I/O Buffer

For file operations, 80KB is the sweet spot — large enough for efficient I/O, small enough to stay below the Large Object Heap threshold (85,000 bytes):

```csharp
private const int FileBufferSize = 81_920; // 80 KB — just under LOH threshold

public async Task ProcessFileAsync(string path)
{
    byte[] buffer = ArrayPool<byte>.Shared.Rent(FileBufferSize);
    try
    {
        await using var stream = new FileStream(path, FileMode.Open,
            FileAccess.Read, FileShare.Read, FileBufferSize,
            FileOptions.SequentialScan | FileOptions.Asynchronous);

        int bytesRead;
        while ((bytesRead = await stream.ReadAsync(buffer)) > 0)
        {
            ProcessChunk(buffer.AsSpan(0, bytesRead));
        }
    }
    finally
    {
        ArrayPool<byte>.Shared.Return(buffer);
    }
}
```

## Span\<T\>: Zero-Copy Slicing

`Span<T>` lets you work with slices of arrays and strings without creating new allocations. The classic example is CSV parsing:

```csharp
// Before: String.Split allocates a new string per field
string[] fields = line.Split(',');  // N allocations

// After: Span-based parsing — zero allocations
public static void ParseCsvLine(ReadOnlySpan<char> line, Span<Range> fields)
{
    int fieldIndex = 0;
    int start = 0;

    for (int i = 0; i < line.Length; i++)
    {
        if (line[i] == ',')
        {
            fields[fieldIndex++] = start..i;
            start = i + 1;
        }
    }
    fields[fieldIndex] = start..line.Length;
}
```

Each `Range` is just two integers — no heap allocation, no GC pressure. The caller accesses fields via `line[fields[0]]`, which returns a `ReadOnlySpan<char>` slice of the original data.

For async code where `Span<T>` can't cross `await` boundaries, use `ReadOnlyMemory<T>` instead:

```csharp
public async Task ProcessAsync(ReadOnlyMemory<byte> data)
{
    // Memory<T> is heap-safe, Span<T> is stack-only
    await ProcessHeaderAsync(data.Slice(0, HeaderSize));
    await ProcessBodyAsync(data.Slice(HeaderSize));
}
```

## The Large Object Heap Problem

Objects larger than 85,000 bytes go on the Large Object Heap, which is only collected during Gen 2 GC — the most expensive kind. LOH fragmentation causes memory bloat even when total live objects are small.

Rules of thumb:
- **Keep arrays under 85KB** — that's ~10,600 `double`s or ~21,250 `int`s
- **Use `ArrayPool<T>.Shared`** for temporary large arrays — the pool handles LOH objects efficiently
- **Monitor Gen 2 collections** — if they're frequent, you have a LOH problem

```csharp
// Monitor GC generation counts
int gen0Before = GC.CollectionCount(0);
int gen1Before = GC.CollectionCount(1);
int gen2Before = GC.CollectionCount(2);

// ... run workload ...

int gen0After = GC.CollectionCount(0);
int gen2After = GC.CollectionCount(2);

// Gen2 collections during a batch suggest LOH pressure
if (gen2After > gen2Before)
{
    _logger.LogWarning("Gen2 GC during batch processing — check for LOH allocations");
}
```

## Continuous Memory Monitoring

In long-running services, memory leaks are slow-motion disasters. A simple timer-based monitor catches them early:

```csharp
public class MemoryMonitor : IDisposable
{
    private readonly Timer _timer;
    private long _lastMemoryUsage;

    public MemoryMonitor(TimeSpan interval)
    {
        _lastMemoryUsage = GC.GetTotalMemory(false);
        _timer = new Timer(CheckMemory, null, interval, interval);
    }

    private void CheckMemory(object? state)
    {
        long current = GC.GetTotalMemory(false);

        if (current > _lastMemoryUsage * 1.5)
        {
            // 50% growth since last check — something is wrong
            _logger.LogWarning(
                "Memory spike: {Previous}MB -> {Current}MB",
                _lastMemoryUsage / (1024 * 1024),
                current / (1024 * 1024));
        }

        _lastMemoryUsage = current;
    }

    public void Dispose() => _timer.Dispose();
}
```

The 50% threshold is tunable — tighter for services with stable workloads, looser for batch processors with variable load. The key is having *any* monitoring, so you don't discover the leak from an OOM crash in production.

## Batch Processing for Predictable Memory

Processing records one-at-a-time has poor locality. Processing all-at-once risks memory exhaustion. Batching is the middle ground:

```csharp
public async IAsyncEnumerable<ProcessResult> ProcessInBatchesAsync(
    IAsyncEnumerable<Record> records,
    int batchSize = 1000)
{
    var batch = new List<Record>(batchSize);

    await foreach (var record in records)
    {
        batch.Add(record);

        if (batch.Count >= batchSize)
        {
            yield return await ProcessBatchAsync(batch);
            batch.Clear();  // Reuse the list — no reallocation
        }
    }

    if (batch.Count > 0)
    {
        yield return await ProcessBatchAsync(batch);
    }
}
```

The pre-allocated `List<Record>(batchSize)` avoids repeated resizing. `batch.Clear()` reuses the internal array. And `IAsyncEnumerable` lets the caller consume results as they're produced rather than waiting for the entire dataset.

## Channel-Based Producer-Consumer

For concurrent processing with backpressure, `System.Threading.Channels` is the modern replacement for `BlockingCollection<T>`:

```csharp
public async Task ProcessWithBackpressureAsync(
    IAsyncEnumerable<Record> source,
    int maxBuffer = 100)
{
    var channel = Channel.CreateBounded<Record>(new BoundedChannelOptions(maxBuffer)
    {
        FullMode = BoundedChannelFullMode.Wait,
        SingleReader = true,
        SingleWriter = true
    });

    // Producer
    var producer = Task.Run(async () =>
    {
        await foreach (var record in source)
        {
            await channel.Writer.WriteAsync(record);
        }
        channel.Writer.Complete();
    });

    // Consumer
    await foreach (var record in channel.Reader.ReadAllAsync())
    {
        await ProcessRecordAsync(record);
    }

    await producer;
}
```

The bounded channel with `FullMode.Wait` automatically applies backpressure — if the consumer can't keep up, the producer pauses. No manual synchronization needed.

## Putting It All Together

Here's a data processing method that combines several of these patterns:

```csharp
public async Task<ProcessResult> ProcessLargeDatasetAsync(
    IAsyncEnumerable<Record> records)
{
    var sb = _sbPool.Get();
    byte[] buffer = ArrayPool<byte>.Shared.Rent(FileBufferSize);
    long totalProcessed = 0;

    try
    {
        await foreach (var record in records)
        {
            sb.Clear();
            FormatRecord(record, sb);  // Reuse StringBuilder

            ReadOnlySpan<char> formatted = sb.ToString();
            // ... process ...

            totalProcessed++;

            if (totalProcessed % 50_000 == 0)
            {
                long memory = GC.GetTotalMemory(false);
                _logger.LogInformation(
                    "Processed {Count} records, memory: {MB}MB",
                    totalProcessed, memory / (1024 * 1024));
            }
        }

        return new ProcessResult(totalProcessed);
    }
    finally
    {
        _sbPool.Return(sb);
        ArrayPool<byte>.Shared.Return(buffer);
    }
}
```

Pooled `StringBuilder`, rented byte buffer, periodic memory logging, and `try/finally` to guarantee returns. Nothing exotic — just disciplined resource management.

## Summary

| Technique | When to Use | Impact |
|-----------|------------|--------|
| Object pooling | Tight loops creating/discarding objects | Eliminates GC pressure |
| `ArrayPool<T>` | Temporary byte/array buffers | Avoids LOH allocations |
| `Span<T>` | Parsing, slicing, zero-copy operations | Zero allocation |
| `Memory<T>` | Same as Span but across `await` | Zero allocation (async) |
| 80KB buffer limit | File I/O buffer sizing | Avoids LOH |
| Memory monitoring | Long-running services | Catches leaks early |
| Batch processing | High-volume data | Predictable memory |
| Channels | Producer-consumer | Built-in backpressure |

Start with profiling. If Gen 0 collections are high, you have an allocation problem. If Gen 2 collections are high, you have a LOH problem. If memory grows unbounded, you have a leak. The patterns above address all three.

## References

- [ArrayPool\<T\> documentation](https://learn.microsoft.com/en-us/dotnet/api/system.buffers.arraypool-1)
- [Span\<T\> usage guidelines](https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/memory-t-usage-guidelines)
- [ObjectPool in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/performance/objectpool)
- [System.Threading.Channels](https://learn.microsoft.com/en-us/dotnet/core/extensions/channels)
- [BenchmarkDotNet](https://benchmarkdotnet.org/)
- [Large Object Heap](https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/large-object-heap)
