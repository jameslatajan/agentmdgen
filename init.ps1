<#
.SYNOPSIS
  First-run setup for the AGENTS.md generator.

.DESCRIPTION
  -Scan <root>   Walk a directory tree, classify each project, and write
                 projects.php.json / projects.f7.json.
  -Check         Validate the setup without changing anything.

  Run -Scan once after cloning, review the generated lists, then -Check.
#>
param(
  [string]$Scan,
  [switch]$Check,
  [int]$Depth = 4,
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'common.ps1')

$ok = $true
$needsScan = $false
function Fail($m) { Write-Host "  FAIL  $m" -ForegroundColor Red;    $script:ok = $false }
function Warn($m) { Write-Host "  WARN  $m" -ForegroundColor Yellow }
function Pass($m) { Write-Host "  ok    $m" -ForegroundColor Green }

# ---------------------------------------------------------------- scan ----
if ($Scan) {
  if (-not (Test-Path -PathType Container $Scan)) { throw "not a directory: $Scan" }
  $root = (Resolve-Path $Scan).Path
  Write-Host "scanning $root (depth $Depth)..."

  $found = @{ php = [System.Collections.Generic.List[string]]::new()
              f7  = [System.Collections.Generic.List[string]]::new() }

  # Walk breadth-first, skipping noise directories entirely.
  $queue = [System.Collections.Generic.Queue[object]]::new()
  $queue.Enqueue(@{ path = $root; depth = 0 })
  while ($queue.Count) {
    $n = $queue.Dequeue()
    $t = Get-ProjectType $n.path
    # .Replace is literal; -replace would treat a lone backslash as a regex.
    if ($t) { $found[$t].Add($n.path.Replace('\','/')) }
    if ($n.depth -ge $Depth) { continue }
    foreach ($c in Get-ChildItem $n.path -Directory -ErrorAction SilentlyContinue) {
      if ($PruneDirs -contains $c.Name) { continue }
      $queue.Enqueue(@{ path = $c.FullName; depth = $n.depth + 1 })
    }
  }

  foreach ($t in 'php','f7') {
    $out  = Join-Path $PSScriptRoot $Lists[$t]
    $list = $found[$t] | Sort-Object -Unique
    if ((Test-Path $out) -and -not $Force) {
      Warn "$($Lists[$t]) exists, not overwritten ($($list.Count) found). Re-run with -Force."
      continue
    }
    # -AsArray keeps [ ] even for zero or one entry (a scalar would serialise
    # as a bare string, and indexing it would yield a character).
    $list | ConvertTo-Json -AsArray | Set-Content -Path $out -Encoding utf8
    Pass "$($Lists[$t]): $(@($list).Count) projects"
  }

  Write-Host "`nReview the lists, remove anything you don't want synced, then:"
  Write-Host "  .\init.ps1 -Check"
  return
}

# --------------------------------------------------------------- check ----
if (-not $Check) { Get-Help $PSCommandPath -Detailed; return }

Write-Host "`nPowerShell"
if ($PSVersionTable.PSVersion.Major -ge 7) { Pass "pwsh $($PSVersionTable.PSVersion)" }
else { Fail "PowerShell 7+ required, found $($PSVersionTable.PSVersion)" }

Write-Host "`nMasters"
foreach ($t in 'php','f7') {
  $f = Join-Path $PSScriptRoot $Sources[$t]
  if (-not (Test-Path $f)) { Fail "$($Sources[$t]) missing"; continue }
  $c = Get-Content $f -Raw
  # A marker inside a master propagates into every synced project.
  if (($c -match $StartRx) -or ($c -match $EndRx)) { Fail "$($Sources[$t]) contains managed markers - remove them" }
  else { Pass "$($Sources[$t]) clean" }
}
$php = Join-Path $PSScriptRoot $Sources['php']
$f7  = Join-Path $PSScriptRoot $Sources['f7']
if ((Test-Path $php) -and (Test-Path $f7) -and
    ((Get-Content $php -Raw) -eq (Get-Content $f7 -Raw))) {
  Warn "both masters are identical - f7 projects will receive php rules"
}

Write-Host "`nProject lists"
foreach ($t in 'php','f7') {
  $f = Join-Path $PSScriptRoot $Lists[$t]
  if (-not (Test-Path $f)) { Warn "$($Lists[$t]) missing - run: .\init.ps1 -Scan <root>"; $needsScan = $true; continue }
  try { $dirs = @(Get-Content $f -Raw | ConvertFrom-Json) }
  catch { Fail "$($Lists[$t]) is not valid JSON"; continue }

  $missing  = @($dirs | Where-Object { -not (Test-Path -PathType Container $_) })
  $mismatch = @($dirs | Where-Object {
                  (Test-Path -PathType Container $_) -and
                  (($s = Get-ProjectType $_)) -and $s -ne $t })
  Pass "$($Lists[$t]): $($dirs.Count) projects"
  if ($missing.Count)  { Warn "  $($missing.Count) missing on disk, e.g. $($missing[0])" }
  if ($mismatch.Count) { Warn "  $($mismatch.Count) look like another type, e.g. $($mismatch[0])" }
}

Write-Host "`nScript"
# Write-Host output bypasses the pipeline, so trust the exit code, not the text.
& (Join-Path $PSScriptRoot 'sync-agents.ps1') -SelfTest | Out-Null
if ($LASTEXITCODE -eq 0) { Pass 'sync-agents.ps1 -SelfTest' }
else { Fail 'sync-agents.ps1 -SelfTest failed - run it directly for detail' }

Write-Host ""
if (-not $ok) {
  Write-Host "Fix the failures above before syncing." -ForegroundColor Red; exit 1
}
elseif ($needsScan) {
  # Nothing to sync yet - don't send a new user to a no-op run.
  Write-Host "Setup incomplete. Next: .\init.ps1 -Scan <path-to-your-projects>" -ForegroundColor Yellow
  exit 2
}
else {
  Write-Host "All checks passed. Next: .\sync-agents.ps1 -DryRun" -ForegroundColor Green
}
