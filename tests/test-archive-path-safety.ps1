#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $project 'scripts/unpack-flow.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) "unpack-flow-path-safety-$([guid]::NewGuid().ToString('N'))"
try {
    $inputRoot = Join-Path $root 'input'
    $outputRoot = Join-Path $root 'output'
    New-Item -ItemType Directory -Path $inputRoot,$outputRoot | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function New-TestZip([string]$Path, [string]$EntryName, [bool]$Link = $false) {
        $stream = [IO.File]::Create($Path)
        try {
            $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
            try {
                $entry = $zip.CreateEntry($EntryName)
                if ($Link) { $entry.ExternalAttributes = -1577123840 }
                $writer = [IO.StreamWriter]::new($entry.Open())
                try { $writer.WriteLine('blocked') } finally { $writer.Dispose() }
            } finally { $zip.Dispose() }
        } finally { $stream.Dispose() }
    }

    $valid = Join-Path $inputRoot 'valid.zip'
    New-TestZip $valid 'safe/marker.txt'
    & $engine run $valid -Output (Join-Path $root 'valid-output') -StopOnError
    if (-not (Test-Path -LiteralPath (Join-Path $root 'valid-output/safe/marker.txt'))) { throw 'valid ZIP failed' }

    foreach ($case in @(
        @{ Name='parent.zip'; Entry='../escape-parent.txt' },
        @{ Name='absolute.zip'; Entry='/escape-absolute.txt' },
        @{ Name='drive.zip'; Entry='C:\escape-drive.txt' },
        @{ Name='mixed.zip'; Entry='safe\..\..\escape-mixed.txt' },
        @{ Name='link.zip'; Entry='safe-link'; Link=$true }
    )) {
        $archive = Join-Path $inputRoot $case.Name
        New-TestZip $archive $case.Entry ([bool]$case.Link)
        $failed = $false
        try { & $engine run $archive -Output $outputRoot -StopOnError } catch { $failed = $true }
        if (-not $failed) { throw "unsafe ZIP unexpectedly succeeded: $($case.Name)" }
    }

    $inner = Join-Path $inputRoot 'inner.zip'
    New-TestZip $inner '../../escape-inner.txt'
    $outer = Join-Path $inputRoot 'outer.zip'
    $outerStream = [IO.File]::Create($outer)
    try {
        $outerZip = [IO.Compression.ZipArchive]::new($outerStream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $outerEntry = $outerZip.CreateEntry('nested/inner.zip')
            $entryStream = $outerEntry.Open()
            try {
                $innerStream = [IO.File]::OpenRead($inner)
                try { $innerStream.CopyTo($entryStream) } finally { $innerStream.Dispose() }
            } finally { $entryStream.Dispose() }
        } finally { $outerZip.Dispose() }
    } finally { $outerStream.Dispose() }
    $nestedFailed = $false
    try { & $engine run $outer -Output (Join-Path $root 'nested-output') -StopOnError } catch { $nestedFailed = $true }
    if (-not $nestedFailed) { throw 'unsafe recursive inner ZIP unexpectedly succeeded' }

    foreach ($name in @('escape-parent.txt','escape-absolute.txt','escape-drive.txt','escape-mixed.txt','escape-inner.txt')) {
        if (Get-ChildItem -LiteralPath $root -Filter $name -Recurse -Force -ErrorAction SilentlyContinue) {
            throw "archive traversal wrote a file: $name"
        }
    }
    if (Get-ChildItem -LiteralPath $root -Directory -Recurse -Force | Where-Object { $_.Name -match '^(\.uf_|\.ufi_)' }) {
        throw 'temporary extraction directory was not cleaned'
    }
    'PowerShell archive path safety: PASS'
} finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
