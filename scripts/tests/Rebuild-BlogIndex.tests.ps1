#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Checks Rebuild-BlogIndex.ps1 against the failures it actually had.

.DESCRIPTION
    Every case here is a defect observed by running the script, not a hypothetical.
    Run with pwsh: ./scripts/tests/Rebuild-BlogIndex.tests.ps1

    Fixtures are generated into a temp directory so the cases do not depend on which posts
    happen to be in content/blog on the day they run.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Script = Join-Path (Join-Path $PSScriptRoot '..') 'Rebuild-BlogIndex.ps1' | Resolve-Path
$script:Pwsh = (Get-Process -Id $PID).Path
$script:Failures = 0
$script:Count = 0

# Builds a blog repository layout: $root/content/blog/<name>.md for each post supplied.
function New-Fixture {
    param([hashtable[]]$Posts)

    $root = Join-Path ([System.IO.Path]::GetTempPath()) "blog-index-$([guid]::NewGuid())"
    $blog = Join-Path (Join-Path $root 'content') 'blog'
    New-Item -ItemType Directory -Path $blog -Force | Out-Null

    foreach ($post in $Posts) {
        $frontmatter = @(
            '---'
            "title: `"$($post.title)`""
            'author: "Test Author"'
            "created: $($post.created)"
            "status: $($post.status)"
            "description: `"Description of $($post.title)`""
            "categories: [`"$($post.category)`"]"
            "tags: [`"$($post.tag)`"]"
            "slug: `"$($post.slug)`""
            '---'
            ''
            'Body text.'
        ) -join "`n"

        Set-Content -LiteralPath (Join-Path $blog "$($post.slug).md") -Value $frontmatter
    }

    return $root
}

function New-Post {
    param([string]$Slug, [string]$Title, [string]$Created, [string]$Status = 'published',
        [string]$Category = 'Development', [string]$Tag = 'csharp')

    return @{ slug = $Slug; title = $Title; created = $Created; status = $Status; category = $Category; tag = $Tag }
}

# The script is run as a child process rather than dot-sourced, for two reasons: it is how every
# real caller invokes it (the workflow, rebuild-blog.bat, and the command in CLAUDE.md), and the
# Set-StrictMode above would otherwise leak into it and fail on conveniences it legitimately uses.
# It also gives each run its own process, which the determinism case below depends on.
function Invoke-Index {
    param([string]$Root)

    & $script:Pwsh -NoProfile -File $script:Script -Path $Root *>$null
    if ($LASTEXITCODE -ne 0) {
        throw "the script exited with $LASTEXITCODE"
    }
    return Get-Content -LiteralPath (Join-Path $Root 'README.md') -Raw
}

function Assert-Case {
    param([string]$Name, [scriptblock]$Body)

    $script:Count++
    try {
        $problem = & $Body
        if ($problem) {
            $script:Failures++
            Write-Host "FAIL  $Name" -ForegroundColor Red
            Write-Host "      $problem" -ForegroundColor Red
            return
        }
        Write-Host "ok    $Name" -ForegroundColor Green
    }
    catch {
        $script:Failures++
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host "      threw: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# The reason this file exists. The "Posts by Tags" sections were emitted in the key order of a
# plain hashtable, which varies between processes, so two runs over identical content produced
# different README.md files. refresh-blog-index.yml commits README.md whenever it differs, so
# this turned into an "Auto-update blog index" commit on every push, forever.
#
# Two runs in ONE process cannot catch it: string hashing is randomized per process, not per
# call. The runs have to be in separate pwsh processes.
Assert-Case -Name 'two runs over the same content produce the same index' -Body {
    $root = New-Fixture -Posts @(
        (New-Post -Slug 'alpha' -Title 'Alpha' -Created '2025-01-01' -Tag 'csharp')
        (New-Post -Slug 'bravo' -Title 'Bravo' -Created '2025-02-01' -Tag 'debugging')
        (New-Post -Slug 'charlie' -Title 'Charlie' -Created '2025-03-01' -Tag 'architecture')
        (New-Post -Slug 'delta' -Title 'Delta' -Created '2025-04-01' -Tag 'performance')
        (New-Post -Slug 'echo' -Title 'Echo' -Created '2025-05-01' -Tag 'security')
        (New-Post -Slug 'foxtrot' -Title 'Foxtrot' -Created '2025-06-01' -Tag 'automation')
        (New-Post -Slug 'golf' -Title 'Golf' -Created '2025-07-01' -Tag 'observability')
        (New-Post -Slug 'hotel' -Title 'Hotel' -Created '2025-08-01' -Tag 'case-study')
        (New-Post -Slug 'india' -Title 'India' -Created '2025-09-01' -Tag 'unreal-engine')
        (New-Post -Slug 'juliet' -Title 'Juliet' -Created '2025-10-01' -Tag 'git-worktrees')
        (New-Post -Slug 'kilo' -Title 'Kilo' -Created '2025-11-01' -Tag 'msbuild')
    )
    try {
        $renders = @(1..4 | ForEach-Object { Invoke-Index -Root $root })

        $distinct = @($renders | Select-Object -Unique)
        if ($distinct.Count -ne 1) {
            $orders = $renders | ForEach-Object {
                (@($_ -split "`n" | Select-String -Pattern '^### ' -Raw) -join ' | ')
            }
            return "$($distinct.Count) distinct results across 4 runs. Section orders:`n      $($orders -join "`n      ")"
        }
        return $null
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

# The tag sections are an editorial order, not an alphabetical one, so the table's order is the
# expected output order. Pinning it is what keeps the [ordered] on $tagGroups from being
# "simplified" back to a plain hashtable later.
Assert-Case -Name 'tag sections follow the order declared in $tagGroups' -Body {
    # One tag per group, each chosen because it belongs to exactly one group, so all 11 sections
    # are emitted. Covering every group is what gives the case its teeth: with a handful of
    # sections an unordered hashtable lands on the right order often enough to pass by luck.
    $tagForGroup = [ordered]@{
        '.NET and C#'                 = 'csharp'
        'Build Systems and MSBuild'   = 'build-server'
        'Troubleshooting and Debugging' = 'debugging'
        'Architecture and Design'     = 'architecture'
        'Development Tools'           = 'git-worktrees'
        'Performance and Optimization' = 'performance'
        'Game Development'            = 'unreal-engine'
        'DevOps and Automation'       = 'automation'
        'Security'                    = 'security'
        'Observability'               = 'observability'
        'Team Practices'              = 'case-study'
    }

    $n = 0
    $posts = foreach ($group in $tagForGroup.Keys) {
        $n++
        $id = '{0:D2}' -f $n
        New-Post -Slug "post-$id" -Title "Post $id" -Created "2025-01-$id" -Tag $tagForGroup[$group]
    }

    $root = New-Fixture -Posts $posts
    try {
        $readme = Invoke-Index -Root $root
        $tagsSection = ($readme -split '## Posts by Tags')[1]
        $sections = @($tagsSection -split "`n" | Select-String -Pattern '^### ' -Raw)

        $expected = @($tagForGroup.Keys | ForEach-Object { "### $_" })
        if (($sections -join '|') -ne ($expected -join '|')) {
            return "expected [$($expected -join ', ')]`n      got      [$($sections -join ', ')]"
        }
        return $null
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

# Sort-Object is not stable. With few enough tied items it happens to preserve input order, so a
# two-post fixture proves nothing — this uses enough tied posts to get past that threshold and
# actually scramble. Two posts already share a created date in content/blog today.
Assert-Case -Name 'posts sharing a created date are ordered by title' -Body {
    $posts = 1..40 | ForEach-Object {
        $n = '{0:D2}' -f $_
        New-Post -Slug "post-$n" -Title "Post $n" -Created '2025-07-18'
    }
    $root = New-Fixture -Posts $posts
    try {
        $readme = Invoke-Index -Root $root
        $titles = @($readme -split "`n" |
            Select-String -Pattern '^### \[(Post \d\d)\]' |
            ForEach-Object { $_.Matches[0].Groups[1].Value })

        $expected = @(1..40 | ForEach-Object { 'Post {0:D2}' -f $_ })
        if (($titles -join ',') -ne ($expected -join ',')) {
            return "tied posts came out as [$($titles -join ', ')]"
        }
        return $null
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

# The acceptance criterion from ktsu-dev/blogs#2: the documented command has to find the posts on
# whatever platform it runs on. The path is built from a separator-free child segment so that it
# resolves the same way under pwsh on Linux/macOS and Windows PowerShell 5.1 via rebuild-blog.bat.
Assert-Case -Name 'every published post is found and indexed' -Body {
    $root = New-Fixture -Posts @(
        (New-Post -Slug 'alpha' -Title 'Alpha' -Created '2025-01-01')
        (New-Post -Slug 'bravo' -Title 'Bravo' -Created '2025-02-01')
        (New-Post -Slug 'charlie' -Title 'Charlie' -Created '2025-03-01')
    )
    try {
        $readme = Invoke-Index -Root $root
        foreach ($title in @('Alpha', 'Bravo', 'Charlie')) {
            if ($readme -notmatch "\[$title\]\(\./content/blog/") {
                return "$title is missing from the index"
            }
        }
        if ($readme -notmatch '\*\*Total Posts:\*\* 3') {
            return 'the index did not report 3 posts'
        }
        return $null
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

# Only status: published reaches the index. Guards the filter against a refactor of the sort.
Assert-Case -Name 'drafts and reviews stay out of the index' -Body {
    $root = New-Fixture -Posts @(
        (New-Post -Slug 'shipped' -Title 'Shipped' -Created '2025-01-01' -Status 'published')
        (New-Post -Slug 'wip' -Title 'Wip' -Created '2025-02-01' -Status 'draft')
        (New-Post -Slug 'pending' -Title 'Pending' -Created '2025-03-01' -Status 'review')
    )
    try {
        $readme = Invoke-Index -Root $root
        if ($readme -match '\[Wip\]' -or $readme -match '\[Pending\]') {
            return 'an unpublished post reached the index'
        }
        if ($readme -notmatch '\[Shipped\]') {
            return 'the published post is missing'
        }
        return $null
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host "$script:Failures of $script:Count case(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host "All $script:Count case(s) passed." -ForegroundColor Green
