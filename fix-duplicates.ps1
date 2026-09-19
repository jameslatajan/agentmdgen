# Repairs AGENTS.md files that accumulated stacked managed blocks.
# Rule: everything up to and including the LAST managed:end marker is
# generated junk; the original project content is whatever follows it.
# Backs up every file it touches. -DryRun previews.
param([switch]$DryRun)

$BackupRoot = Join-Path $PSScriptRoot ("backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
# Matches both marker styles that have been used.
$EndRx = '(?m)^(?:<!--\s*agents:managed:end\s*-->|\[//\]:\s*#\s*\(agents:managed:end\))\s*$'

foreach ($dir in (Get-Content "$PSScriptRoot/projects.json" -Raw | ConvertFrom-Json)) {
  $f = Join-Path $dir 'AGENTS.md'
  if (-not (Test-Path $f)) { continue }

  $text = Get-Content $f -Raw
  $m = [regex]::Matches($text, $EndRx)
  if ($m.Count -eq 0) { continue }

  $last  = $m[$m.Count - 1]
  $tail  = $text.Substring($last.Index + $last.Length).TrimStart("`r","`n")
  $before = ($text -split "`n").Count
  $after  = ($tail -split "`n").Count

  # No tail = the file is nothing but stacked generated blocks (an old
  # "create" target). Delete it; the next sync writes one clean block.
  $purelyGenerated = [string]::IsNullOrWhiteSpace($tail)
  if ($purelyGenerated) {
    '{0,-4} blocks  {1,6} -> DELETE (regenerate on next sync)  {2}' -f $m.Count, $before, $f
  } else {
    '{0,-4} blocks  {1,6} -> {2,-6} {3}' -f $m.Count, $before, $after, $f
  }
  if ($DryRun) { continue }

  if (-not (Test-Path $BackupRoot)) { New-Item -ItemType Directory -Force $BackupRoot | Out-Null }
  $safe = ($dir -replace '^[A-Za-z]:[\/]', '' -replace '[\/]', '_') + '_AGENTS.md'
  Copy-Item $f (Join-Path $BackupRoot $safe) -Force
  if ($purelyGenerated) { Remove-Item $f -Force }
  else { Set-Content -Path $f -Value $tail -NoNewline -Encoding utf8 }
}
if (-not $DryRun -and (Test-Path $BackupRoot)) { Write-Host "`nbackups: $BackupRoot" }
