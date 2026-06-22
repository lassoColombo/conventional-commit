# conventional-commit (ccommit)

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) module for Nushell.

Parse a message into structured pieces, encode a record back into a message, and walk git ranges.

# Why?

Because answering questions like `which breaking changes shipped between v1.4.0 and v1.5.0?` is more difficult than it should be.

This module provides functions that parse conventional commits into predictable, structured data, according to the official specification.  
It allows you to answer those types of questions with ease and precision:
```nu
ccommit list v1.4.0 v1.5.0 | where breaking | get hash 
```

# Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) ccommit] | path join # I like to call it ccommit
git clone git@github.com:lassoColombo/conventional-commit.git $dest

# use the module
use ccommit
ccommit list --help
```

# Quick start

```nu
use ccommit

# validity check
'feat(ui): add picker' | ccommit is-conventional

# full parse
'feat(ui)!: rework picker' | ccommit decode

# encode a record back into a message (inverse of decode)
# breaking commits carry the evidence: a `!` (bang) and/or a BREAKING CHANGE footer
{type: feat, scope: api, breaking: true, bang: true, description: 'drop /v1'} | ccommit encode

# walk a git range
ccommit list HEAD~10 HEAD
```

# Spec conformance: what is `conventional` anyway?

This module adheres to [Conventional Commits v.1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).  

The spec reserves the meaning of `feat`, `fix`, and `BREAKING CHANGE` but leaves the type set open - any noun is a valid type. **By default this module does the same: any letter-only type is conventional**, so `feat: x`, `wip: x`, and `asd: x` all parse as conventional.

On top of that, you can **optionally overlay a closed set of allowed types** to enforce a team policy - set `$env.CONVENTIONAL_COMMIT_VALID_TYPES` and any type outside it is treated as non-conventional.

## Project-policy type list

By default `is-conventional` and `decode` accept any letter-only type, matching the spec. Setting `$env.CONVENTIONAL_COMMIT_VALID_TYPES` turns the type slot into a closed set: both functions build their subject regex from your list, and a commit whose type isn't in it decodes as non-conventional. The policy is a decode-side concern only — `encode` never consults it and won't error on an out-of-policy type, keeping the two directions symmetric.

In this readme we will use types defined in the [Angular convention](https://github.com/angular/angular/blob/main/CONTRIBUTING.md#type). 

`$env.CONVENTIONAL_COMMIT_VALID_TYPES` can both be a list and a comma/space-separated string:
```nu
# Nushell config - list form
$env.CONVENTIONAL_COMMIT_VALID_TYPES = [feat fix docs style refactor perf test build ci chore revert]
```
```sh
# POSIX shell / CI env - string form
export CONVENTIONAL_COMMIT_VALID_TYPES="feat,fix,chore,docs,ops"
```

# Parsed shape

`ccommit decode` always returns this record. Fields are nullable so non-conventional input is still safe to consume:

```nu
{
  type:         string | null   # lowercased type, or null when not conventional
  scope:        string | null   # text inside parens, or null
  breaking:     bool            # true when `!` is in the prefix OR a BREAKING CHANGE footer is present
  bang:         bool            # true when the `!` marker was literally in the header (≠ breaking, which also counts the footer)
  subject:      string          # the raw first line (derived; read-only - see encode note)
  description:  string | null   # text after `: ` (spec rule 5), or null
  body:         string | null   # body paragraphs joined with `\n\n`, or null
  footers:      table<token: string, sep: string, value: string>   # sep is the literal `: ` or ` #` the footer used
  conventional: bool            # true when the subject line conforms
}
```

`ccommit list` augments each row with `hash`, `author`, and `date` from `git log`. Decoration flags add more columns on demand - see [`list` decoration flags](#list-decoration-flags) below.

# Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `ccommit is-conventional` | `string -> bool` | Header-only validity check. Body and footers are ignored. |
| `ccommit decode` | `string -> record` | Full structured parse. Returns the same shape for conventional and non-conventional input. |
| `ccommit encode` | `record -> string` | Inverse of `decode`. Renders a structured record back into a Conventional Commits string. |
| `ccommit list` | `[from?: string, to: string = HEAD] -> table` | Walk `git log <from>..<to>` and parse each commit. Omit `from` to walk full history. Optional flags add decoration columns (author email, committer, merge info, GPG status, containing tag, diff stats, per-file change buckets). |


## `ccommit list` ranges

`from` is exclusive, `to` defaults to `HEAD` - matching `git log` semantics:

```nu
ccommit list                    # full history
ccommit list HEAD~10            # last 10 commits
ccommit list v1.4.0 v1.5.0      # commits between two tags
```

`from` and `to` are each resolved as a single revision

## `ccommit list` decoration flags

Each flag opts the corresponding column(s) into the output.

| Flag | Adds columns | Source | Cost |
|---|---|---|---|
| `--with-email` | `author_email: string` | `git log %ae` | free |
| `--with-committer` | `committer, committer_email, committer_date` | `git log %cn / %ce / %cI` | free |
| `--with-merge-info` | `parents: list<string>, is_merge: bool` | `git log %P` | free |
| `--with-signature` | `signature: string` (`G`/`B`/`U`/`N`/`E`) | `git log %G?` | free |
| `--with-stats` | `files_changed: int, insertions: int, deletions: int` | `git show --shortstat` per row | one extra pass |
| `--with-changes` | `added: list<string>, modified: list<string>, deleted: list<string>` | `git show --name-status` per row, bucketed by status code (renames/copies land in `modified` under their new path) | one extra pass |
| `--with-tag` | `tag: string \| null` - earliest tag containing the commit | `git tag --contains --sort=creatordate` per row | one operation per commit |

*free* = already fetched by the base `list`. *one extra pass* = a single batched `git log` over the whole range, regardless of size. *one operation per commit* = scales with the number of commits, so reach for it only on the rows you need.

## `ccommit encode` round-trip

`encode` and `decode` are inverses: whatever `decode` gives you, `encode` turns back into the original message.

```nu
'feat(ui): add picker' | ccommit decode | ccommit encode
# => 'feat(ui): add picker'
```

This is what makes the structured record safe to edit. Decode a commit, change its `scope` or `description`, encode it back, and you get a valid message.

`Decode` is able to consume unconventional commits, and will parse them into a structure with the `conventional` field set to false.  
Similarly `encode` is able to produce unconventional commits — but *only* when told to, via `conventional: false`, in which case it emits the raw `subject` verbatim. This way any round-trip is safe to perform and will preserve the original message unchanged.

On the conventional path (`conventional: true`), `encode` guarantees a conventional header: it validates the result against the spec grammar with the same recognizer `decode` uses, so components that can't form a conventional header — a type with non-letters, a scope containing `)`, a multi-line description — error rather than silently produce something `decode` would call non-conventional. The check is against the spec, not the project [type policy](#project-policy-type-list): a spec-valid-but-out-of-policy type like `wip` still encodes, keeping `encode` independent of the environment.

## Encoding

The encoding strategy used depends on the `conventional` field:
- `true`: `encode` builds the subject line from `type`, `scope`, `breaking`, and `description` alone - so those first two are required, and any `subject` left in the record is simply ignored. If configured, $env.CONVENTIONAL_COMMIT_VALID_TYPES is also validated.
- `false`: `encode` to emit the raw `subject` verbatim and no validation is performed

# CI/CD recipes

## Validate every commit in a pull request

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

## Skip CI when no commit is build-worthy

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

## Build only the components touched by a merge request

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

## Determine the next semver bump

Look at every conventional commit since the last tag, derive the bump level (`major` / `minor` / `patch`) from their types and breaking flags, then compute the actual next version with the [`semver`](https://github.com/lassoColombo/semver) module.

```nu
use ccommit
use semver

# Returns the next version string (e.g. `1.5.0`), always strictly greater
# than `last`. Returns null when no release-worthy commit has landed since
# `last` - a single sentinel regardless of whether a tag was passed.
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

## Block unsigned or bad-signature commits

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

## Generate a release changelog

Group conventional commits between two tags by type and render markdown sections. Two design choices keep the output safe and predictable:

- **Section order is driven by the spec** - not by which type happens to appear first in the data - so the output is stable release-over-release.
- **User-supplied content (description, scope) goes through an `md-escape` helper** so backticks, brackets, underscores, etc. in a description can't break the rendered markdown. The bullet is assembled via `format pattern` from pre-computed columns.

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
