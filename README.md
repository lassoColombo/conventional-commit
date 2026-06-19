# conventional-commit

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) for Nushell

Parse a message into structured pieces, encode a record back into a message, and walk git ranges.

## Why?

Because answering questions like `which breaking changes shipped between v1.4.0 and v1.5.0?` using grep and regexes goes wrong quickly.
This module provides functions that parse conventional commits into predictable, structured data, according to the official specification.
It allows you to answer those kinds of questions with ease, and precision:
```nu
conventional-commit list v1.4.0 v1.5.0 | where breaking | select hash scope description
```

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) conventional-commit] | path join
git clone git@github.com:lassoColombo/conventional-commit.git $dest

# use the module
use conventional-commit
conventional-commit decode --help
```

## Quick start

```nu
use conventional-commit

# header-only validity check (non-throwing)
'feat(ui): add picker' | conventional-commit is-conventional      # => true
'FIX: typo'            | conventional-commit is-conventional      # => true  (case-insensitive)
'wip stuff'            | conventional-commit is-conventional      # => false

# full parse — always returns the same shape, even for non-conventional input
'feat(ui)!: rework picker' | conventional-commit decode
# => { kind: feat, scope: ui, breaking: true, description: 'rework picker', ... }

# encode a record back into a message (inverse of decode)
{kind: feat, scope: api, breaking: true, description: 'drop /v1'} | conventional-commit encode
# => 'feat(api)!: drop /v1'

# walk a git range
conventional-commit list HEAD~10 HEAD
# => table<hash, author, date, subject, kind, scope, breaking, description, body, footers, conventional>

# common queries
conventional-commit list v1.4.0 v1.5.0 | where breaking
conventional-commit list | where not conventional                  # find offenders
conventional-commit list | where kind == 'feat' and scope == 'api'
conventional-commit list HEAD~50 HEAD | group-by kind | transpose kind count | update count {|r| $r.count | length}
```

## Parsed shape

`conventional-commit decode` always returns this record. Fields are nullable so non-conventional input is still safe to consume:

```nu
{
  kind:         string | null   # lowercased type, or null when not conventional
  scope:        string | null   # text inside parens, or null
  breaking:     bool            # true when `!` is in the prefix OR a BREAKING CHANGE footer is present
  subject:      string          # the raw first line
  description:  string | null   # text after `: ` (spec rule 5), or null
  body:         string | null   # body paragraphs joined with `\n\n`, or null
  footers:      table<token: string, value: string>
  conventional: bool            # true when the subject line conforms
}
```

`conventional-commit list` augments each row with `hash`, `author`, and `date` from `git log`.

## Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `conventional-commit is-conventional` | `string -> bool` | Header-only validity check. Body and footers are ignored. |
| `conventional-commit decode` | `string -> record` | Full structured parse. Returns the same shape for conventional and non-conventional input. |
| `conventional-commit encode` | `record -> string` | Inverse of `decode`. Renders a structured record back into a Conventional Commits string. |
| `conventional-commit list` | `[from?: string, to: string = HEAD] -> table` | Walk `git log <from>..<to>` and parse each commit. Omit `from` to walk full history. |

### `conventional-commit encode` round-trip

`encode` is the inverse of `decode` for canonical inputs:

```nu
'feat(ui): add picker' | conventional-commit decode | conventional-commit encode
# => 'feat(ui): add picker'
```

Notes on the canonical minimal form:

- When `kind` is null/missing, the raw `subject` field is emitted verbatim — so non-conventional decodes still round-trip.
- When `breaking: true` AND a `BREAKING CHANGE` / `BREAKING-CHANGE` footer is present, the `!` marker is suppressed (the footer alone is sufficient per rules 11, 16). This means `feat!: x\n\nBREAKING CHANGE: y` collapses to `feat: x\n\nBREAKING CHANGE: y` on a decode → encode round-trip.
- Footers are always emitted with the `: ` separator; the alternate ` #` separator is not preserved.

### `conventional-commit list` ranges

`from` is exclusive, `to` defaults to `HEAD` — matching `git log` semantics:

```nu
conventional-commit list                    # full history
conventional-commit list HEAD~10            # last 10 commits
conventional-commit list v1.4.0 v1.5.0      # commits between two tags
conventional-commit list main..feature/x    # also works — pass any single revspec as `from`
```

Messages are read with `git log -z --pretty=%B`, so multi-line bodies and footers survive intact.

## Spec compliance

Parsing covers the full [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) BNF:

- Any letter-only type, case-insensitive (rules 1, 14, 15) — `Feat`, `FIX`, and `feat` are all valid
- Optional scope in parentheses (rule 4)
- `!` breaking marker in the prefix (rule 13) — folded into the `breaking` flag
- Body after exactly one blank line; free-form paragraphs (rules 6, 7) — a missing blank line means the message is treated as subject-only, no body
- Footer block with `<token>: <value>` or `<token> #<value>` separators (rule 8), word form using `-` for whitespace (rule 9)
- Multi-line footer values continue on subsequent non-footer-matching lines (rule 10)
- `BREAKING CHANGE` and `BREAKING-CHANGE` footers (rules 11, 12, 16) set `breaking: true` in the parsed record, alongside any `!` marker

## Naming notes

- `decode` / `encode` rather than `parse` / `format` — `parse` would shadow the built-in `parse --regex` the module relies on internally.
