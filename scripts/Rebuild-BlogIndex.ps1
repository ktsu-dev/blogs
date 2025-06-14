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
        $metadata['RelativePath'] = "./$($fileInfo.Name)"
        
        return $metadata
    }
    catch {
        Write-Error "Error processing file $FilePath : $($_.Exception.Message)"
        return $null
    }
}

# Function to format date for display
function Format-BlogDate {
    param([string]$DateString)
    
    if ([string]::IsNullOrEmpty($DateString)) {
        return "Unknown"
    }
    
    try {
        $date = [DateTime]::Parse($DateString)
        return $date.ToString("MMMM d, yyyy")
    }
    catch {
        return $DateString
    }
}

# Main script
Write-Host "Rebuilding blog index..." -ForegroundColor Cyan

# Find all markdown files except README.md
$blogPosts = Get-ChildItem -Path $Path -Filter "*.md" -File | 
    Where-Object { $_.Name -ne "README.md" }

Write-Host "Found $($blogPosts.Count) blog post(s)" -ForegroundColor Green

# Parse metadata from each post
$posts = @()
foreach ($post in $blogPosts) {
    Write-Host "   Processing: $($post.Name)" -ForegroundColor Gray
    $metadata = Get-BlogPostMetadata -FilePath $post.FullName
    if ($metadata) {
        $posts += $metadata
    }
}

if ($posts.Count -eq 0) {
    Write-Error "No valid blog posts found with frontmatter"
    exit 1
}

# Sort posts by date (newest first)
$sortedPosts = $posts | Sort-Object { 
    try { [DateTime]::Parse($_.created) } 
    catch { [DateTime]::MinValue } 
} -Descending

# Generate README content
$readmeContent = @()
$readmeContent += "# ktsu.dev Blog"
$readmeContent += ""
$readmeContent += "Welcome to my technical blog repository! This is where I share my experiences, insights, and deep dives into software development, debugging adventures, and architectural discoveries."
$readmeContent += ""

# Latest Posts section
$readmeContent += "## Latest Posts"
$readmeContent += ""

foreach ($post in $sortedPosts) {
    $readmeContent += "### [$($post.title)]($($post.RelativePath))"
    $publishedDate = Format-BlogDate -DateString $post.created
    $status = if ($post.status) { $post.status } else { "Unknown" }
    $readmeContent += "**Published:** $publishedDate | **Status:** $status"
    
    if ($post.categories) {
        $categories = if ($post.categories -is [array]) { $post.categories -join ', ' } else { $post.categories }
        $readmeContent += "**Categories:** $categories"
    }
    
    if ($post.tags) {
        $tags = if ($post.tags -is [array]) { $post.tags -join ', ' } else { $post.tags }
        $readmeContent += "**Tags:** $tags"
    }
    
    $readmeContent += ""
    if ($post.description) {
        $readmeContent += $post.description
    }
    $readmeContent += ""
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

foreach ($category in ($categories.Keys | Sort-Object)) {
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

# Group tags by category for better organization
$tagGroups = @{
    '.NET and C#' = @('dotnet', 'csharp', 'nuget', 'msbuild', 'visual-studio')
    'Build Systems and MSBuild' = @('msbuild', 'build-server', 'nuget', 'visual-studio')
    'Troubleshooting and Debugging' = @('debugging', 'troubleshooting')
    'Architecture and Design' = @('architecture', 'design-flaw')
    'Development Tools' = @('git-worktrees', 'visual-studio')
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
        $uniquePosts = $groupPosts | Sort-Object -Property title -Unique
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
$uniqueCategories = $allCategories | Sort-Object -Unique
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
$readmeContent += "- **Status**: Draft, review, complete tracking"
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
$readmePath = Join-Path -Path $Path -ChildPath "README.md"
$readmeContent -join "`n" | Set-Content -Path $readmePath -Encoding UTF8

Write-Host "Blog index rebuilt successfully!" -ForegroundColor Green
Write-Host "Generated index for $($posts.Count) blog post(s)" -ForegroundColor Green
Write-Host "README.md updated at: $readmePath" -ForegroundColor Green 