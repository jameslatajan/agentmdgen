# Syncs shared agent rules into each project's AGENTS.md.
#
# Default is a MERGE: the shared text lives between managed markers and is
# replaced in place; anything the project added outside the markers is kept.
# -Overwrite replaces the whole file (destructive, use -DryRun first).
#
# A project's type comes from which list file it appears in.
# -Type limits the run to one type.
param(
  [ValidateSet('php','f7')][string]$Type,
  [switch]$Overwrite,
  [switch]$DryRun,
  [switch]$SelfTest
)

. (Join-Path $PSScriptRoot 'common.ps1')

# Returns the new file content. $existing is $null when the file is absent.
function Merge-Managed([string]$existing, [string]$shared) {
  $block = "$StartMark`n`n$shared`n`n$EndMark"
  if ([string]::IsNullOrWhiteSpace($existing)) { return "$block`n" }

  # Match any historical marker style, so a changed marker never causes a
  # second block to be prepended on top of the first.
  $sm = [regex]::Match($existing, $StartRx)
  $em = [regex]::Match($existing, $EndRx)
  $s = if ($sm.Success) { $sm.Index } else { -1 }
  $e = if ($em.Success) { $em.Index } else { -1 }
  $eLen = if ($em.Success) { $em.Length } else { 0 }
  # Replace in place only when both markers are present and ordered.
  if ($s -ge 0 -and $e -gt $s) {
    return $existing.Substring(0, $s) + $block + $existing.Substring($e + $eLen)
  }
  # No markers: adopt the file by prepending the block, keeping its content.
  return "$block`n`n$existing"
}

if ($SelfTest) {
  $fail = 0
  function Check($name, $got, $want) {
    if ($got -ne $want) { Write-Host "FAIL $name`n  want: [$want]`n  got : [$got]"; $script:fail++ }
  }

  # --- Merge-Managed ---
  Check 'new file'      (Merge-Managed $null 'RULES')          "$StartMark`n`nRULES`n`n$EndMark`n"
  Check 'empty file'    (Merge-Managed '   ' 'RULES')          "$StartMark`n`nRULES`n`n$EndMark`n"
  Check 'adopt'         (Merge-Managed "custom`n" 'RULES')     "$StartMark`n`nRULES`n`n$EndMark`n`ncustom`n"
  Check 'replace' `
    (Merge-Managed "top`n$StartMark`nOLD`n$EndMark`nbottom`n" 'NEW') `
    "top`n$StartMark`n`nNEW`n`n$EndMark`nbottom`n"
  Check 'idempotent' `
    (Merge-Managed (Merge-Managed "custom`n" 'RULES') 'RULES') `
    "$StartMark`n`nRULES`n`n$EndMark`n`ncustom`n"
  # A literal $ in shared text must survive (regex/backref hazard).
  Check 'dollar-safe'   (Merge-Managed $null 'cost is $1 & $_') "$StartMark`n`ncost is `$1 & `$_`n`n$EndMark`n"
  # The bug that stacked 3 blocks: a file marked with the OLD link-label
  # style must be REPLACED, not prepended to, when markers change style.
  Check 'cross-style marker' `
    (Merge-Managed "[//]: # (agents:managed:start)`nOLD`n[//]: # (agents:managed:end)`nkeep`n" 'NEW') `
    "$StartMark`n`nNEW`n`n$EndMark`nkeep`n"
  # Malformed (end before start) must not corrupt: treated as unmarked.
  Check 'malformed' `
    (Merge-Managed "$EndMark`nx`n$StartMark`n" 'R') `
    "$StartMark`n`nR`n`n$EndMark`n`n$EndMark`nx`n$StartMark`n"

  # --- Get-ProjectType ---
  $t = Join-Path ([IO.Path]::GetTempPath()) "sync-agents-test-$PID"
  try {
    foreach ($c in @(
      @{ n='f7';       f=@{ 'package.json'  = '{"dependencies":{"framework7":"^8"}}' }; want='f7'  },
      @{ n='f7-mixed'; f=@{ 'package.json'  = '{"dependencies":{"framework7":"^8"}}'; 'x.php' = '' }; want='f7' },
      @{ n='composer'; f=@{ 'composer.json' = '{}' };                                  want='php' },
      @{ n='bare-php'; f=@{ 'index.php'     = '' };                                    want='php' },
      @{ n='node';     f=@{ 'package.json'  = '{"dependencies":{"vue":"^3"}}' };        want=$null },
      @{ n='empty';    f=@{};                                                          want=$null }
    )) {
      $d = Join-Path $t $c.n
      New-Item -ItemType Directory -Force $d | Out-Null
      $c.f.GetEnumerator() | ForEach-Object { Set-Content (Join-Path $d $_.Key) $_.Value }
      Check "type/$($c.n)" (Get-ProjectType $d) $c.want
    }
  } finally { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }

  if ($fail) { Write-Host "selftest FAILED ($fail)"; exit 1 }
  Write-Host 'selftest ok'
  exit 0   # explicit, so callers can trust $LASTEXITCODE
}

$types = if ($Type) { @($Type) } else { $Lists.Keys | Sort-Object }

foreach ($t in $types) {
 $listPath = Join-Path $PSScriptRoot $Lists[$t]
 if (-not (Test-Path $listPath)) { Write-Warning "no $($Lists[$t]), skipping all $t projects"; continue }

 foreach ($dir in (Get-Content $listPath -Raw | ConvertFrom-Json)) {
  if (-not (Test-Path -PathType Container $dir)) { Write-Warning "missing: $dir"; continue }

  # The list is authoritative, but warn when the directory looks like another
  # type - that is how f7 projects end up with PHP rules.
  $sniffed = Get-ProjectType $dir
  if ($sniffed -and $sniffed -ne $t) {
    Write-Warning "listed as $t but looks like $sniffed`: $dir"
  }

  $source = Join-Path $PSScriptRoot $Sources[$t]
  if (-not (Test-Path $source)) { Write-Warning "no $($Sources[$t]), skipped: $dir"; continue }

  $dest     = Join-Path $dir 'AGENTS.md'
  $existing = if (Test-Path $dest) { Get-Content $dest -Raw } else { $null }

  if ($Overwrite) {
    $new = Get-Content $source -Raw
    $how = 'overwrite'
  } else {
    $new = Merge-Managed $existing (Get-Content $source -Raw).TrimEnd()
    # Match either marker style, so the reported action matches what Merge-Managed does.
    $hasMark = $existing -match $StartRx
    $how = if ($null -eq $existing) { 'create' }
           elseif ($hasMark) { 'update' }
           else { 'adopt' }
  }

  if ($new -eq $existing) { Write-Host "[$t] unchanged $dest"; continue }
  if ($DryRun) { Write-Host "[$t] would $how $dest"; continue }

  Set-Content -Path $dest -Value $new -NoNewline -Encoding utf8
  Write-Host "[$t] $how $dest"
 }
}
