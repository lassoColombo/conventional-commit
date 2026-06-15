# ccommit

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) for Nushell — parse a message into structured pieces, or walk a git range and get a table of fully parsed commits.

## Why?

`git log --grep` and `awk` can find commits, but they can't answer questions about them. "Which breaking changes shipped between `v1.4.0` and `v1.5.0`?" turns into a parser the moment a `BREAKING CHANGE:` footer enters the picture — and writing that parser correctly (multi-line footer continuations, `!` vs footer breaking markers, case-insensitive types) is a surprising amount of work.

```nu
ccommit list v1.4.0 v1.5.0 | where breaking | select hash scope description
# table of just the breaking changes, ready to paste into release notes
```

Or, on a single message:

```nu
"feat(api)!: drop /v1\n\nBREAKING CHANGE: legacy clients must upgrade" | ccommit decode
# => {
#   kind: 'feat', scope: 'api', breaking: true,
#   description: 'drop /v1',
#   body: null,
#   footers: [{token: 'BREAKING CHANGE', value: 'legacy clients must upgrade'}],
#   conventional: true,
#   ...
# }
```

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) ccommit] | path join
git clone git@github.com:lassoColombo/conventional-commit.git $dest

# use the module
use ccommit
ccommit decode --help
```

## Quick start

```nu
use ccommit

# header-only validity check (non-throwing)
'feat(ui): add picker' | ccommit is-conventional      # => true
'FIX: typo'            | ccommit is-conventional      # => true  (case-insensitive)
'wip stuff'            | ccommit is-conventional      # => false

# full parse — always returns the same shape, even for non-conventional input
'feat(ui)!: rework picker' | ccommit decode
# => { kind: feat, scope: ui, breaking: true, description: 'rework picker', ... }

# walk a git range
ccommit list HEAD~10 HEAD
# => table<hash, author, date, subject, kind, scope, breaking, description, body, footers, conventional>

# common queries
ccommit list v1.4.0 v1.5.0 | where breaking
ccommit list | where not conventional                  # find offenders
ccommit list | where kind == 'feat' and scope == 'api'
ccommit list HEAD~50 HEAD | group-by kind | transpose kind count | update count {|r| $r.count | length}
```

## Parsed shape

`ccommit decode` always returns this record. Fields are nullable so non-conventional input is still safe to consume:

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

`ccommit list` augments each row with `hash`, `author`, and `date` from `git log`.

## Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `ccommit is-conventional` | `string -> bool` | Header-only validity check. Body and footers are ignored. |
| `ccommit decode` | `string -> record` | Full structured parse. Returns the same shape for conventional and non-conventional input. |
| `ccommit list` | `[from?: string, to: string = HEAD] -> table` | Walk `git log <from>..<to>` and parse each commit. Omit `from` to walk full history. |
| `ccommit kinds` | `nothing -> list<string>` | The Angular-convention type list. **Informational only** — not used by validation. |

### `ccommit list` ranges

`from` is exclusive, `to` defaults to `HEAD` — matching `git log` semantics:

```nu
ccommit list                    # full history
ccommit list HEAD~10            # last 10 commits
ccommit list v1.4.0 v1.5.0      # commits between two tags
ccommit list main..feature/x    # also works — pass any single revspec as `from`
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

- `kinds` is **not** consulted by `is-conventional` or `decode`. The spec allows any letter-only type (rule 14); the list is exposed so callers that want a stricter project policy (e.g. "only Angular types") can layer it on top of the spec-correct parser.
- `decode` rather than `parse` — `parse` would shadow the built-in `parse --regex` the module relies on internally.
