# Shared helpers for sync-agents.ps1 and init.ps1.

# type -> master file and project list, all relative to the repo root.
$Sources = @{ php = 'AGENTS-PHP.md';     f7 = 'AGENTS-F7V5.md' }
$Lists   = @{ php = 'projects.php.json'; f7 = 'projects.f7.json' }

$StartMark = '<!-- agents:managed:start -->'
$EndMark   = '<!-- agents:managed:end -->'

# Recognises the current HTML-comment markers and the legacy link-label style,
# so changing the marker never causes a second block to be prepended.
$StartRx = '(?m)^(?:<!--\s*agents:managed:start\s*-->|\[//\]:\s*#\s*\(agents:managed:start\))'
$EndRx   = '(?m)^(?:<!--\s*agents:managed:end\s*-->|\[//\]:\s*#\s*\(agents:managed:end\))'

# Directories never worth descending into when scanning for projects.
$PruneDirs = @('node_modules','vendor','platforms','plugins','build','builds','.git','dist','tmp')

function Get-ProjectType([string]$dir) {
  # framework7 wins: an f7 project can also carry stray .php files.
  $pkg = Join-Path $dir 'package.json'
  if ((Test-Path $pkg) -and (Get-Content $pkg -Raw -ErrorAction SilentlyContinue) -match 'framework7') { return 'f7' }
  if (Test-Path (Join-Path $dir 'composer.json')) { return 'php' }
  if (Get-ChildItem $dir -Filter *.php -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return 'php' }
  return $null
}
