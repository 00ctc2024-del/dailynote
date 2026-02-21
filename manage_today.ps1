param(
    [string]$BasePath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

function Get-DiaryHeaderTitle {
    return (([char[]](0x65E5,0x8A18,0x5185,0x5BB9)) -join '')
}

function Get-DiaryHeaderLine {
    return '## ' + (Get-DiaryHeaderTitle)
}

function New-TodayTemplate {
    param(
        [string]$Path,
        [string]$DateText
    )

    $headerLine = Get-DiaryHeaderLine
    $content = @(
        $headerLine,
        '',
        ''
    )

    Set-Content -Path $Path -Value $content -Encoding UTF8
}

function Set-DiaryHeader {
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        $Text = ''
    }

    $headerLine = Get-DiaryHeaderLine
    $escapedHeader = [regex]::Escape($headerLine)
    $normalized = $Text -replace "`r`n", "`n"

    if ($normalized -match ('(?m)^' + $escapedHeader + '\s*$')) {
        return ($normalized -replace "`n", "`r`n")
    }

    $trimmed = $normalized.TrimStart("`n")
    $withHeader = $headerLine + "`n`n" + $trimmed
    return ($withHeader -replace "`n", "`r`n")
}

function Remove-ZettelSection {
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $normalized = $Text -replace "`r`n", "`n"
    $match = [regex]::Match($normalized, '(?im)^##\s+zettelconnection\s*$')
    if ($match.Success) {
        $normalized = $normalized.Substring(0, $match.Index)
    }

    return ($normalized.TrimEnd() -replace "`n", "`r`n")
}

function Get-DiaryBody {
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $headerLine = Get-DiaryHeaderLine
    $normalized = $Text -replace "`r`n", "`n"
    $withoutZettel = [regex]::Replace($normalized, '(?is)^(.+?)(?m)^##\s+zettelconnection\s*$.*$', '$1')

    $pattern = '(?is)^\s*' + [regex]::Escape($headerLine) + '\s*(.*)$'
    $match = [regex]::Match($withoutZettel, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return $withoutZettel.Trim()
}

function Get-KeywordTokens {
    param(
        [string]$Text
    )

    $result = New-Object 'System.Collections.Generic.HashSet[string]'
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $result
    }

    $stopWords = @(
        'with', 'this', 'that', 'have', 'been', 'were', 'your', 'today', 'journal',
        'the', 'and', 'for', 'from', 'into', 'about'
    )
    $stopSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($word in $stopWords) {
        [void]$stopSet.Add($word)
    }

    $tokenMatches = [regex]::Matches($Text, '[\p{IsCJKUnifiedIdeographs}]{2,}|[A-Za-z][A-Za-z0-9_-]{2,}')
    foreach ($match in $tokenMatches) {
        $token = $match.Value.ToLowerInvariant()
        if ($token.Length -lt 2) {
            continue
        }
        if ($stopSet.Contains($token)) {
            continue
        }
        [void]$result.Add($token)
    }

    return $result
}

function Get-RelatedLinks {
    param(
        [string]$CurrentBody,
        [string]$BaseDir,
        [string]$ExcludePath,
        [int]$MaxLinks = 5
    )

    $currentTokens = Get-KeywordTokens -Text $CurrentBody
    if ($currentTokens.Count -eq 0) {
        return @()
    }

    $candidates = @()
    $allMd = Get-ChildItem -Path $BaseDir -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue
    $seenNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $allMd) {
        if ($file.FullName -eq $ExcludePath) {
            continue
        }

        if ($file.Name -ieq 'today.md' -or $file.Name -ieq 'README.md') {
            continue
        }

        $text = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $body = Get-DiaryBody -Text $text
        $tokens = Get-KeywordTokens -Text $body
        if ($tokens.Count -eq 0) {
            continue
        }

        $score = 0
        $overlap = @()
        foreach ($token in $currentTokens) {
            if ($tokens.Contains($token)) {
                $score++
                $overlap += $token
            }
        }

        if ($score -gt 0) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            if ($seenNames.Contains($baseName)) {
                continue
            }
            [void]$seenNames.Add($baseName)

            $candidates += [PSCustomObject]@{
                Name = $baseName
                Score = $score
                Overlap = $overlap
            }
        }
    }

    if (-not $candidates) {
        return @()
    }

    $selected = $candidates |
        Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Name'; Descending = $false } |
        Select-Object -First $MaxLinks

    $links = @()
    foreach ($item in $selected) {
        $tagTokens = @()
        if ($item.Overlap -and $item.Overlap.Count -gt 0) {
            $tagTokens = $item.Overlap | Sort-Object -Unique | Select-Object -First 3
        }

        $tagText = ''
        if ($tagTokens.Count -gt 0) {
            $tags = @()
            foreach ($tag in $tagTokens) {
                $tags += ('#' + $tag)
            }
            $tagText = ' ' + ($tags -join ' ')
        }

        $links += ('- [[' + $item.Name + ']]' + $tagText)
    }

    return $links
}

function New-ArchivedContent {
    param(
        [string]$CurrentText,
        [string[]]$RelatedLinks
    )

    $headerFixed = Set-DiaryHeader -Text $CurrentText
    $withoutZettel = Remove-ZettelSection -Text $headerFixed

    $lines = @()
    $lines += $withoutZettel
    $lines += ''
    $lines += '## zettelconnection'
    $lines += ''
    if ($RelatedLinks -and $RelatedLinks.Count -gt 0) {
        $lines += $RelatedLinks
    }

    return ($lines -join "`r`n")
}

function Get-ArchiveFilePath {
    param(
        [string]$Dir,
        [string]$BaseName
    )

    $path = Join-Path -Path $Dir -ChildPath ($BaseName + '.md')
    if (-not (Test-Path -Path $path)) {
        return $path
    }

    $index = 1
    while ($true) {
        $candidate = Join-Path -Path $Dir -ChildPath ($BaseName + '-' + $index + '.md')
        if (-not (Test-Path -Path $candidate)) {
            return $candidate
        }
        $index++
    }
}

if (-not $BasePath) {
    throw 'BasePath could not be resolved.'
}

$todayFile = Join-Path -Path $BasePath -ChildPath 'today.md'
$stateFile = Join-Path -Path $BasePath -ChildPath '.today-state.json'
$now = Get-Date
$todayDate = $now.ToString('yyyy-MM-dd')

$activeDate = $null
if (Test-Path -Path $stateFile) {
    try {
        $state = Get-Content -Path $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.activeDate -match '^\d{4}-\d{2}-\d{2}$') {
            $activeDate = $state.activeDate
        }
    }
    catch {
        $activeDate = $null
    }
}

if (-not $activeDate -and (Test-Path -Path $todayFile)) {
    $activeDate = (Get-Item -Path $todayFile).LastWriteTime.ToString('yyyy-MM-dd')
}

if (-not $activeDate) {
    $activeDate = $todayDate
}

if ((Test-Path -Path $todayFile) -and $activeDate -ne $todayDate) {
    $currentText = Get-Content -Path $todayFile -Raw -Encoding UTF8
    $currentText = Set-DiaryHeader -Text $currentText
    $currentBody = Get-DiaryBody -Text $currentText
    $relatedLinks = Get-RelatedLinks -CurrentBody $currentBody -BaseDir $BasePath -ExcludePath $todayFile
    $archivedContent = New-ArchivedContent -CurrentText $currentText -RelatedLinks $relatedLinks

    Set-Content -Path $todayFile -Value $archivedContent -Encoding UTF8

    $archiveDate = [DateTime]::ParseExact($activeDate, 'yyyy-MM-dd', $null)
    $targetDir = Join-Path -Path $BasePath -ChildPath $archiveDate.ToString('yyyy')
    $targetDir = Join-Path -Path $targetDir -ChildPath $archiveDate.ToString('MM')
    $targetDir = Join-Path -Path $targetDir -ChildPath $archiveDate.ToString('dd')

    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

    $archiveName = $archiveDate.ToString('yyyy-MM-dd')
    $targetFile = Get-ArchiveFilePath -Dir $targetDir -BaseName $archiveName
    Move-Item -Path $todayFile -Destination $targetFile
}

if (-not (Test-Path -Path $todayFile)) {
    New-TodayTemplate -Path $todayFile -DateText $todayDate
}
else {
    $existing = Get-Content -Path $todayFile -Raw -Encoding UTF8
    $normalized = Set-DiaryHeader -Text $existing
    if ($normalized -ne $existing) {
        Set-Content -Path $todayFile -Value $normalized -Encoding UTF8
    }
}

$newState = [PSCustomObject]@{
    activeDate = $todayDate
    updatedAt = (Get-Date).ToString('o')
}
$newState | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
