#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Rebuilds the blog index in README.md by scanning markdown files and parsing their frontmatter.

.DESCRIPTION
    This script scans the repository for markdown files (excluding README.md), parses their YAML frontmatter,
    and regenerates the README.md file with an organized index of all blog posts.

.PARAMETER Path
    The root path of the blog repository. Defaults to the parent directory of the script.

.EXAMPLE
    .\Rebuild-BlogIndex.ps1
    
.EXAMPLE
    .\Rebuild-BlogIndex.ps1 -Path "C:\path\to\blog"

.NOTES
    Author: Generated for Matt Edmondson's Blog
    This script requires PowerShell 5.1 or later.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = (Get-Location).Path
)

# Function to parse YAML frontmatter from markdown files
function Get-BlogPostMetadata {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    try {
        $content = Get-Content -Path $FilePath -Raw
        
        # Check if file starts with YAML frontmatter
        if (-not $content.StartsWith('---')) {
            Write-Warning "File $FilePath does not contain YAML frontmatter"
            return $null
        }
        
        # Extract frontmatter between --- delimiters
        $frontmatterEnd = $content.IndexOf('---', 3)
        if ($frontmatterEnd -eq -1) {
            Write-Warning "File $FilePath has malformed YAML frontmatter"
            return $null
        }
        
        $yamlContent = $content.Substring(3, $frontmatterEnd - 3).Trim()
        
        # Parse YAML manually (simple key-value parser)
        $metadata = @{}
        $yamlContent -split "`n" | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                if ($line -match '^([^:]+):\s*(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    # Remove quotes if present
                    if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                        $value = $matches[1]
                    }
                    
                    # Handle arrays (simple bracket notation)
                    if ($value -match '^\[(.*)\]$') {
                        $arrayContent = $matches[1]
                        $value = $arrayContent -split ',' | ForEach-Object { $_.Trim() -replace '^["'']', '' -replace '["'']$', '' }
                    }
                    
                    $metadata[$key] = $value
                }
            }
        }
        
        # Add file information
        $fileInfo = Get-Item -Path $FilePath
        $metadata['FileName'] = $fileInfo.Name
        $metadata['FilePath'] = $fileInfo.Name
        $metadata['RelativePath'] = "./content/blog/$($fileInfo.Name)"
        
        return $metadata
    }
    catch {
        Write-Error "Error processing file $FilePath : $($_.Exception.Message)"
        return $null
    }
}

# Everything that reaches README.md is culture-invariant, because the index has to be the same bytes
# whoever runs the script: the workflow on windows-latest, rebuild-blog.bat under Windows PowerShell
# 5.1, or pwsh on a de-DE machine. Left to the current culture, a German run wrote "Juli 18, 2025",
# and the workflow then committed the README back to English.
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-BlogDate {
    param([string]$DateString)

    return [DateTime]::Parse($DateString, $script:Invariant)
}

# A total order on text: invariant and case-insensitive first, which is how the index has always
# been ordered, then ordinal so that values differing only in case still come out the same way on
# every run. Sort-Object can't give this: it sorts with the current culture, and -Culture "" (the
# invariant culture's name) falls back to the current culture too.
function Compare-InvariantText {
    param([string]$Left, [string]$Right)

    $result = [StringComparer]::InvariantCultureIgnoreCase.Compare($Left, $Right)
    if ($result -eq 0) {
        $result = [string]::CompareOrdinal($Left, $Right)
    }
    return $result
}

# Sorts by the text $Key gives for each item, in Compare-InvariantText order. -Unique keeps the first
# of each run of keys that are equal ignoring case, as Sort-Object -Unique did.
function Sort-InvariantText {
    param([object[]]$Items, [scriptblock]$Key = { param($item) $item }, [switch]$Unique)

    $list = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in $Items) {
        $list.Add($item)
    }
    $list.Sort([System.Comparison[object]] {
            param($x, $y)
            Compare-InvariantText -Left ([string](& $Key $x)) -Right ([string](& $Key $y))
        })

    $sorted = @()
    $lastKey = $null
    foreach ($item in $list) {
        $itemKey = [string](& $Key $item)
        if ($Unique -and $null -ne $lastKey -and [StringComparer]::InvariantCultureIgnoreCase.Equals($itemKey, $lastKey)) {
            continue
        }
        $sorted += , $item
        $lastKey = $itemKey
    }
    return , $sorted
}

# Function to format date for display
function Format-BlogDate {
    param([string]$DateString)
    
    if ([string]::IsNullOrEmpty($DateString)) {
        return "Unknown"
    }
    
    try {
        $date = ConvertTo-BlogDate -DateString $DateString
        return $date.ToString("MMMM d, yyyy", $script:Invariant)
    }
    catch {
        return $DateString
    }
}

# Main script
Write-Host "Rebuilding blog index..." -ForegroundColor Cyan

# Find all markdown files in the content/blog directory except README.md
# Join-Path is nested rather than given a "content\blog" child segment: a separator embedded in a
# single argument is not portable, and the three-argument form that would replace it needs
# PowerShell 6+, which rebuild-blog.bat (Windows PowerShell 5.1) does not have.
$blogPosts = Get-ChildItem -Path (Join-Path (Join-Path $Path "content") "blog") -Filter "*.md" -File |
    Where-Object { $_.Name -ne "README.md" }

Write-Host "Found $($blogPosts.Count) blog post(s)" -ForegroundColor Green

# Parse metadata from each post
$posts = @()
foreach ($post in $blogPosts) {
    Write-Host "   Processing: $($post.Name)" -ForegroundColor Gray
    $metadata = Get-BlogPostMetadata -FilePath $post.FullName
    if ($metadata -and $metadata.status -eq "published") {
        $posts += $metadata
    }
    elseif ($metadata) {
        Write-Host "   Skipping: $($post.Name) (status: $($metadata.status))" -ForegroundColor Yellow
    }
}

if ($posts.Count -eq 0) {
    Write-Error "No valid blog posts found with status 'published'"
    exit 1
}

Write-Host "Found $($posts.Count) published blog post(s)" -ForegroundColor Green

# Sort posts by date (newest first), breaking ties on title.
# Sort-Object is not a stable sort, so posts sharing a created date are not guaranteed to keep
# their input order. The tiebreaker is what makes the result reproducible: the workflow commits
# README.md whenever it differs, so an unordered tie becomes a spurious commit on every push.
# Titles aren't compared by Sort-Object, which would use the current culture. They are put in
# invariant order first, and that position is then the tiebreaker for the sort by date.
$byTitle = Sort-InvariantText -Items $posts -Key { param($post) $post.title }
$dated = for ($i = 0; $i -lt $byTitle.Count; $i++) {
    $created = try { ConvertTo-BlogDate -DateString $byTitle[$i].created } catch { [DateTime]::MinValue }
    [pscustomobject]@{ Post = $byTitle[$i]; Created = $created; Index = $i }
}
$sortedPosts = @($dated | Sort-Object -Property @{ Expression = { $_.Created }; Descending = $true }, Index |
    ForEach-Object { $_.Post })

# Generate README content
$readmeContent = @()
$readmeContent += "# ktsu.dev Blog"
$readmeContent += ""
$readmeContent += "Welcome to the ktsu.dev technical blog. This is where I share my experiences, insights, and deep dives into software development, debugging adventures, and architectural discoveries."
$readmeContent += ""

# Latest Posts section
$readmeContent += "## Latest Posts"
$readmeContent += ""

foreach ($post in $sortedPosts) {
    $readmeContent += "### [$($post.title)]($($post.RelativePath))"
    $readmeContent += ""
    $publishedDate = Format-BlogDate -DateString $post.created
    $status = if ($post.status) { $post.status } else { "Unknown" }
    $readmeContent += "**Published:** $publishedDate"
    $readmeContent += ""
    $readmeContent += "**Status:** $status"
    $readmeContent += ""
    
    if ($post.categories) {
        $categories = if ($post.categories -is [array]) { $post.categories -join ', ' } else { $post.categories }
        $readmeContent += "**Categories:** $categories"
        $readmeContent += ""
    }
    
    if ($post.tags) {
        $tags = if ($post.tags -is [array]) { $post.tags -join ', ' } else { $post.tags }
        $readmeContent += "**Tags:** $tags"
        $readmeContent += ""
    }
    
    if ($post.description) {
        $readmeContent += $post.description
        $readmeContent += ""
    }
    $readmeContent += "---"
    $readmeContent += ""
}

# Generate category sections
$categories = @{}
foreach ($post in $posts) {
    if ($post.categories) {
        $postCategories = if ($post.categories -is [array]) { $post.categories } else { @($post.categories) }
        foreach ($category in $postCategories) {
            if (-not $categories[$category]) {
                $categories[$category] = @()
            }
            $categories[$category] += $post
        }
    }
}

$readmeContent += "## Posts by Category"
$readmeContent += ""

foreach ($category in (Sort-InvariantText -Items @($categories.Keys))) {
    $readmeContent += "### $category"
    foreach ($post in $categories[$category]) {
        $readmeContent += "- [$($post.title)]($($post.RelativePath))"
    }
    $readmeContent += ""
}

# Generate tag sections
$tags = @{}
foreach ($post in $posts) {
    if ($post.tags) {
        $postTags = if ($post.tags -is [array]) { $post.tags } else { @($post.tags) }
        foreach ($tag in $postTags) {
            if (-not $tags[$tag]) {
                $tags[$tag] = @()
            }
            $tags[$tag] += $post
        }
    }
}

# Group tags by category for better organization.
# [ordered] is load-bearing, not decoration: the "Posts by Tags" sections are emitted in key order,
# and a plain hashtable enumerates its keys in an order that varies between processes. That made
# every run produce a different README.md, and the workflow commits README.md whenever it differs.
$tagGroups = [ordered]@{
    '.NET and C#' = @('dotnet', 'csharp', 'nuget', 'msbuild', 'visual-studio')
    'Build Systems and MSBuild' = @('msbuild', 'build-server', 'nuget', 'visual-studio')
    'Troubleshooting and Debugging' = @('debugging', 'troubleshooting')
    'Architecture and Design' = @('architecture', 'design-flaw', 'design-patterns', 'type-safety', 'strong-typing')
    'Development Tools' = @('git-worktrees', 'visual-studio')
    'Performance and Optimization' = @('performance', 'memory-management', 'concurrency', 'threading')
    'Game Development' = @('unreal-engine', 'game-development')
    'DevOps and Automation' = @('devops', 'automation', 'git')
    'Security' = @('security')
    'Observability' = @('observability', 'distributed-systems')
    'Team Practices' = @('team-management', 'case-study', 'conference-notes')
}

$readmeContent += "## Posts by Tags"
$readmeContent += ""

foreach ($groupName in $tagGroups.Keys) {
    $groupTags = $tagGroups[$groupName]
    $groupPosts = @()
    
    foreach ($tag in $groupTags) {
        if ($tags[$tag]) {
            $groupPosts += $tags[$tag]
        }
    }
    
    if ($groupPosts.Count -gt 0) {
        $readmeContent += "### $groupName"
        $uniquePosts = Sort-InvariantText -Items $groupPosts -Key { param($post) $post.title } -Unique
        foreach ($post in $uniquePosts) {
            $readmeContent += "- [$($post.title)]($($post.RelativePath))"
        }
        $readmeContent += ""
    }
}

# Blog stats
$allCategories = @()
foreach ($post in $posts) {
    if ($post.categories) {
        $allCategories += if ($post.categories -is [array]) { $post.categories } else { @($post.categories) }
    }
}
$uniqueCategories = Sort-InvariantText -Items $allCategories -Unique
$latestPost = $sortedPosts | Select-Object -First 1

$readmeContent += "## Blog Stats"
$readmeContent += ""
$readmeContent += "- **Total Posts:** $($posts.Count)"
$readmeContent += "- **Categories:** $($uniqueCategories.Count) ($($uniqueCategories -join ', '))"
if ($latestPost) {
    $readmeContent += "- **Most Recent:** $(Format-BlogDate -DateString $latestPost.created)"
}
$readmeContent += ""

# Add footer sections
$readmeContent += "## About This Blog"
$readmeContent += ""
$readmeContent += "This blog focuses on:"
$readmeContent += "- **Deep Technical Dives**: Thorough investigations into complex problems"
$readmeContent += "- **Real-World Debugging**: Actual troubleshooting experiences from development work"
$readmeContent += "- **Architecture Insights**: Analysis of design patterns, flaws, and improvements"
$readmeContent += "- **Developer Tools**: Exploration of development tooling and best practices"
$readmeContent += ""
$readmeContent += "## Search and Navigation"
$readmeContent += ""
$readmeContent += "All blog posts are written in Markdown and include comprehensive frontmatter with:"
$readmeContent += "- **Categories**: High-level topic groupings"
$readmeContent += "- **Tags**: Specific technology and concept tags"
$readmeContent += "- **Keywords**: SEO and searchability terms"
$readmeContent += "- **Status**: Draft, review, published tracking"
$readmeContent += "- **Dates**: Created and modified timestamps"
$readmeContent += ""
$readmeContent += "## Connect"
$readmeContent += ""
$readmeContent += "Feel free to open issues or discussions if you have questions about any of the blog posts or want to suggest topics for future articles."
$readmeContent += ""
$readmeContent += "## Automation"
$readmeContent += ""
$readmeContent += "This blog index is automatically regenerated when new posts are pushed to the repository, using GitHub Actions."
$readmeContent += "The workflow runs the `scripts/Rebuild-BlogIndex.ps1` PowerShell script to parse all markdown files and rebuild this index."
$readmeContent += ""
$readmeContent += "---"
$readmeContent += ""
$readmeContent += "*This blog is maintained as a Git repository to track changes, encourage collaboration, and provide version history for all content.*"

# Write README.md
# Written through .NET rather than Set-Content: -Encoding UTF8 writes a byte order mark under Windows
# PowerShell 5.1 and none under pwsh 7, and Set-Content ends the file with the platform's newline.
# .NET needs a full path, because its current directory isn't PowerShell's current location.
$readmePath = Join-Path -Path $Path -ChildPath "README.md"
$readmeFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($readmePath)
[System.IO.File]::WriteAllText($readmeFullPath, ($readmeContent -join "`n") + "`n", (New-Object System.Text.UTF8Encoding $false))

Write-Host "Blog index rebuilt successfully!" -ForegroundColor Green
Write-Host "Generated index for $($posts.Count) blog post(s)" -ForegroundColor Green
Write-Host "README.md updated at: $readmePath" -ForegroundColor Green 