# Conventional Commits parser.
#
# Implements https://www.conventionalcommits.org/en/v1.0.0/. Parses a
# commit message into its structured pieces (kind, scope, breaking,
# subject, body, footers), or walks a git range and produces a table of
# fully parsed commits.
#
# Spec coverage:
#   - any letter-only type, case-insensitive (rules 1, 14, 15)
#   - optional scope in parentheses (rule 4)
#   - `!` breaking marker in the prefix (rule 13)
#   - body after exactly one blank line, free-form paragraphs (rules 6, 7)
#   - footer block `<token>: <value>` / `<token> #<value>` with multi-line
#     value continuation (rules 8–10)
#   - BREAKING CHANGE / BREAKING-CHANGE footer (rules 11, 12, 16) folded
#     into the `breaking` flag
#
# Public commands:
#   ccommit kinds            — recommended type set (informational)
#   ccommit is-conventional  — header-only validity check
#   ccommit parts            — full structured parse of a message
#   ccommit list             — git range → table of parsed commits
# ---------- internals ----------
# Subject line: <kind>[(scope)][!]: <description>. `(?i)` is applied at
# parse time so the type is matched case-insensitively per spec rule 15.
const SUBJECT_REGEX = '^(?P<kind>[A-Za-z]+)(?:\((?P<scope>[^)]+)\))?(?P<breaking>!)?: (?P<description>.+)$'
# Footer line: <token><sep><value>. `BREAKING CHANGE` and
# `BREAKING-CHANGE` are the spec-mandated uppercase synonyms (rules 15,
# 16); all other tokens use the `-`-for-whitespace word form (rule 9).
# Separator is `: ` or ` #` (rule 8).
const FOOTER_REGEX = '^(?P<token>BREAKING CHANGE|BREAKING-CHANGE|[A-Za-z][A-Za-z0-9-]*)(?P<sep>: | #)(?P<value>.*)$'
# Partition a commit message into subject / body / footer-block lines.
def split-message [msg: string] {
    let lines = $msg | lines
    if ($lines | is-empty) { return {
        subject: ''
        body: null
        footer_lines: []
    } }
    let subject = $lines | first
    let after = $lines | skip 1
    # Spec rule 6: a body MUST begin one blank line after the description.
    # Without that blank line, treat the message as subject-only.
    if ($after | is-empty) or (($after | first | str trim) | is-not-empty) { return {
        subject: $subject
        body: null
        footer_lines: []
    } }
    let trimmed = $after | skip while {|l| ($l | str trim) | is-empty} | reverse | skip while {|l| ($l | str trim) | is-empty} | reverse
    if ($trimmed | is-empty) { return {
        subject: $subject
        body: null
        footer_lines: []
    } }
    # Normalize whitespace-only lines to '' so `split list` can find them.
    let norm = $trimmed | each {|l| if (($l | str trim) | is-empty) { '' } else { $l }}
    let paragraphs = $norm | split list ''
    let last = $paragraphs | last
    let is_footer_block = (not ($last | is-empty)) and (($last | first) =~ $FOOTER_REGEX)
    if $is_footer_block {
        let body_paras = $paragraphs | drop 1
        let body = if ($body_paras | is-empty) { null } else {
            $body_paras | each {|p| $p | str join "\n"} | str join "\n\n"
        }
        {
            subject: $subject
            body: $body
            footer_lines: $last
        }
    } else {
        let body = $paragraphs | each {|p| $p | str join "\n"} | str join "\n\n"
        {
            subject: $subject
            body: $body
            footer_lines: []
        }
    }
}
# Parse already-identified footer-block lines into a table of
# {token, value} records. Lines that don't start a new footer are
# appended as continuation to the previous footer's value (rule 10).
def parse-footers [lines: list<string>] {
    $lines | reduce --fold [] {|line, acc|
    let m = $line | parse --regex $FOOTER_REGEX
    if ($m | is-empty) {
      if ($acc | is-empty) {
        $acc
      } else {
        let prev = $acc | last
        let merged = { token: $prev.token, value: ($prev.value + "\n" + $line) }
        ($acc | drop 1) | append $merged
      }
    } else {
      let r = $m | first
      $acc | append { token: $r.token, value: $r.value }
    }
  }
}
# ---------- public ----------
# Conventional Commits "recommended" types.
#
# Per spec rule 14 any noun is a valid type; this list is the widely-
# used Angular convention plus `revert` and is exposed for callers that
# want to apply a stricter project policy on top of the spec-correct
# parser. It is NOT used by validation or parsing.
search-terms types kinds conventional commits
example "list the kinds" { ccommit kinds } --result [feat fix perf refactor revert test ci build docs style chore]
export def kinds [] { [
    feat
    fix
    perf
    refactor
    revert
    test
    ci
    build
    docs
    style
    chore
] }
# Check whether the piped message has a conformant subject line.
#
# Only the first line is inspected — body and footers are ignored.
# Type is matched case-insensitively per spec rule 15; a message with a
# `BREAKING CHANGE` footer but a non-conformant header is still false.
search-terms validate check conventional
example "valid feat" { 'feat(ui): add picker' | ccommit is-conventional } --result true
example "case-insensitive" { 'FIX: typo' | ccommit is-conventional } --result true
example "invalid wip" { 'wip stuff' | ccommit is-conventional } --result false
export def is-conventional [] { $in | lines | first | default '' =~ ('(?i)' + $SUBJECT_REGEX) }
# Parse the piped commit message into its structured parts.
#
# Always returns a record with the same shape, so non-conventional
# input is still safe to consume:
#   - kind         — lowercased type, or null when not conventional
#   - scope        — text inside parens, or null
#   - breaking     — true when `!` is in the prefix OR a BREAKING CHANGE
#                    / BREAKING-CHANGE footer is present (rules 11, 16)
#   - subject      — the raw first line of the message
#   - description  — text after `: ` (spec rule 5), or null otherwise
#   - body         — body paragraphs joined with `\n\n`, or null
#   - footers      — table<token: string, value: string>
#   - conventional — true when the subject line conforms
search-terms parse split decompose conventional
example "subject only" { 'feat(ui): add picker' | ccommit parts }
example "breaking via footer" { "feat: rework auth\n\nBREAKING CHANGE: drop /v1" | ccommit parts }
example "body and footers" { "fix(api): retry on 503\n\nThe upstream returns 503 during deploys.\n\nRefs #42\nReviewed-by: alice" | ccommit parts }
example "non-conventional" { 'hello world' | ccommit parts }
export def parts [] { let msg = $in
let s = split-message $msg
let footers = parse-footers $s.footer_lines
let m = $s.subject | parse --regex ('(?i)' + $SUBJECT_REGEX)
if ($m | is-empty) { {
    kind: null
    scope: null
    breaking: false
    subject: $s.subject
    description: null
    body: $s.body
    footers: $footers
    conventional: false
} } else {
    let r = $m | first
    let bang = ($r.breaking == '!')
    let footer_breaking = $footers | any {|f|
      $f.token == 'BREAKING CHANGE' or $f.token == 'BREAKING-CHANGE'
    }
    {
        kind: ($r.kind | str downcase)
        scope: $r.scope
        breaking: ($bang or $footer_breaking)
        subject: $s.subject
        description: $r.description
        body: $s.body
        footers: $footers
        conventional: true
    }
} }
# List commits in a git range with each message fully parsed.
#
# Walks `git log <from>..<to>` reading the full message body (`%B`),
# with NUL-separated records (`-z`) so multi-line messages survive
# intact. Each row carries hash/author/date plus the same fields
# returned by `ccommit parts`.
search-terms list log range git conventional
example "recent commits" { ccommit list HEAD~10 HEAD }
example "breaking only" { ccommit list | where breaking }
example "non-conformant" { ccommit list | where not conventional }
export def list [
  from?: string      # Starting revision, exclusive. Omit to walk full history.
  to: string = HEAD  # Ending revision.
]: nothing -> table {
    let range = if ($from | is-empty) { [] } else { [
        $"($from)..($to)"
    ] }
    let sep = (char -u "1F")
    let nul = (char -u "00")
    let res = (^git --no-pager log -z --pretty=format:%H%x1f%an%x1f%aI%x1f%B ...$range | complete)
    if $res.exit_code != 0 { error make --unspanned {
        msg: $res.stderr
    } }
    $res.stdout | split row $nul | where {|s| ($s | str trim) | is-not-empty} | each {|rec|
      # `--number 4` caps splits so a `\x1f` inside the message body
      # cannot bleed into the metadata columns.
      let fields = $rec | split row --number 4 $sep
      let message = ($fields | get 3? | default '')
      let p = $message | parts
      {
        hash: $fields.0
        author: $fields.1
        date: ($fields.2 | into datetime)
        subject: $p.subject
        kind: $p.kind
        scope: $p.scope
        breaking: $p.breaking
        description: $p.description
        body: $p.body
        footers: $p.footers
        conventional: $p.conventional
      }
    }
}
