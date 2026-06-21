# conventional-commit

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) module for Nushell.

Parse a message into structured pieces, encode a record back into a message, and walk git ranges.

1. [conventional-commit](#conventional-commit)
   1. [Why?](#why?)
   2. [Installation](#installation)
   3. [Quick start](#quick-start)
   4. [Parsed shape](#parsed-shape)
   5. [Commands](#commands)
      1. [`ccommit encode` round-trip](#`ccommit-encode`-round-trip)
      2. [`ccommit list` ranges](#`ccommit-list`-ranges)
      3. [`list` decoration flags](#`list`-decoration-flags)
         1. [Performance](#performance)
   6. [Spec conformance](#spec-conformance)
      1. [Project-policy type list](#project-policy-type-list)
   7. [CI/CD recipes](#ci/cd-recipes)
      1. [Validate every commit in a pull request](#validate-every-commit-in-a-pull-request)
      2. [Skip CI when no commit is build-worthy](#skip-ci-when-no-commit-is-build-worthy)
      3. [Build only the components touched by a merge request](#build-only-the-components-touched-by-a-merge-request)
      4. [Determine the next semver bump](#determine-the-next-semver-bump)
      5. [Block unsigned or bad-signature commits](#block-unsigned-or-bad-signature-commits)
      6. [Generate a release changelog](#generate-a-release-changelog)

## Why?

Because answering questions like `which breaking changes shipped between v1.4.0 and v1.5.0?` is more difficult than it should be.

This module provides functions that parse conventional commits into predictable, structured data, according to the official specification.  
It allows you to answer those types of questions with ease, and precision:
```nu
ccommit list v1.4.0 v1.5.0 | where breaking | get hash 
```

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) ccommit] | path join
git clone git@github.com:lassoColombo/conventional-commit.git $dest

# use the module
use ccommit
ccommit list --help
```

## Quick start

```nu
use ccommit

# validity check
'feat(ui): add picker' | ccommit is-conventional

# full parse
'feat(ui)!: rework picker' | ccommit decode

# encode a record back into a message (inverse of decode)
{type: feat, scope: api, breaking: true, description: 'drop /v1'} | ccommit encode

# walk a git range
ccommit list HEAD~10 HEAD
```

## Parsed shape

`ccommit decode` always returns this record. Fields are nullable so non-conventional input is still safe to consume:

```nu
{
  type:         string | null   # lowercased type, or null when not conventional
  scope:        string | null   # text inside parens, or null
  breaking:     bool            # true when `!` is in the prefix OR a BREAKING CHANGE footer is present
  subject:      string          # the raw first line
  description:  string | null   # text after `: ` (spec rule 5), or null
  body:         string | null   # body paragraphs joined with `\n\n`, or null
  footers:      table<token: string, value: string>
  conventional: bool            # true when the subject line conforms
}
```

`ccommit list` augments each row with `hash`, `author`, and `date` from `git log`. Decoration flags add more columns on demand - see [`list` decoration flags](#list-decoration-flags) below.

## Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `ccommit is-conventional` | `string -> bool` | Header-only validity check. Body and footers are ignored. |
| `ccommit decode` | `string -> record` | Full structured parse. Returns the same shape for conventional and non-conventional input. |
| `ccommit encode` | `record -> string` | Inverse of `decode`. Renders a structured record back into a Conventional Commits string. |
| `ccommit list` | `[from?: string, to: string = HEAD] -> table` | Walk `git log <from>..<to>` and parse each commit. Omit `from` to walk full history. Optional flags add decoration columns (author email, committer, merge info, GPG status, containing tag, diff stats, per-file change buckets). |

### `ccommit encode` round-trip

`encode` is the inverse of `decode` for canonical inputs:

```nu
'feat(ui): add picker' | ccommit decode | ccommit encode
# => 'feat(ui): add picker'
```

Notes on the canonical minimal form:

- When `type` is null/missing, the raw `subject` field is emitted verbatim - so non-conventional decodes still round-trip.
- When `breaking: true` AND a `BREAKING CHANGE` / `BREAKING-CHANGE` footer is present, the `!` marker is suppressed (the footer alone is sufficient per rules 11, 16). This means `feat!: x\n\nBREAKING CHANGE: y` collapses to `feat: x\n\nBREAKING CHANGE: y` on a decode → encode round-trip.
- Footers are always emitted with the `: ` separator; the alternate ` #` separator is not preserved.

### `ccommit list` ranges

`from` is exclusive, `to` defaults to `HEAD` - matching `git log` semantics:

```nu
ccommit list                    # full history
ccommit list HEAD~10            # last 10 commits
ccommit list v1.4.0 v1.5.0      # commits between two tags
ccommit list main..feature/x    # also works - pass any single revspec as `from`
```

### `list` decoration flags

Each flag opts the corresponding column(s) into the output. Default `list` is unchanged - these are pure additions.

| Flag | Adds columns | Source |
|---|---|---|
| `--with-email` | `author_email: string` | `git log %ae` |
| `--with-committer` | `committer, committer_email, committer_date` | `git log %cn / %ce / %cI` |
| `--with-merge-info` | `parents: list<string>, is_merge: bool` | `git log %P` |
| `--with-signature` | `signature: string` (`G`/`B`/`U`/`N`/`E`) | `git log %G?` |
| `--with-tag` | `tag: string \| null` - earliest tag containing the commit | `git tag --contains --sort=creatordate` per row |
| `--with-stats` | `files_changed: int, insertions: int, deletions: int` | `git show --shortstat` per row |
| `--with-changes` | `added: list<string>, modified: list<string>, deleted: list<string>` | `git show --name-status` per row, bucketed by status code (renames/copies land in `modified` under their new path) |


#### Performance

The flags fall into three cost tiers:

- **Free** - `--with-email`, `--with-committer`, `--with-merge-info`, `--with-signature`. The base `list` already fetches every one of these fields in its single `git log` call (`%ae`, `%cn`/`%ce`/`%cI`, `%P`, `%G?`). The flag only decides whether the column is kept; toggling it adds **no extra work**. Default `list` simply rejects these columns at the end.
- **One extra `git log` pass** - `--with-stats` and `--with-changes`. Both derive their data from each commit's diff, so they each run a *single* batched `git log` over the whole range (`--shortstat` / `--name-status`) and join the result onto the rows by hash. Cost is one extra subprocess regardless of how many commits are in the range — it does not scale with N.
- **One git process per commit** - `--with-tag` (`git tag --contains`). The earliest tag containing a commit can't be derived from a single log pass, so this spawns a subprocess **for every row in the range**, parallelised with `par-each`. This is the only flag whose process count scales linearly with the number of commits.

So a 1000-commit range with no flags - or with only the free ones - is one `git log`; with `--with-stats --with-changes` it's three `git log` passes total; only `--with-tag` adds a process per commit. Reach for `--with-tag` on the rows you actually need (filter the range, or `where`/`first` before deciding).

## Spec conformance

This module adheres to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The spec reserves the meaning of `feat`, `fix`, and `BREAKING CHANGE` but leaves the type set open - any noun is a valid type (rule 14). **By default this module does the same: any letter-only type is conventional**, so `feat: x`, `wip: x`, and `hotfix: x` all parse as conventional.

On top of that, you can **optionally overlay a closed set of allowed types** to enforce a team policy - set `$env.CONVENTIONAL_COMMIT_VALID_TYPES` and any type outside it is treated as non-conventional.

### Project-policy type list

By default `is-conventional` and `decode` accept any letter-only type, matching the spec. Setting `$env.CONVENTIONAL_COMMIT_VALID_TYPES` turns the type slot into a closed set: both functions build their subject regex from your list, and a commit whose type isn't in it parses as non-conventional. This is a policy overlay, opt-in per project - unset means unrestricted.

A common choice is the [Angular convention](https://github.com/angular/angular/blob/main/CONTRIBUTING.md#type). Both a list and a comma/space-separated string are accepted (env vars set from POSIX shells are always strings):

```nu
# Nushell config - list form
$env.CONVENTIONAL_COMMIT_VALID_TYPES = [feat fix docs style refactor perf test build ci chore revert]
```

```sh
# POSIX shell / CI env - string form
export CONVENTIONAL_COMMIT_VALID_TYPES="feat,fix,chore,docs,ops"
```

With `feat,fix,chore,docs,ops` configured, `feat: x` and `ops(infra): y` are conventional; `refactor: z` is not. Matching stays case-insensitive (spec rule 15) - `FEAT: x` still decodes to `type: feat`.

## CI/CD recipes

### Validate every commit in a pull request

Fail the pipeline if any commit on the PR branch isn't conventional. The offenders' hashes and subjects are printed before exit so the author can fix them up:

```nu
def assert-conventional [base: string = 'origin/main'] {
    let offenders = ccommit list $base HEAD | where not conventional
    if ($offenders | is-empty) { return }
    print $'(ansi red)Non-conventional commits:(ansi reset)'
    $offenders | select hash author subject | each {$in | table -e} | str join "\n\n" | print
    error make --unspanned $"($offenders | length) commit(s) need a conventional header"
}
```

To also enforce a closed type set, set `$env.CONVENTIONAL_COMMIT_VALID_TYPES` for the run - out-of-policy types then fail the `conventional` check above, so `assert-conventional` already covers them.

### Skip CI when no commit is build-worthy

Short-circuit the pipeline when the branch only carries `docs` / `chore` / `style` noise.

```nu
# Set once in your CI env (or Nushell config):
#   $env.CONVENTIONAL_COMMIT_BUILDABLE_TYPES = [feat fix perf refactor]
let buildable = [feat fix perf refactor]
let signal = ccommit list origin/main HEAD | where conventional and ($it.type in $buildable)

if ($signal | is-empty) {
    print $'(ansi green)no build-worthy commits - skipping pipeline(ansi reset)'
    return
}
```

### Build only the components touched by a merge request

In a monorepo where each top-level directory is an independent component, derive the touched set from the MR's commits, intersect with the components that actually exist on disk, then build only those. The filesystem lookup keeps stale paths (deleted dirs, repo-meta dirs) out:

```nu
# Top-level dirs that aren't meta/hidden (`_cicfg`, `.github`, …).
def components [root: path = .]: nothing -> list<string> {
    ls --short-names $root | where type == dir and (not ($it.name =~ '^[_.]')) | get name | sort
}

def touched-components [base: string = 'origin/main', root: path = .]: nothing -> list<string> {
    let known = components $root
    ccommit list $base HEAD --with-changes
    | each {|r| [...$r.added ...$r.modified ...$r.deleted]}
    | flatten | uniq
    | each { path split | first }
    | where $it in $known
    | uniq | sort
}

for c in (touched-components) {
    print $"building ($c)…"
    ^make -C $c build test
}
```

### Determine the next semver bump

Look at every conventional commit since the last tag, derive the bump level (`major` / `minor` / `patch`) from their types and breaking flags, then compute the actual next version with the [`semver`](https://github.com/lassoColombo/semver) module.

```nu
use ccommit
use semver

# Returns the next version string (e.g. `1.5.0`), always strictly greater
# than `last`. Returns null when no release-worthy commit has landed since
# `last` — a single sentinel regardless of whether a tag was passed.
def next-version [
last?: string # e.g. 1.97.45
]: nothing -> any {   
    let current = $last | default '0.0.0'
    let commits = (
        if ($last | is-empty) { ccommit list } else { ccommit list $last HEAD }
    ) | where conventional

    if ($commits | any {$in.breaking}) {
        $current | semver decode | semver bump major
    } else if ($commits | any {$in.type == 'feat'}) {
        $current | semver decode | semver bump minor
    } else if ($commits | any {$in.type in [fix perf refactor]}) {
        $current | semver decode | semver bump patch
    } else {
        return null   # no release-worthy change
    }
    | semver encode
}
```

### Block unsigned or bad-signature commits

For protected branches that mandate signed commits - `G`=good, `U`=good but unknown signer (acceptable in most policies):

```nu
def assert-signed [base: string = 'origin/main'] {
    let unsigned = ccommit list $base HEAD --with-signature
    | where signature not-in ['G' 'U']

    if ($unsigned | is-empty) { return }
    $unsigned | select hash author signature subject | print
    error make --unspanned {msg: $"($unsigned | length) unsigned commit(s)"}
}
```

### Generate a release changelog

Group conventional commits between two tags by type and render markdown sections. Two design choices keep the output safe and predictable:

- **Section order is driven by the spec** - not by which type happens to appear first in the data - so the output is stable release-over-release.
- **User-supplied content (description, scope) goes through an `md-escape` helper** so backticks, brackets, underscores, etc. in a description can't break the rendered markdown. The bullet is assembled via `format pattern` from pre-computed columns rather than inline string building per row.

```nu
# Escape characters that would otherwise break markdown rendering inside
# a commit description: backslash, backtick, *, _, [], <, >.
def md-escape []: string -> string {
    $in | str replace --all --regex r#'([\\*_\[\]`<>])'# r#'\${1}'#
}

def changelog [from: string, to: string = HEAD]: nothing -> string {
    let sections = [
        [type,     title];
        [feat,     '✨ Features']
        [fix,      '🐛 Bug Fixes']
        [perf,     '⚡ Performance']
        [refactor, '♻️ Refactoring']
    ]
    let commits = ccommit list $from $to
        | where conventional
        | insert short       {|c| $c.hash | str substring ..7}
        | update description {|c| $c.description | md-escape}
        | insert scope_part  {|c| if ($c.scope | is-empty) { '' } else { $"\(($c.scope | md-escape)\) "}}
        | insert bang        {|c| if $c.breaking { ' **BREAKING**' } else { '' }}

    $sections | each {|s|
        let rows = $commits | where type == $s.type
        if ($rows | is-empty) { return null }
        let bullets = $rows | format pattern '- {scope_part}{description}{bang} - `{short}`'
        $"## ($s.title)\n" + ($bullets | str join "\n")
    } | compact | str join "\n\n"
}

changelog v1.4.0 v1.5.0 | save -f CHANGELOG-v1.5.0.md
```
