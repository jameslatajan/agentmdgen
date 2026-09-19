# AGENTS.md Generator

Keep one shared set of agent rules in sync across many repositories, without
destroying the project-specific notes each one already has.

If you maintain a dozen projects that each need an `AGENTS.md` (or
`CLAUDE.md`, or any shared convention file), this copies a master into all of
them — but writes it into a **managed block**, so anything a project added
around that block survives every future sync.

```markdown
<!-- agents:managed:start -->

...replaced on every sync, from your master...

<!-- agents:managed:end -->

Project-specific notes live here. The generator never touches them.
```

## Requirements

PowerShell 7 or newer (`pwsh`). Works on Windows, macOS and Linux — it is
cross-platform PowerShell, not Windows PowerShell 5.

## Quick start

```powershell
git clone <this-repo>
cd agentmd_generator

# 1. Build your project lists by scanning a directory tree
.\init.ps1 -Scan C:\path\to\your\projects

# 2. Open projects.php.json / projects.f7.json and delete anything
#    you don't want synced (scans pick up scratch dirs too)

# 3. Validate the setup
.\init.ps1 -Check

# 4. Preview, then apply
.\sync-agents.ps1 -DryRun
.\sync-agents.ps1
```

Your lists are gitignored — they contain absolute paths specific to your
machine. The committed `projects.*.example.json` files show the shape.

## Concepts

### Types

A **type** pairs a master rules file with a list of projects:

| Type | Master | List |
|---|---|---|
| `php` | `AGENTS-PHP.md` | `projects.php.json` |
| `f7` | `AGENTS-F7V5.md` | `projects.f7.json` |

**The list a project sits in decides its type.** There is no guessing at sync
time. To move a project between types, move its path between list files.

The bundled masters are the author's own rules for CodeIgniter and Framework7
projects, kept as working examples. **Replace them with yours** — the tool
does not care what they contain.

### Detection

`init.ps1 -Scan` classifies directories, first match wins:

1. `package.json` containing `framework7` → **f7**
2. `composer.json` present → **php**
3. any `*.php` in the directory root → **php**

Framework7 is checked first deliberately: an F7 project can carry stray `.php`
files and would otherwise be misread.

`sync-agents.ps1` re-runs this check only to **warn** on a mismatch:

```
WARNING: listed as f7 but looks like php: /path/to/project
```

It syncs anyway — your list wins. The warning exists because F7 projects
silently receiving PHP rules is the exact failure this design prevents.

Detection reads only the directory root. It is a project-root test, not a
recursive search, so nested apps are listed individually.

## Commands

### `init.ps1`

| Flag | Effect |
|---|---|
| `-Scan <root>` | Walk a tree and write both project lists. |
| `-Depth <n>` | How deep to walk. Default 4. |
| `-Force` | Overwrite existing lists (refuses by default). |
| `-Check` | Validate setup; changes nothing. Exits non-zero on failure. |

`-Check` verifies: PowerShell version, both masters exist and contain no stray
markers, the masters are not identical, both lists parse as JSON, listed
directories exist, no type mismatches, and `sync-agents.ps1 -SelfTest` passes.

### `sync-agents.ps1`

| Flag | Effect |
|---|---|
| `-DryRun` | Print what would happen. No writes. |
| `-SelfTest` | Run built-in assertions. Exits non-zero on failure. |
| `-Type php` / `-Type f7` | Process only that one list. |
| `-Overwrite` | Replace the whole file. **Destructive** — see below. |

Reports one action per project:

| Action | Meaning |
|---|---|
| `create` | No `AGENTS.md` existed. Writes the block. |
| `adopt` | File existed without markers. Prepends the block, **keeps existing content**. |
| `update` | Markers found. Replaces only what is between them. |
| `unchanged` | Already identical. No write. |

Re-running is idempotent.

### `fix-duplicates.ps1`

Repairs files that accumulated stacked blocks.

```powershell
.\fix-duplicates.ps1 -DryRun
.\fix-duplicates.ps1
```

Everything up to and including the **last** `managed:end` marker is treated as
generated; whatever follows is kept. If nothing follows, the file was purely
generated and is deleted so the next sync recreates it cleanly. Every touched
file is copied to `backup-<timestamp>/` first.

## Why merge instead of overwrite

Project `AGENTS.md` files are usually not interchangeable — different runtime
versions, different structure, different local conventions. A blanket copy
deletes all of it, and there may be no git history to recover from.

`-Overwrite` exists if you genuinely want a full replace. It destroys
per-project content. Preview with `-DryRun` first, and make sure your targets
are in version control.

## Markers

Two styles are recognised when locating an existing block:

```
<!-- agents:managed:start -->     HTML comment (current)
[//]: # (agents:managed:start)    link-label style (legacy)
```

Some markdown viewers render HTML comments visibly. The link-label form is
invisible everywhere, but is a reference-style link definition, which makes
some editors treat the file as read-only in rich-text mode. Pick your poison
in `common.ps1`.

Two rules that matter:

1. **Never let a marker appear inside a master file.** It propagates into every
   synced project and breaks block detection. `init.ps1 -Check` tests for this.
2. If you change the marker strings, keep the old form matching in `$StartRx`
   and `$EndRx`, or the next sync prepends a second block instead of replacing
   the first. There is a `cross-style marker` assertion covering this.

## Adding a type

1. Add your master, e.g. `AGENTS-VUE.md`.
2. Register it in `common.ps1`:
   ```powershell
   $Sources = @{ php = 'AGENTS-PHP.md';     f7 = 'AGENTS-F7V5.md';   vue = 'AGENTS-VUE.md' }
   $Lists   = @{ php = 'projects.php.json'; f7 = 'projects.f7.json'; vue = 'projects.vue.json' }
   ```
3. Add a rule to `Get-ProjectType` in `common.ps1`, most specific first.
4. Add the type to the `ValidateSet` on `-Type` in `sync-agents.ps1`.
5. Add a case to the `-SelfTest` detection block, then run `-SelfTest`.

## Files

| File | Purpose |
|---|---|
| `init.ps1` | Setup: scan for projects, validate configuration. |
| `sync-agents.ps1` | The sync. |
| `fix-duplicates.ps1` | Repair stacked blocks. |
| `common.ps1` | Shared config and detection, used by all three. |
| `AGENTS-*.md` | Master rule sets (examples — replace them). |
| `projects.*.json` | Your project lists (gitignored). |
| `projects.*.example.json` | Committed examples showing the format. |

## Safety

The generator writes to files across many repositories and creates **no
backups of its own**. Keep your projects in version control; `git diff` after
a sync is the intended review step.

`fix-duplicates.ps1` does back up everything it touches, to `backup-<timestamp>/`.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
