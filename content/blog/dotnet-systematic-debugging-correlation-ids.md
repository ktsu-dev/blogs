---
title: "Systematic Debugging with Correlation IDs in .NET"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "A scientific approach to debugging .NET systems — correlation IDs for request tracing, structured logging, Activity-based distributed tracing, and practical patterns for finding bugs faster."
categories: ["Development", "C#", "Debugging"]
tags: ["csharp", "dotnet", "debugging", "distributed-systems", "observability"]
keywords: ["correlation ID .NET", "distributed tracing", "structured logging C#", "System.Diagnostics.Activity", "debugging methodology", "OpenTelemetry .NET"]
slug: "dotnet-systematic-debugging-correlation-ids"
---

# Systematic Debugging with Correlation IDs in .NET

The hardest bugs aren't the ones that crash your application — they're the ones that produce wrong results silently, or fail intermittently, or only happen when three services interact under load. These bugs resist ad-hoc debugging. They require a system.

This post covers a structured approach to debugging .NET applications: a methodology for narrowing down root causes, correlation IDs for tracing requests across services, structured logging that's actually searchable, and Activity-based distributed tracing.

## The Scientific Method for Debugging

Before reaching for tools, apply a process:

1. **Observe**: What is the actual behavior? What was expected? When did it start?
2. **Hypothesize**: What could cause this difference? List at least three possibilities.
3. **Test**: Design the smallest experiment that eliminates one hypothesis.
4. **Analyze**: Did the test confirm or reject the hypothesis?
5. **Repeat**: Narrow down until you find the root cause.

The most common debugging mistake is skipping step 2 — jumping straight from "it's broken" to changing code. Listing multiple hypotheses forces you to consider causes you might otherwise miss.

### Reproduce First

A bug you can't reproduce is a bug you can't fix with confidence. Before investigating:

- **Document exact steps** to trigger the failure
- **Isolate variables** — does it happen on all environments? All inputs? All times of day?
- **Use `git bisect`** for regressions — find the exact commit that introduced the behavior

```bash
git bisect start
git bisect bad                    # Current commit is broken
git bisect good v1.2.0            # This release was working
# Git checks out a midpoint — test and mark good/bad
# Repeat until the offending commit is found
```

## Correlation IDs: Tracing Requests Across Services

In a distributed system, a single user action might touch five services. Without a shared identifier, correlating logs across those services is archaeology.

A correlation ID is a unique string (typically a GUID) that follows a request through every service it touches:

```csharp
public class CorrelationMiddleware
{
    private readonly RequestDelegate _next;

    public CorrelationMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        // Use the caller's correlation ID, or generate a new one
        var correlationId = context.Request.Headers["X-Correlation-ID"]
            .FirstOrDefault() ?? Guid.NewGuid().ToString();

        // Make it available to the entire request pipeline
        context.Items["CorrelationId"] = correlationId;

        // Include it in all log entries for this request
        using (LogContext.PushProperty("CorrelationId", correlationId))
        {
            // Echo it back so the caller can reference it
            context.Response.Headers.Append("X-Correlation-ID", correlationId);
            await _next(context);
        }
    }
}
```

When service A calls service B, it passes the correlation ID in the header. Service B's middleware picks it up and adds it to its own logs. Now a single query retrieves the entire request path:

```kusto
// Application Insights (KQL)
traces
| where timestamp > ago(30m)
| where customDimensions.CorrelationId == "abc-123-def-456"
| order by timestamp asc
```

## Structured Logging: Named Properties, Not String Interpolation

The difference between searchable logs and useless logs is structure:

```csharp
// Bad — unstructured, unsearchable
_logger.LogInformation($"User {userId} processed {count} records in {elapsed}ms");

// Good — structured, every field is independently queryable
_logger.LogInformation(
    "User {UserId} processed {RecordCount} records in {ElapsedMs}ms",
    userId, count, elapsed);
```

The structured version lets you query for all requests by a specific user, or all requests that processed more than 1000 records, or all requests slower than 500ms — without regex.

### Log Context, Not Just Events

When an exception occurs, the stack trace tells you *where*. The context tells you *why*:

```csharp
try
{
    await ProcessDataAsync(data);
}
catch (Exception ex)
{
    _logger.LogError(ex,
        "Failed to process data. Context: {@Context}",
        new
        {
            DataId = data?.Id,
            DataType = data?.GetType().Name,
            RecordCount = data?.Records?.Count,
            Timestamp = DateTime.UtcNow
        });
    throw;
}
```

The `@` prefix tells Serilog (and compatible loggers) to serialize the entire object, not just call `.ToString()`.

## Activity-Based Distributed Tracing

.NET's `System.Diagnostics.Activity` API provides built-in distributed tracing that integrates with OpenTelemetry:

```csharp
private static readonly ActivitySource _activitySource = new("DataPipeline");

public async Task<ProcessingResult> ProcessAsync(DataInput input)
{
    using var activity = _activitySource.StartActivity("ProcessData");
    activity?.SetTag("input.type", input.GetType().Name);
    activity?.SetTag("input.size", input.Data?.Length.ToString());

    var stages = new (string Name, Func<Task> Action)[]
    {
        ("Validate", () => ValidateInput(input)),
        ("Transform", () => TransformData(input)),
        ("Persist", () => PersistData(input))
    };

    foreach (var (name, action) in stages)
    {
        using var stageActivity = _activitySource.StartActivity($"Stage.{name}");
        try
        {
            _logger.LogDebug("Starting stage: {Stage}", name);
            await action();
            _logger.LogDebug("Completed stage: {Stage}", name);
        }
        catch (Exception ex)
        {
            stageActivity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            _logger.LogError(ex, "Failed at stage: {Stage}", name);
            throw;
        }
    }

    return new ProcessingResult { Success = true };
}
```

Activities automatically propagate through `async/await`, HTTP calls (via `HttpClient`), and message queues. Each activity records its parent, creating a tree of spans that visualizers like Jaeger or Azure Monitor can render as a timeline.

## Timing Without Noise

For performance debugging, wrap suspect operations with `Stopwatch`:

```csharp
public class DiagnosticMiddleware
{
    public async Task InvokeAsync(HttpContext context)
    {
        using var scope = _logger.BeginScope(
            "Request {RequestId}", context.TraceIdentifier);

        var stopwatch = Stopwatch.StartNew();
        try
        {
            await _next(context);
        }
        finally
        {
            stopwatch.Stop();
            _logger.LogInformation(
                "Request {Method} {Path} completed in {Duration}ms with {StatusCode}",
                context.Request.Method,
                context.Request.Path,
                stopwatch.ElapsedMilliseconds,
                context.Response.StatusCode);
        }
    }
}
```

The `finally` block ensures timing is logged even when requests fail — which is often when you need the timing most.

## Concurrent Operation Debugging

Concurrency bugs need extra instrumentation. Use `SemaphoreSlim` for controlled parallelism with per-item tracing:

```csharp
public async Task ProcessConcurrentlyAsync(IEnumerable<DataItem> items)
{
    var semaphore = new SemaphoreSlim(Environment.ProcessorCount);
    var tasks = items.Select(async item =>
    {
        await semaphore.WaitAsync();
        try
        {
            using var activity = _activitySource.StartActivity("ProcessItem");
            activity?.SetTag("item.id", item.Id);

            var sw = Stopwatch.StartNew();
            await ProcessItemAsync(item);

            _logger.LogDebug(
                "Processed item {ItemId} in {Duration}ms",
                item.Id, sw.ElapsedMilliseconds);
        }
        finally
        {
            semaphore.Release();
        }
    });

    await Task.WhenAll(tasks);
}
```

The `SemaphoreSlim` bounds parallelism to CPU count, preventing thread pool starvation. The per-item Activity creates individual spans you can correlate with downstream service calls.

## Querying Your Logs

Structured logging is only useful if you can query it. Common patterns:

### Find all errors in the last hour

```json
{
    "query": {
        "bool": {
            "must": [
                { "term": { "level": "ERROR" } },
                { "range": { "@timestamp": { "gte": "now-1h" } } }
            ]
        }
    }
}
```

### Trace a single request across services

```kusto
traces
| where customDimensions.CorrelationId == "abc-123"
| project timestamp, message, customDimensions.ServiceName
| order by timestamp asc
```

### Find slow operations

```kusto
traces
| where customDimensions.ElapsedMs > 500
| summarize count() by bin(timestamp, 5m), customDimensions.Stage
| render timechart
```

## The Debugging Toolkit

| Tool | Use Case |
|------|----------|
| Correlation IDs | Tracing requests across services |
| Structured logging | Searchable, queryable log entries |
| `System.Diagnostics.Activity` | Distributed tracing with OpenTelemetry |
| `Stopwatch` | Performance measurement |
| `git bisect` | Finding regression commits |
| Application Insights / Jaeger | Visualizing distributed traces |
| PerfView / dotTrace | CPU and memory profiling |

Start with correlation IDs and structured logging — they cost almost nothing to add and make every future debugging session faster.

## References

- [System.Diagnostics.Activity](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.activity)
- [OpenTelemetry .NET](https://opentelemetry.io/docs/languages/dotnet/)
- [Serilog Structured Logging](https://serilog.net/)
- [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [git bisect](https://git-scm.com/docs/git-bisect)
