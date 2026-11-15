<#
.SYNOPSIS
Converts 8 AM Class TXT/BAK runtime logs into a CSV.
.DESCRIPTION
Reads one or more files without modifying them. Only lines in the format
"8AMC <Unix epoch seconds> <event> <details>" are included. Exact duplicate
events are removed and records are ordered by timestamp, preserving input
order for events with the same timestamp. LocalTime uses Asia/Shanghai.
.PARAMETER InputPath
One or more TXT/BAK log file paths. Paths are treated literally.
.PARAMETER OutputPath
CSV destination. Defaults to 8am-class-events.csv beside the first input file.
.EXAMPLE
.\tools\read-run-log.ps1 -InputPath '8am-class.BAK','8am-class.TXT'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$InputPath,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$inputFiles = @(
    foreach ($path in $InputPath) {
        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') {
            throw 'Each InputPath must identify a file.'
        }
        $item.FullName
    }
)

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([System.IO.Path]::GetDirectoryName($inputFiles[0])) '8am-class-events.csv'
}
$outputFile = [System.IO.Path]::GetFullPath($OutputPath)
foreach ($inputFile in $inputFiles) {
    if ([string]::Equals($inputFile, $outputFile, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputPath must differ from every input file.'
    }
}

try {
    $timeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('Asia/Shanghai')
} catch {
    # Windows PowerShell may require the Windows identifier for the same zone.
    $timeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
}

$records = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$pattern = '^8AMC[ \t]+(?<epoch>-?\d+)[ \t]+(?<event>\S+)(?:[ \t]+(?<details>.*))?$'
$sequence = 0
$duplicates = 0
$skipped = 0
foreach ($inputFile in $inputFiles) {
    foreach ($line in [System.IO.File]::ReadLines($inputFile)) {
        $match = [regex]::Match($line, $pattern)
        [long]$epoch = 0
        if (!$match.Success -or ![long]::TryParse($match.Groups['epoch'].Value, [ref]$epoch)) {
            $skipped++
            continue
        }
        try {
            $instant = [System.DateTimeOffset]::FromUnixTimeSeconds($epoch)
            $local = [System.TimeZoneInfo]::ConvertTime($instant, $timeZone)
        } catch {
            $skipped++
            continue
        }
        $eventName = $match.Groups['event'].Value
        $details = $match.Groups['details'].Value
        $key = "$epoch`0$eventName`0$details"
        if (!$seen.Add($key)) {
            $duplicates++
            continue
        }
        $records.Add([pscustomobject]@{
            Epoch = $epoch
            LocalTime = $local.ToString('yyyy-MM-dd HH:mm:ss zzz', [System.Globalization.CultureInfo]::InvariantCulture)
            Event = $eventName
            Details = $details
            Sequence = $sequence
        })
        $sequence++
    }
}

if ($records.Count -eq 0) {
    [System.IO.File]::WriteAllText($outputFile, '"Epoch","LocalTime","Event","Details"' + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
} else {
    $records |
        Sort-Object -Property Epoch, Sequence |
        Select-Object Epoch, LocalTime, Event, Details |
        Export-Csv -LiteralPath $outputFile -NoTypeInformation -Encoding UTF8
}
Write-Output "Exported $($records.Count) unique events; removed $duplicates duplicate records; skipped $skipped unmatched or invalid lines."
