<#
.SYNOPSIS
  Walk Symphony scan rows, probe each file's NTFS allocation with
  GetCompressedFileSizeW, and insert the results into symphony.file_physical
  in batched HTTP POSTs.

.DESCRIPTION
  Reads `run_id \t file_uri` on stdin (one row per line).
  Writes to ClickHouse via batched TSV INSERTs with exponential-backoff retry.
  Skipped files (not found, Win32 errors) are logged to a sidecar file and
  omitted from file_physical; missing rows are reconstructed at validation
  time via set-diff against scan_results.

.PARAMETER RunId
  The run_id currently being walked. Used in pre-flight output only —
  actual run_id per row comes from stdin.

.EXAMPLE
  clickhouse-client -q "SELECT run_id, file_uri FROM symphony.scan_results
      WHERE run_id='abc' AND filename != '' FORMAT TabSeparated" \
    | pwsh -NoProfile -File probe-physical-size.ps1 -RunId abc
#>

param(
    [Parameter(Mandatory=$true)][string]$RunId,
    [string]$ClickHouseUrl  = "http://localhost:8123",
    [string]$CHUser         = "symphony",
    [string]$CHPassword     = "symphony",
    [string]$Database       = "symphony",
    [string]$Table          = "file_physical",
    [int]   $BatchSize      = 25000,
    [string]$ErrorLogPath   = "walker-errors.log",
    [string]$FailedBatchDir = "failed-batches",
    [int]   $ProgressEveryN = 1   # print a line every N batches
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# P/Invoke: GetCompressedFileSizeW (kernel32)
# Returns allocation bytes for sparse/compressed files; equivalent to what
# 'dir' shows as "size on disk". Safe for normal files too.
# ---------------------------------------------------------------------------
if (-not ("Walker.K32" -as [type])) {
    Add-Type -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern uint GetCompressedFileSizeW(string lpFileName, out uint lpFileSizeHigh);
"@ -Name K32 -Namespace Walker
}

function Convert-UriToWindowsPath {
    param([Parameter(Mandatory=$true)][string]$Uri)
    if ($Uri -notmatch '^win://[^/]+/([A-Za-z])/(.*)$') {
        throw "Unrecognised uri: $Uri"
    }
    $drive   = $matches[1]
    $rest    = $matches[2] -replace '/', '\'
    $decoded = [System.Uri]::UnescapeDataString($rest)
    $win     = "{0}:\{1}" -f $drive, $decoded
    if ($win.Length -gt 248) { $win = "\\?\$win" }
    return $win
}

function Get-PhysicalSize {
    param([Parameter(Mandatory=$true)][string]$Path)
    $high = [uint32]0
    $low  = [Walker.K32]::GetCompressedFileSizeW($Path, [ref]$high)
    if ($low -eq 0xFFFFFFFF) {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($err -ne 0) {
            throw [System.ComponentModel.Win32Exception]::new($err)
        }
    }
    return ([uint64]$high * [uint64]4294967296) + [uint64]$low
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
$authBytes  = [Text.Encoding]::ASCII.GetBytes("${CHUser}:${CHPassword}")
$authHeader = "Basic " + [Convert]::ToBase64String($authBytes)
$headers    = @{ Authorization = $authHeader }

try {
    $ping = Invoke-WebRequest -Uri "$ClickHouseUrl/ping" -UseBasicParsing -TimeoutSec 5
    if ($ping.StatusCode -ne 200) { throw "HTTP $($ping.StatusCode)" }
} catch {
    throw "ClickHouse /ping failed at $ClickHouseUrl : $($_.Exception.Message). Is WSL up? (see RESUME.md)"
}

$verifyQuery = "SELECT count() FROM system.tables WHERE database='$Database' AND name='$Table'"
$verifyUri   = "$ClickHouseUrl/?query=" + [Uri]::EscapeDataString($verifyQuery)
$verifyResp  = Invoke-WebRequest -Uri $verifyUri -Headers $headers -UseBasicParsing -TimeoutSec 5
if ($verifyResp.Content.Trim() -ne "1") {
    throw "Table ${Database}.${Table} not found — run schema.sql first"
}

if (-not (Test-Path $FailedBatchDir)) {
    New-Item -ItemType Directory -Path $FailedBatchDir -Force | Out-Null
}

"=== walker start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') RunId=$RunId BatchSize=$BatchSize ===" |
    Add-Content -Path $ErrorLogPath

$insertQuery = "INSERT INTO ${Database}.${Table} (run_id, file_uri, allocated) FORMAT TabSeparated"
$insertUri   = "$ClickHouseUrl/?query=" + [Uri]::EscapeDataString($insertQuery)

# ---------------------------------------------------------------------------
# Batch flush with exponential-backoff retry
# ---------------------------------------------------------------------------
function Invoke-BatchInsert {
    param(
        [Parameter(Mandatory=$true)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory=$true)][int]$BatchNum
    )
    if ($Lines.Count -eq 0) { return }
    $body   = ($Lines -join "`n") + "`n"
    $delays = @(1, 4, 16)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            Invoke-RestMethod -Uri $insertUri `
                              -Method Post `
                              -Body $body `
                              -ContentType 'text/tab-separated-values' `
                              -Headers $headers `
                              -TimeoutSec 120 | Out-Null
            return
        } catch {
            if ($attempt -lt 2) {
                "[{0}] batch {1} attempt {2} failed: {3} — retrying in {4}s" -f `
                    (Get-Date -Format 'HH:mm:ss'), $BatchNum, ($attempt + 1), `
                    $_.Exception.Message, $delays[$attempt] |
                    Add-Content -Path $ErrorLogPath
                Start-Sleep -Seconds $delays[$attempt]
            } else {
                $dumpName = "batch-{0:D5}-{1}.tsv" -f $BatchNum, (Get-Date -Format 'yyyyMMddHHmmss')
                $dumpPath = Join-Path $FailedBatchDir $dumpName
                [IO.File]::WriteAllText($dumpPath, $body, [Text.UTF8Encoding]::new($false))
                "[{0}] batch {1} FAILED after 3 attempts, dumped {2} rows to {3}: {4}" -f `
                    (Get-Date -Format 'HH:mm:ss'), $BatchNum, $Lines.Count, $dumpPath, $_.Exception.Message |
                    Add-Content -Path $ErrorLogPath
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Main loop — read stdin, probe, buffer, flush
# ---------------------------------------------------------------------------
$buffer     = [System.Collections.Generic.List[string]]::new($BatchSize)
$batchNum   = 0
$totalRows  = 0
$errors     = 0
$startTime  = Get-Date

$stdin = [Console]::In
while ($true) {
    $line = $stdin.ReadLine()
    if ($null -eq $line) { break }
    if ($line.Length -eq 0) { continue }

    $tabIdx = $line.IndexOf("`t")
    if ($tabIdx -lt 0) { continue }
    $rowRunId = $line.Substring(0, $tabIdx)
    $fileUri  = $line.Substring($tabIdx + 1)

    try {
        $winPath = Convert-UriToWindowsPath $fileUri
    } catch {
        "PATH_CONVERT`t$fileUri`t$($_.Exception.Message)" | Add-Content -Path $ErrorLogPath
        $errors++
        continue
    }

    if (-not [System.IO.File]::Exists($winPath)) {
        "MISSING`t$fileUri" | Add-Content -Path $ErrorLogPath
        $errors++
        continue
    }

    try {
        $allocated = Get-PhysicalSize -Path $winPath
    } catch {
        "WIN32`t$fileUri`t$($_.Exception.Message)" | Add-Content -Path $ErrorLogPath
        $errors++
        continue
    }

    [void]$buffer.Add(("{0}`t{1}`t{2}" -f $rowRunId, $fileUri, $allocated))

    if ($buffer.Count -ge $BatchSize) {
        $batchNum++
        Invoke-BatchInsert -Lines $buffer -BatchNum $batchNum
        $totalRows += $buffer.Count
        $buffer.Clear()

        if ($batchNum % $ProgressEveryN -eq 0) {
            $elapsed = (Get-Date) - $startTime
            $rate    = [int]($totalRows / [Math]::Max($elapsed.TotalSeconds, 1))
            "[{0:HH:mm:ss}] batch {1,5}  rows {2,12:N0}  rate {3,7:N0}/s  errors {4}" -f `
                (Get-Date), $batchNum, $totalRows, $rate, $errors | Write-Host
        }
    }
}

# Final flush
if ($buffer.Count -gt 0) {
    $batchNum++
    Invoke-BatchInsert -Lines $buffer -BatchNum $batchNum
    $totalRows += $buffer.Count
    $buffer.Clear()
}

$elapsed = (Get-Date) - $startTime
$rate    = [int]($totalRows / [Math]::Max($elapsed.TotalSeconds, 1))
$summary = "done: rows={0:N0} errors={1} batches={2} elapsed={3:N1}s rate={4:N0}/s" -f `
    $totalRows, $errors, $batchNum, $elapsed.TotalSeconds, $rate
Write-Host $summary
"=== walker end $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $summary ===" | Add-Content -Path $ErrorLogPath
