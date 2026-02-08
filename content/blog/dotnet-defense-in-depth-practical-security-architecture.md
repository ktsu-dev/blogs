---
title: "Defense in Depth: Practical Security Architecture for .NET Systems"
author: "Matt Edmondson"
created: 2026-02-08
modified: 2026-02-08
status: draft
description: "A layered security architecture for .NET data processing systems — input validation, JWT auth, role-based access, rate limiting, encryption, and security headers with working code."
categories: ["Development", "C#", "Architecture"]
tags: ["csharp", "dotnet", "security", "architecture", "design-patterns"]
keywords: ["defense in depth .NET", "security architecture", "JWT authentication C#", "rate limiting", "security headers middleware", "data encryption .NET", "RBAC authorization"]
slug: "dotnet-defense-in-depth-practical-security-architecture"
---

# Defense in Depth: Practical Security Architecture for .NET Systems

Security in production systems isn't a single check at the front door. It's a series of layers, each designed to catch what the previous one missed. If your authentication is compromised, authorization should still block unauthorized access. If authorization fails, rate limiting should constrain the damage. If rate limiting is bypassed, encryption should protect the data at rest.

This post walks through a six-layer security architecture for .NET data processing systems, with working code for each layer.

## The Six Layers

```
Request → [1. Input Validation]
        → [2. Authentication]
        → [3. Authorization]
        → [4. Rate Limiting]
        → [5. Security Headers]
        → [6. Response Security]
        → Response
```

Each layer operates independently. Removing one shouldn't collapse the entire security model — it should just reduce the depth of defense.

## Layer 1: Input Validation

Every external input is hostile until proven otherwise. Validate at the boundary, not deep in business logic:

```csharp
public class InputValidator
{
    public ValidationResult Validate(DataInput input)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(input.UserId))
            errors.Add("UserId is required");

        if (input.Query?.Length > 10_000)
            errors.Add("Query exceeds maximum length");

        // Reject known-dangerous patterns
        if (ContainsSqlInjectionPatterns(input.Query))
            errors.Add("Query contains invalid characters");

        return errors.Count == 0
            ? ValidationResult.Success()
            : ValidationResult.Failure(errors);
    }

    private static bool ContainsSqlInjectionPatterns(string? input)
    {
        if (input is null) return false;
        var patterns = new[] { "';", "--", "/*", "*/", "xp_", "exec " };
        return patterns.Any(p =>
            input.Contains(p, StringComparison.OrdinalIgnoreCase));
    }
}
```

Even with parameterized queries (which you should always use), validating inputs prevents malformed data from reaching deeper layers where it might cause unexpected behavior.

## Layer 2: Authentication

JWT tokens for service-to-service communication, with strict validation:

```csharp
public class JwtAuthenticationService
{
    private readonly SecurityConfig _config;

    public async Task<AuthenticationResult> AuthenticateAsync(string token)
    {
        var handler = new JwtSecurityTokenHandler();
        var parameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = _config.JwtIssuer,
            ValidAudience = _config.JwtAudience,
            IssuerSigningKey = new SymmetricSecurityKey(
                Convert.FromBase64String(_config.JwtSecret)),
            ClockSkew = TimeSpan.FromMinutes(5)
        };

        try
        {
            var principal = handler.ValidateToken(
                token, parameters, out var validatedToken);
            return AuthenticationResult.Success(principal);
        }
        catch (SecurityTokenException ex)
        {
            return AuthenticationResult.Failure(ex.Message);
        }
    }
}
```

Key decisions:
- **`ClockSkew` of 5 minutes** accommodates server time drift without being so generous that expired tokens are accepted
- **All five validation flags are `true`** — skipping any one of them (common in tutorials) creates a real vulnerability
- **Catch `SecurityTokenException`** specifically, not a bare `Exception` — you want to distinguish auth failures from system errors

## Layer 3: Authorization

Authentication tells you *who* the caller is. Authorization tells you *what they can do*:

```csharp
public static class SecurityPolicies
{
    public static void ConfigurePolicies(this IServiceCollection services)
    {
        services.AddAuthorization(options =>
        {
            options.AddPolicy("AdminOnly", policy =>
                policy.RequireRole("Administrator"));

            options.AddPolicy("DataProcessorAccess", policy =>
                policy.RequireRole("Administrator", "DataProcessor", "Operator"));

            options.AddPolicy("ReadOnlyAccess", policy =>
                policy.RequireRole("Administrator", "DataProcessor",
                    "Operator", "Viewer"));
        });
    }
}
```

Policies are cumulative — `AdminOnly` is the most restrictive, `ReadOnlyAccess` the least. Apply them to endpoints:

```csharp
[Authorize(Policy = "DataProcessorAccess")]
[HttpPost("process")]
public async Task<IActionResult> ProcessData([FromBody] DataInput input)
{
    // Only Administrator, DataProcessor, and Operator roles reach here
}
```

## Layer 4: Rate Limiting

Rate limiting prevents brute force attacks and constrains the blast radius of compromised credentials:

```csharp
public class RateLimitingMiddleware
{
    private readonly IDistributedCache _cache;
    private readonly int _maxRequestsPerMinute;

    public async Task InvokeAsync(HttpContext context)
    {
        string ip = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        string key = $"rate_limit:{ip}";

        var requests = await _cache.GetAsync<List<DateTime>>(key)
            ?? new List<DateTime>();

        var now = DateTime.UtcNow;
        requests.RemoveAll(r => r < now.AddMinutes(-1));
        requests.Add(now);

        await _cache.SetAsync(key, requests, new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(2)
        });

        if (requests.Count > _maxRequestsPerMinute)
        {
            context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
            context.Response.Headers.Append("Retry-After", "60");
            return;
        }

        await _next(context);
    }
}
```

The sliding window (remove requests older than 1 minute, count remaining) is simple and effective. For production systems with high throughput, consider the built-in `System.Threading.RateLimiting` APIs in .NET 7+ which offer fixed window, sliding window, token bucket, and concurrency limiters.

## Layer 5: Security Headers

HTTP headers that instruct browsers (and proxies) to enforce security policies:

```csharp
public class SecurityHeadersMiddleware
{
    public async Task InvokeAsync(HttpContext context)
    {
        var headers = context.Response.Headers;

        // Prevent XSS
        headers.Append("Content-Security-Policy",
            "default-src 'self'; script-src 'self'");

        // Prevent clickjacking
        headers.Append("X-Frame-Options", "DENY");

        // Enable browser XSS filter
        headers.Append("X-XSS-Protection", "1; mode=block");

        // Prevent MIME-type sniffing
        headers.Append("X-Content-Type-Options", "nosniff");

        // Enforce HTTPS
        headers.Append("Strict-Transport-Security",
            "max-age=31536000; includeSubDomains");

        // Control referrer information
        headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");

        await _next(context);
    }
}
```

These headers cost nothing to add and prevent entire categories of client-side attacks. Register the middleware early in the pipeline so it covers all responses, including error pages.

## Layer 6: Data Encryption

Sensitive data (PII, credentials, API keys) should be encrypted at rest:

```csharp
public class DataEncryptionService
{
    private readonly byte[] _key;

    public async Task<EncryptedData> EncryptAsync(string plaintext)
    {
        using var aes = Aes.Create();
        aes.Key = _key;
        aes.GenerateIV();  // Fresh IV per encryption

        using var encryptor = aes.CreateEncryptor();
        using var ms = new MemoryStream();
        using var cs = new CryptoStream(ms, encryptor, CryptoStreamMode.Write);
        using var sw = new StreamWriter(cs);

        await sw.WriteAsync(plaintext);
        await sw.FlushAsync();
        await cs.FlushFinalBlockAsync();

        return new EncryptedData
        {
            Data = Convert.ToBase64String(ms.ToArray()),
            IV = Convert.ToBase64String(aes.IV),
            Timestamp = DateTimeOffset.UtcNow
        };
    }
}
```

Critical: **generate a new IV for every encryption operation**. Reusing IVs with the same key is a textbook cryptographic weakness.

## Parameterized Queries: Always

This isn't a layer — it's a baseline requirement. Never build SQL from string concatenation:

```csharp
// Always parameterized
public async Task<IEnumerable<DataRecord>> GetRecordsByUserAsync(
    string userId, DateTime fromDate)
{
    const string sql = """
        SELECT Id, Content, CreatedAt, UserId
        FROM DataRecords
        WHERE UserId = @UserId
        AND CreatedAt >= @FromDate
        ORDER BY CreatedAt DESC
        """;

    return await _connection.QueryAsync<DataRecord>(sql,
        new { UserId = userId, FromDate = fromDate });
}
```

With Dapper or Entity Framework, parameterized queries are the default. The danger is in hand-written SQL or stored procedure calls where someone concatenates user input.

## Testing Security

Security that isn't tested is wishful thinking:

```csharp
[TestMethod]
public async Task SqlInjection_IsRejectedByValidation()
{
    var input = new DataInput { Query = "'; DROP TABLE Users;--" };
    var result = _validator.Validate(input);
    Assert.IsFalse(result.IsValid);
}

[TestMethod]
public async Task ExpiredToken_IsRejected()
{
    var expiredToken = GenerateToken(expiration: DateTime.UtcNow.AddHours(-1));
    var result = await _authService.AuthenticateAsync(expiredToken);
    Assert.IsFalse(result.IsAuthenticated);
}

[TestMethod]
public async Task RateLimit_Returns429_WhenExceeded()
{
    for (int i = 0; i < _maxRequests + 1; i++)
    {
        var response = await _client.GetAsync("/api/data");
        if (i >= _maxRequests)
            Assert.AreEqual(HttpStatusCode.TooManyRequests, response.StatusCode);
    }
}
```

## Summary

| Layer | Protects Against | Cost |
|-------|-----------------|------|
| Input validation | Injection, malformed data | Low — just validation code |
| Authentication | Unauthorized access | Medium — JWT infrastructure |
| Authorization | Privilege escalation | Low — policy configuration |
| Rate limiting | Brute force, DoS | Low — middleware + cache |
| Security headers | XSS, clickjacking, MIME sniffing | Near zero — HTTP headers |
| Data encryption | Data breach exposure | Medium — key management |

The layers are independent and additive. Start with input validation and parameterized queries (they're free). Add authentication and authorization next (they define your access model). Then layer on rate limiting, headers, and encryption as your threat model demands.

## References

- [OWASP Top Ten](https://owasp.org/www-project-top-ten/)
- [ASP.NET Core Security](https://learn.microsoft.com/en-us/aspnet/core/security/)
- [JWT Authentication](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/)
- [Rate Limiting in .NET 7+](https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit)
- [Data Protection APIs](https://learn.microsoft.com/en-us/aspnet/core/security/data-protection/)
