param()

$ErrorActionPreference = 'Stop'
$provDir = 'C:\Users\Administrator\Documents\claude\symphony\dashboards\provisioned'

function ReadJson([string]$path) {
    [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path))
}
function WriteJson([string]$path, [string]$text) {
    [IO.File]::WriteAllBytes($path, [Text.Encoding]::UTF8.GetBytes($text))
}
function Count([string]$text, [string]$needle) {
    ([regex]::Matches($text, [regex]::Escape($needle))).Count
}

# ------------- sym-arch -------------
$f = Join-Path $provDir 'sym-arch.json'
$t = ReadJson $f

# Replace top-folder extract regex with splitByChar on 4th segment
$oldExtract = 'extract(file_path, \u0027^[^\\\\/]*[\\\\/]+[^\\\\/]*[\\\\/]+([^\\\\/]+)\u0027)'
$newExtract = 'splitByChar(\u0027/\u0027, file_path)[4]'
$c = Count $t $oldExtract
$t = $t.Replace($oldExtract, $newExtract)
Write-Host "sym-arch: replaced top-folder regex ($c occurrences)"

WriteJson $f $t

# ------------- sym-ops -------------
$f = Join-Path $provDir 'sym-ops.json'
$t = ReadJson $f

# 1. Broken-inheritance: parent_acl != '' AND acl != parent_acl  →  acl_analysis LIKE '%B%'
$oldBroken = 'parent_acl != \u0027\u0027 AND acl != parent_acl'
$newBroken = 'positionCaseInsensitive(acl_analysis, \u0027B\u0027) \u003e 0'
$c = Count $t $oldBroken
$t = $t.Replace($oldBroken, $newBroken)
Write-Host "sym-ops: fixed broken-inheritance heuristic ($c occurrences)"

WriteJson $f $t

# ------------- sym-cfo -------------
$f = Join-Path $provDir 'sym-cfo.json'
$t = ReadJson $f

# Swap modified -> last_accessed in the archive-savings calcs (keeps `modified` in size-by-age panels alone)
# Pattern: `modified \u003c now()-INTERVAL 3 YEAR` in CFO dashboards is specifically for "cold bytes" — pivot to access.
$oldCfo = 'modified \u003c now()-INTERVAL 3 YEAR'
$newCfo = 'last_accessed \u003c now()-INTERVAL 3 YEAR'
$c = Count $t $oldCfo
$t = $t.Replace($oldCfo, $newCfo)
Write-Host "sym-cfo: pivoted cold-bytes filter to last_accessed ($c occurrences)"

WriteJson $f $t

# ------------- sym-exec -------------
$f = Join-Path $provDir 'sym-exec.json'
$t = ReadJson $f

# Replace Everyone% query with W% (may widen access) — same panel, more informative metric on this data
$oldEv = 'countIf(owner_name LIKE \u0027S-1-%\u0027 OR owner_name=\u0027\u0027 OR positionCaseInsensitive(owner_name,\u0027unresolv\u0027)\u003e0)'
# Actually that's the orphan query — leave it. For Everyone, the query uses positionCaseInsensitive(acl,'Everyone')
$oldEveryone = 'positionCaseInsensitive(acl,\u0027Everyone\u0027)\u003e0'
$newW = 'positionCaseInsensitive(acl_analysis,\u0027W\u0027)\u003e0'
$c = Count $t $oldEveryone
$t = $t.Replace($oldEveryone, $newW)
Write-Host "sym-exec: swapped Everyone -> W (may widen access) filter ($c occurrences)"

WriteJson $f $t

Write-Host "Done."
