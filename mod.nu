# Conventional Commits parser.
#
# Implements https://www.conventionalcommits.org/en/v1.0.0/. Parses a
# commit message into its structured pieces (kind, scope, breaking,
# subject, body, footers), or walks a git range and produces a table of
# fully parsed commits.
#
# Public commands:
#   ccommit is-conventional  — header-only validity check
#   ccommit decode            — full structured parse of a message
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
def is-blank []: string -> bool { ($in | str trim) | is-empty }
# Partition a commit message into subject / body / footer-block lines.
def split-message [msg: string] {
    let lines = $msg | lines
    let subject = $lines | first | default ''
    let after = $lines | skip 1
    let empty = {subject: $subject, body: null, footer_lines: []}
    # Spec rule 6: a body MUST begin one blank line after the description.
    # Without that blank line, treat the message as subject-only.
    if ($after | is-empty) or (not ($after | first | is-blank)) { return $empty }
    let trimmed = $after | skip while { is-blank } | reverse | skip while { is-blank } | reverse
    if ($trimmed | is-empty) { return $empty }
    # Normalize whitespace-only lines to '' so `split list` can find them.
    let norm = $trimmed | each {|l| if ($l | is-blank) { '' } else { $l }}
    let paragraphs = $norm | split list ''
    let last = $paragraphs | last
    let is_footer_block = ($last | is-not-empty) and (($last | first) =~ $FOOTER_REGEX)
    if $is_footer_block {
        let body_paras = $paragraphs | drop 1
        {
            subject: $subject
            body: (if ($body_paras | is-empty) { null } else { $body_paras | each { str join "\n" } | str join "\n\n" })
            footer_lines: $last
        }
    } else {
        {
            subject: $subject
            body: ($paragraphs | each { str join "\n" } | str join "\n\n")
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
                let merged = {token: $prev.token, value: ($prev.value + "\n" + $line)}
                $acc | drop 1 | append $merged
            }
        } else {
            let r = $m | first
            $acc | append {token: $r.token, value: $r.value}
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
@search-terms types kinds conventional commits
@example "list the kinds" { ccommit kinds } --result [feat fix perf refactor revert test ci build docs style chore]
def kinds [] { [
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
@search-terms validate check conventional
@example "valid feat" { 'feat(ui): add picker' | ccommit is-conventional } --result true
@example "case-insensitive" { 'FIX: typo' | ccommit is-conventional } --result true
@example "invalid wip" { 'wip stuff' | ccommit is-conventional } --result false
export def is-conventional [] { $in | lines | first | default '' | $in =~ ('(?i)' + $SUBJECT_REGEX) }
# Decode the piped commit message into its structured parts.
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
@search-terms parse split decompose conventional
@example "subject only" { 'feat(ui): add picker' | ccommit decode }
@example "breaking via footer" { "feat: rework auth\n\nBREAKING CHANGE: drop /v1" | ccommit decode }
@example "body and footers" { "fix(api): retry on 503\n\nThe upstream returns 503 during deploys.\n\nRefs #42\nReviewed-by: alice" | ccommit decode }
@example "non-conventional" { 'hello world' | ccommit decode }
export def decode [] {
    let msg = $in
    let s = split-message $msg
    let footers = parse-footers $s.footer_lines
    let m = $s.subject | parse --regex ('(?i)' + $SUBJECT_REGEX)
    if ($m | is-empty) {
        {
            kind: null
            scope: null
            breaking: false
            subject: $s.subject
            description: null
            body: $s.body
            footers: $footers
            conventional: false
        }
    } else {
        let r = $m | first
        let footer_breaking = $footers | any {$in.token in ['BREAKING CHANGE' 'BREAKING-CHANGE']}
        {
            kind: ($r.kind | str downcase)
            scope: $r.scope
            breaking: (($r.breaking == '!') or $footer_breaking)
            subject: $s.subject
            description: $r.description
            body: $s.body
            footers: $footers
            conventional: true
        }
    }
}
# List commits in a git range with each message fully parsed.
#
# Walks `git log <from>..<to>` reading the full message body (`%B`),
# with NUL-separated records (`-z`) so multi-line messages survive
# intact. Each row carries hash/author/date plus the same fields
# returned by `ccommit decode`.
@search-terms list log range git conventional
@example "recent commits" { ccommit list HEAD~10 HEAD }
@example "breaking only" { ccommit list | where breaking }
@example "non-conformant" { ccommit list | where not conventional }
export def list [
    from?: string      # Starting revision, exclusive. Omit to walk full history.
    to: string = HEAD  # Ending revision.
]: nothing -> table {
    let range = if ($from | is-empty) { [] } else { [$"($from)..($to)"] }
    let sep = char us
    let nul = char nul
    let res = ^git --no-pager log -z --pretty=format:%H%x1f%an%x1f%aI%x1f%B ...$range | complete
    if $res.exit_code != 0 { error make --unspanned {msg: $res.stderr} }
    $res.stdout | split row $nul | where {|s| not ($s | is-blank)} | each {|rec|
        # `--number 4` caps splits so a `\x1f` inside the message body
        # cannot bleed into the metadata columns.
        let fields = $rec | split row --number 4 $sep
        let message = $fields | get 3? | default ''
        let p = $message | decode
        {
            hash: $fields.0
            author: $fields.1
            date: ($fields.2 | into datetime)
            subject: $p.subject
        } | merge ($p | reject subject)
    }
}
