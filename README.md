# conventional-commits (ccommit)

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) module for Nushell.

Parse a message into structured pieces, encode a record back into a message, walk git ranges.

---

- [conventional-commits (ccommit)](#conventional-commits-(ccommit))
  - [Why?](#why?)
  - [Installation](#installation)
    - [Dependencies](#dependencies)
  - [Quick start](#quick-start)
  - [Spec conformance - what is conventional anyway?](#spec-conformance---what-is-conventional-anyway?)
    - [Project-policy type list](#project-policy-type-list)
    - [One definition, both directions](#one-definition,-both-directions)
  - [Commands](#commands)
    - [`ccommit decode`](#`ccommit-decode`)
    - [`ccommit encode`](#`ccommit-encode`)
    - [`ccommit is-conventional`](#`ccommit-is-conventional`)
    - [`ccommit list`](#`ccommit-list`)
  - [CI/CD recipes](#ci/cd-recipes)
    - [Validate every commit in a pull request](#validate-every-commit-in-a-pull-request)
    - [Skip CI when no commit is build-worthy](#skip-ci-when-no-commit-is-build-worthy)
    - [Build only the components touched by a merge request](#build-only-the-components-touched-by-a-merge-request)
    - [Determine the next semver bump](#determine-the-next-semver-bump)
    - [Generate a release changelog](#generate-a-release-changelog)
  - [Mentions](#mentions)

## Why?

Because answering questions like these is more difficult than it should be:
- `which breaking change shipped between v1.4.0 and v1.5.0?` 
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

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) ccommit] | path join # I like to call it ccommit
git clone git@github.com:lassoColombo/conventional-commits.git $dest

# use the module
use ccommit
ccommit list --help
```

### Dependencies

- `git` is used in the commands that inspect the state of the repository (`ccommit list`)

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

## Spec conformance - what is conventional anyway?

This module adheres to [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).  

The spec reserves the meaning of `feat`, `fix`, and `BREAKING CHANGE` but leaves the type set open - any noun is a valid type.  

**By default this module does the same: any letter-only type is conventional**, so `feat: x`, `wip: x`, and `asd: x` all parse as conventional.  

You can optionally overlay a closed set to enforce a team policy (see [Project-policy type list](#project-policy-type-list)).

### Project-policy type list

By default `is-conventional` and `decode` accept any letter-only type, matching the spec. Setting `$env.CONVENTIONAL_COMMIT_VALID_TYPES` turns the type slot into a closed set, and that one definition governs **both** directions: `decode` parses a commit whose type isn't in the set as non-conventional, and `encode` refuses to build a `conventional: true` header with such a type (use `conventional: false` to emit it as a raw subject).

`$env.CONVENTIONAL_COMMIT_VALID_TYPES` can be a list or a comma/space-separated string:
```nu
# Nushell config - list form
$env.CONVENTIONAL_COMMIT_VALID_TYPES = [feat fix docs style refactor perf test build ci chore revert]
```
```sh
# POSIX shell / CI-friendly - string form
export CONVENTIONAL_COMMIT_VALID_TYPES="feat,fix,chore,docs,ops"
```

### One definition, both directions

The `decode` and `encode` commands are exact inverses: whatever `decode` produces, `encode` turns back into the original message - and that holds for non-conventional commits too, so every round-trip is lossless.

```nu
'feat(ui): add picker' | ccommit decode | ccommit encode  # => 'feat(ui): add picker'
```

- `decode` parses anything; unconventional input comes back with `conventional: false`.
- `encode` chooses its path from that `conventional` field. 
    - **non-conventional**: emits the raw `subject`, without validation.
    - **conventional** (default): builds the subject from `type`, `scope`, `breaking`, and `description`, then validates it with the *same* recognizer `decode` uses - the active type policy included - so components that can't form a conventional header are rejected rather than emitted. 

`conventional: false` the only way to produce a non-conventional commit, and what lets a non-conventional `decode` round-trip unchanged:

```nu
# decoding a conventional commit
'fix(collector): retry on error' | ccommit decode
# ╭──────────────┬────────────────────────────────╮
# │ type         │ fix                            │
# │ scope        │ collector                      │
# │ breaking     │ false                          │
# │ bang         │ false                          │
# │ subject      │ fix(collector): retry on error │
# │ description  │ retry on error                 │
# │ body         │                                │
# │ footers      │ [list 0 items]                 │
# │ conventional │ true                           │
# ╰──────────────┴────────────────────────────────╯

# decoding an unconventional commit
'retry on error' | ccommit decode
# ╭──────────────┬────────────────╮
# │ type         │                │
# │ scope        │                │
# │ breaking     │ false          │
# │ bang         │ false          │
# │ subject      │ retry on error │
# │ description  │                │
# │ body         │                │
# │ footers      │ [list 0 items] │
# │ conventional │ false          │
# ╰──────────────┴────────────────╯

# encoding a conventional commit
{type: fix, scope: collector, description: "retry on error"} | ccommit encode
# => fix(collector): retry on error

# encoding a non conventional commit
{subject: "retry on error", conventional: false} | ccommit encode
# => retry on error
```

## Commands

| Command                                               | Signature          | Description                                                                |
| ----------------------------------------------------- | ------------------ | -------------------------------------------------------------------------- |
| [`ccommit decode`](#ccommit-decode)                   | `string -> record` | Decode the piped commit message into its structured parts.                 |
| [`ccommit encode`](#ccommit-encode)                   | `record -> string` | Encode a structured commit record back into a Conventional Commits string. |
| [`ccommit is-conventional`](#ccommit-is-conventional) | `string -> bool`   | Check whether the piped message has a conformant subject line.             |
| [`ccommit list`](#ccommit-list)                       | `nothing -> table` | List commits in a git range with each message fully decoded.               |

### `ccommit decode`

Decode the piped commit message into its structured parts.

Always returns a record with the same shape, so non-conventional input is still safe to consume:  
- `type`: lowercased type, or null when not conventional  
- `scope`: text inside parens, or null  
- `breaking`: true when `!` is in the prefix OR a BREAKING CHANGE/BREAKING-CHANGE footer is present  
- `bang`: true when the `!` marker was literally in the header. Distinct from `breaking`, which also counts the footer.  
- `subject`: the raw first line of the message  
- `description`: text after `: ` (spec rule 5), or null otherwise  
- `body`: body paragraphs joined with `\n\n`, or null  
- `footers`: `table<token: string, sep: string, value: string>`;  
`sep` is the literal `': '` or `' #'` the footer used  
- `conventional`: true when the subject line conforms

**Signature:** `string -> record` · **Category:** `conventional-commits`

**Search terms:** `parse`, `split`, `decompose`, `conventional`

**Examples**

```nu
# subject only
'feat(ui): add picker' | ccommit decode

# breaking via footer
"feat: rework auth\n\nBREAKING CHANGE: drop /v1" | ccommit decode

# body and footers
"fix(api): retry on 503\n\nThe upstream returns 503 during deploys.\n\nRefs #42\nReviewed-by: alice" | ccommit decode

# non-conventional
'hello world' | ccommit decode
```

### `ccommit encode`

Encode a structured commit record back into a Conventional Commits string.  
Inverse of `decode`.

The `conventional` field selects the path (defaults to true):  
- `conventional: true`: the subject is built *solely* from the components (`type`, `scope`, `breaking`, `description`). The `subject` field is **never** read. The built header must be conventional by the same definition `decode` uses, the active type policy included. `encode` errors rather than emit something `decode` would call non-conventional.  
- `conventional: false`: the header isn't a `type: description` shape, so the components can't rebuild it. The raw `subject` line is emitted verbatim.

**Signature:** `record -> string` · **Category:** `conventional-commits`

**Search terms:** `format`, `render`, `serialize`, `build`, `conventional`

**Examples**

```nu
# basic
{type: feat, description: "add picker"} | ccommit encode
# => "feat: add picker"

# with scope and breaking
{type: feat, scope: api, breaking: true, description: "drop /v1"} | ccommit encode
# => "feat(api)!: drop /v1"

# round-trip
'feat(ui): add picker' | ccommit decode | ccommit encode
# => "feat(ui): add picker"
```

### `ccommit is-conventional`

Check whether the piped message has a conformant subject line.

Only the first line is inspected — body and footers are ignored.  
By default any letter-only type is accepted; when  
`valid-types` is configured, the type must appear in it. Matching is  
case-insensitive.

**Signature:** `string -> bool` · **Category:** `conventional-commits`

**Search terms:** `validate`, `check`, `conventional`

**Examples**

```nu
# valid feat
'feat(ui): add picker' | ccommit is-conventional
# => true

# case-insensitive
'FIX: typo' | ccommit is-conventional
# => true

# any type valid by default
'wip: stuff' | ccommit is-conventional
# => true

# out-of-policy type when configured
with-env {CONVENTIONAL_COMMIT_VALID_TYPES: 'feat fix'} { 'wip: stuff' | ccommit is-conventional }
# => false
```

### `ccommit list`

List commits in a git range with each message fully decoded.

Walks `git log <from>..<to>` reading the full message body (`%B`),  
Each row carries hash/author/date plus the same fields  
returned by `ccommit decode`. Errors if the working directory is  
not a git repository or if a revision cannot be resolved.

**Signature:** `nothing -> table` · **Category:** `conventional-commits`

**Parameters**

| Parameter | Type     | Default  | Description                                               |
| --------- | -------- | -------- | --------------------------------------------------------- |
| `from?`   | `string` |          | Starting revision (exclusive). Omit to walk full history. |
| `to?`     | `string` | `"HEAD"` | Ending revision (inclusive).                              |

**Flags**

| Flag                | Type     | Description                                                |
| ------------------- | -------- | ---------------------------------------------------------- |
| `--with-email`      | `switch` | Include the author email.                                  |
| `--with-committer`  | `switch` | Include committer name, email, and date.                   |
| `--with-merge-info` | `switch` | Include parent hashes and an is_merge flag.                |
| `--with-signature`  | `switch` | Include GPG signature status (`%G?`).                      |
| `--with-tag`        | `switch` | Include the earliest tag containing each commit.           |
| `--with-stats`      | `switch` | Include files_changed / insertions / deletions per commit. |
| `--with-changes`    | `switch` | Include `added` / `modified` / `deleted` file-path lists.  |
| `--no-abbrev`       | `switch` | Show full commit/parent hashes instead of abbreviated ones.|

**Search terms:** `list`, `log`, `range`, `git`, `conventional`

**Examples**

```nu
# recent commits
ccommit list HEAD~10 HEAD

# between tags
ccommit list v1.4.0 v1.5.0

# full history
ccommit list

# breaking only
ccommit list | where breaking

# non-conformant
ccommit list | where not conventional

# which release shipped each
ccommit list HEAD~10 --with-tag

# drop merges
ccommit list --with-merge-info | where not is_merge

# biggest changes
ccommit list --with-stats | sort-by insertions --reverse | first 5

# commits that touch mod.nu
ccommit list --with-changes | where {|r| ([...$r.added ...$r.modified ...$r.deleted] | any { $in =~ 'mod.nu' })}
```

## CI/CD recipes

These are ready-made functions or ready-to-adapt starting points. Each is a small function that takes the commit range as explicit `from` / `to` arguments.

### Validate every commit in a pull request

Fail the pipeline if any commit in the range isn't conventional. The offenders' hashes and subjects are printed before exit so the author can fix them up:

```nu
def assert-conventional [from: string, to: string = HEAD] {
    let offenders = ccommit list $from $to | where not conventional
    if ($offenders | is-empty) { return }
    print $'(ansi red)Non-conventional commits:(ansi reset)'
    $offenders | select hash author subject | each {$in | table -e} | str join "\n\n" | print
    error make --unspanned {msg: $"($offenders | length) commit\(s) need a conventional header"}
}
```

### Skip CI when no commit is build-worthy

Short-circuit the pipeline when the range only carries `docs` / `chore` / `style` noise. `build-worthy` returns the commits whose type is worth building; an empty result means skip.

```nu
let worthy = ccommit list origin/main | where {|c| $c.conventional and ($c.type in $types)}
if ($worthy | is-empty) {
    print $'no build-worthy commits - skipping pipeline'
    return
}
```

### Build only the components touched by a merge request

In an imaginary monorepo where each top-level directory is an independent component, build only the components that were touched in the current merge request - and that still exists on disk:

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

touched-components origin/main HEAD | par-each {|c|
    print $"building ($c)…"
    ^make -C $c build test
}
```

### Determine the next semver bump

Pair `ccommit` with [`semver`](https://github.com/lassoColombo/semantic-versioning) to compute the next tag from the commits since the last release: in this example a breaking change bumps major, a `feat` bumps minor, a `fix`/`perf`/`refactor` bumps patch.

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

### Generate a release changelog

```nu
def md-escape []: string -> string {
    $in | str replace --all --regex r#'([!-/:-@\[-`{-~])'# r#'\${1}'#
}

def changelog [from: string, to: string = HEAD]: nothing -> string {
    let titles = {feat: '✨ Features', fix: '🐛 Bug Fixes', perf: '⚡ Performance', refactor: '♻️ Refactoring'}
    let commits = ccommit list $from $to | where conventional

    $titles | items {|type, title|
        let bullets = $commits | where type == $type | each {|c|
            let scope = if ($c.scope | is-empty) { '' } else { $"**($c.scope)** " }
            let mark  = if $c.breaking { ' ⚠️' } else { '' }
            $"- ($scope)($c.description | md-escape)($mark) `($c.hash | str substring ..7)`"
        }
        if ($bullets | is-empty) { null } else { $"## ($title)\n($bullets | str join "\n")" }
    } | compact | str join "\n\n"
}
```

## Mentions

Tests are powered by [nutest](https://github.com/vyadh/nutest) an amazing testing framework for nushell
