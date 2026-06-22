# conventional-commit (ccommit)

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) module for Nushell.

Parse a message into structured pieces, encode a record back into a message, walk git ranges.

### Table of contents
1. [conventional-commit (ccommit)](#conventional-commit-(ccommit))
2. [Why?](#why?)
3. [Installation](#installation)
   1. [Dependencies](#dependencies)
4. [Quick start](#quick-start)
5. [Spec conformance - what is conventional anyway](#spec-conformance---what-is-conventional-anyway)
   1. [Project-policy type list](#project-policy-type-list)
6. [Commands](#commands)
   1. [`ccommit decode`](#`ccommit-decode`)
   2. [`ccommit encode`](#`ccommit-encode`)
      1. [Encoding strategies](#encoding-strategies)
   3. [`ccommit list`](#`ccommit-list`)
      1. [`ccommit list` decoration flags](#`ccommit-list`-decoration-flags)
7. [CI/CD recipes](#ci/cd-recipes)
   1. [Validate every commit in a pull request](#validate-every-commit-in-a-pull-request)
   2. [Skip CI when no commit is build-worthy](#skip-ci-when-no-commit-is-build-worthy)
   3. [Build only the components touched by a merge request](#build-only-the-components-touched-by-a-merge-request)
   4. [Determine the next semver bump](#determine-the-next-semver-bump)
   5. [Block unsigned or bad-signature commits](#block-unsigned-or-bad-signature-commits)
   6. [Generate a release changelog](#generate-a-release-changelog)

# Why?

Because answering questions like these is more difficult than it should be:
- `which breaking changes shipped between v1.4.0 and v1.5.0?` 
- `is there any commit woth of building in this merge request?` 
- `what components in this monorepo were reverted yesterday?` 

This module provides functions that parse conventional commits into predictable, structured data, according to the official specification, and allows you to answer those types of questions with ease and precision:
```nu
# which files were deleted by breaking changes shipped between v1.4.0 and v1.5.0?
ccommit list --with-changes v1.4.0 v1.5.0 
| where {$in.breaking and ($in.deleted | is-not-empty)} 
| select hash author date deleted
```

Most of those questions get asked *inside a CI/CD pipeline*, and nushell is the right tool to answer: it has the ease of use of a shell, but also the precision of any general-purpose programming language. See the [CI/CD recipes](#cicd-recipes) for ready-to-adapt examples of use.

# Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) ccommit] | path join # I like to call it ccommit
git clone git@github.com:lassoColombo/conventional-commit.git $dest

# use the module
use ccommit
ccommit list --help
```

## Dependencies

- `git` is used in the commands that inspect the state of the repository (`ccommit list`)

# Quick start

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

# Spec conformance - what is conventional anyway

This module adheres to [Conventional Commits v.1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).  

The spec reserves the meaning of `feat`, `fix`, and `BREAKING CHANGE` but leaves the type set open - any noun is a valid type. **By default this module does the same: any letter-only type is conventional**, so `feat: x`, `wip: x`, and `asd: x` all parse as conventional.

On top of that, you can **optionally overlay a closed set of allowed types** to enforce a team policy - set `$env.CONVENTIONAL_COMMIT_VALID_TYPES` and any type outside it is treated as non-conventional.

## Project-policy type list

By default `is-conventional` and `decode` accept any letter-only type, matching the spec. Setting `$env.CONVENTIONAL_COMMIT_VALID_TYPES` turns the type slot into a closed set, and that one definition governs **both** directions: `decode` parses a commit whose type isn't in the set as non-conventional, and `encode` refuses to build a `conventional: true` header with such a type (set `conventional: false` to emit it as a raw subject instead).

`$env.CONVENTIONAL_COMMIT_VALID_TYPES` can both be a list and a comma/space-separated string:
```nu
# Nushell config - list form
$env.CONVENTIONAL_COMMIT_VALID_TYPES = [feat fix docs style refactor perf test build ci chore revert]
```
```sh
# POSIX shell / CI env - string form
export CONVENTIONAL_COMMIT_VALID_TYPES="feat,fix,chore,docs,ops"
```

In this readme we will use types defined in the [Angular convention](https://github.com/angular/angular/blob/main/CONTRIBUTING.md#type). 

# Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `ccommit is-conventional` | `string -> bool` | Header-only validity check. Body and footers are ignored. |
| `ccommit decode` | `string -> record` | Full structured parse. Returns the same shape for conventional and non-conventional input. |
| `ccommit encode` | `record -> string` | Inverse of `decode`. Renders a structured record back into a Conventional Commits string. |
| `ccommit list` | `[from?: string, to: string = HEAD] -> table` | Walk `git log <from>..<to>` and parse each commit. Omit `from` to walk full history. Optional flags add decoration columns (author email, committer, merge info, GPG status, containing tag, diff stats, per-file change buckets). |


## `ccommit decode`

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

## `ccommit encode`

`encode` and `decode` are inverses: whatever `decode` gives you, `encode` turns back into the original message.

```nu
'feat(ui): add picker' | ccommit decode | ccommit encode
# => 'feat(ui): add picker'
```

This is what makes the structured record safe to edit. Decode a commit, change its `scope` or `description`, encode it back, and you get a valid message.

`Decode` is able to consume unconventional commits, and will parse them into a structure with the `conventional` field set to false.  
Similarly `encode` is able to produce unconventional commits - but *only* when told to, via `conventional: false`.  
This way any round-trip is safe to perform and will preserve the original message unchanged.

### Encoding strategies

The encoding strategy depends on the `conventional` field:

- **`true`** - the subject is built from `type`, `scope`, `breaking`, and `description` alone; `type` and `description` are required, and any `subject` left in the record is ignored. `breaking: true` adds the `!` marker unless a BREAKING CHANGE footer already carries the change. The built header is then validated with the *same* recognizer `decode` uses - the [type policy](#project-policy-type-list) included - so `encode` can never mint a `conventional: true` header that `decode` would read back as non-conventional.
- **`false`** - `encode` emits the raw `subject` verbatim, no validation. This is the only way to produce a non-conventional commit, and what lets a non-conventional `decode` round-trip.


## `ccommit list`

`ccommit list` augments each row with `hash`, `author`, and `date` from `git log`.  
You can use decoration flags add more columns on demand (see below).

`from` is exclusive, `to` defaults to `HEAD` - matching `git log` semantics:

```nu
ccommit list                    # full history
ccommit list HEAD~10            # last 10 commits
ccommit list v1.4.0 v1.5.0      # commits between two tags
```

`from` and `to` are each resolved as a single revision

### `ccommit list` decoration flags

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

*free* = already fetched by the base `list`. *one extra pass* = a single batched `git log` over the whole range, regardless of size. *one operation per commit* = scales with the number of commits.

# CI/CD recipes

These are copy-paste starting points, not built-ins. Each is a small function that takes the commit range as explicit `from` / `to` arguments, because *how* you obtain the base and head refs is specific to your CI - there is no single right default:

- **GitHub Actions** - base `origin/${{ github.base_ref }}` (or `origin/main`), head `HEAD`.
- **GitLab CI** - base `$CI_MERGE_REQUEST_DIFF_BASE_SHA`, head `$CI_COMMIT_SHA`.
- **Local / pre-push hook** - base `@{upstream}` or the last tag, head `HEAD`.

So the recipes stay agnostic: you pass the refs in, they do the parsing. `to` defaults to `HEAD` for convenience but is always overridable.

## Validate every commit in a pull request

Fail the pipeline if any commit in the range isn't conventional. The offenders' hashes and subjects are printed before exit so the author can fix them up:

```nu
def assert-conventional [from: string, to: string = HEAD] {
    let offenders = ccommit list $from $to | where not conventional
    if ($offenders | is-empty) { return }
    print $'(ansi red)Non-conventional commits:(ansi reset)'
    $offenders | select hash author subject | each {$in | table -e} | str join "\n\n" | print
    error make --unspanned {msg: $"($offenders | length) commit\(s) need a conventional header"}
}

# e.g. GitHub Actions:  assert-conventional origin/main HEAD
```

To also enforce a closed type set, set `$env.CONVENTIONAL_COMMIT_VALID_TYPES` for the run - out-of-policy types then fail the `conventional` check above, so `assert-conventional` already covers them.

## Skip CI when no commit is build-worthy

Short-circuit the pipeline when the range only carries `docs` / `chore` / `style` noise. `build-worthy` returns the commits whose type is worth building; an empty result means skip.

```nu
def build-worthy [
    from: string
    to: string = HEAD
    types: list<string> = [feat fix perf refactor]
]: nothing -> table {
    ccommit list $from $to | where {|c| $c.conventional and ($c.type in $types)}
}

if (build-worthy origin/main HEAD | is-empty) {
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

def touched-components [from: string, to: string = HEAD, root: path = .]: nothing -> list<string> {
    let known = components $root
    ccommit list $from $to --with-changes
    | each {|r| [...$r.added ...$r.modified ...$r.deleted]}
    | flatten | uniq
    | each { path split | first }
    | where $it in $known
    | uniq | sort
}

for c in (touched-components origin/main HEAD) {
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
    last?: string         # previous version/tag, e.g. 1.97.45; omit to scan full history
    to: string = HEAD     # tip of the range to consider
]: nothing -> any {
    let current = $last | default '0.0.0'
    let commits = (
        if ($last | is-empty) { ccommit list } else { ccommit list $last $to }
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
def assert-signed [from: string, to: string = HEAD] {
    let unsigned = ccommit list $from $to --with-signature
    | where signature not-in ['G' 'U']

    if ($unsigned | is-empty) { return }
    $unsigned | select hash author signature subject | print
    error make --unspanned {msg: $"($unsigned | length) unsigned commit\(s)"}
}

# e.g.  assert-signed origin/main HEAD
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
        | insert marker      {|c| if $c.breaking { ' **BREAKING**' } else { '' }}

    $sections | each {|s|
        let rows = $commits | where type == $s.type
        if ($rows | is-empty) { return null }
        let bullets = $rows | format pattern '- {scope_part}{description}{marker} - `{short}`'
        $"## ($s.title)\n" + ($bullets | str join "\n")
    } | compact | str join "\n\n"
}

changelog v1.4.0 v1.5.0 | save -f CHANGELOG-v1.5.0.md
```
