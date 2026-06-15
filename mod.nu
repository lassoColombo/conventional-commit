# Conventional Commits parser.
#
# Implements https://www.conventionalcommits.org/en/v1.0.0/. Parses a
# commit message into its structured pieces (kind, scope, breaking,
# subject, body, footers), or walks a git range and produces a table of
# fully parsed commits.

const SUBJECT_REGEX = '^(?P<kind>[A-Za-z]+)(?:\((?P<scope>[^)]+)\))?(?P<breaking>!)?: (?P<description>.+)$'
const FOOTER_REGEX = '^(?P<token>BREAKING CHANGE|BREAKING-CHANGE|[A-Za-z][A-Za-z0-9-]*)(?P<sep>: | #)(?P<value>.*)$'
def is-blank []: string -> bool { ($in | str trim) | is-empty }

# Partition a commit message into subject / body / footer-block lines.
def split-message [msg: string] {
    let lines = $msg | lines
    let subject = $lines | first | default ''
    let after = $lines | skip 1
    let empty = {subject: $subject, body: null, footer_lines: []}
    if ($after | is-empty) or (not ($after | first | is-blank)) { return $empty }
    let trimmed = $after | skip while { is-blank } | reverse | skip while { is-blank } | reverse
    if ($trimmed | is-empty) { return $empty }
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
# appended as continuation to the previous footer's value.
def decode-footers [lines: list<string>] {
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

# Check whether the piped message has a conformant subject line.
#
# Only the first line is inspected — body and footers are ignored.
# Type matching is case-insensitive (spec rule 15); a message with a
# `BREAKING CHANGE` footer but a non-conformant header still returns false.
@category conventional-commits
@search-terms validate check conventional
@example "valid feat" { 'feat(ui): add picker' | ccommit is-conventional } --result true
@example "case-insensitive" { 'FIX: typo' | ccommit is-conventional } --result true
@example "invalid wip" { 'wip stuff' | ccommit is-conventional } --result false
export def is-conventional []: string -> bool {
    $in | lines | first | default '' | $in =~ ('(?i)' + $SUBJECT_REGEX)
}

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
@category conventional-commits
@search-terms parse split decompose conventional
@example "subject only" { 'feat(ui): add picker' | ccommit decode }
@example "breaking via footer" { "feat: rework auth\n\nBREAKING CHANGE: drop /v1" | ccommit decode }
@example "body and footers" { "fix(api): retry on 503\n\nThe upstream returns 503 during deploys.\n\nRefs #42\nReviewed-by: alice" | ccommit decode }
@example "non-conventional" { 'hello world' | ccommit decode }
export def decode []: string -> record {
    let msg = $in
    let s = split-message $msg
    let footers = decode-footers $s.footer_lines
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

# Encode a structured commit record back into a Conventional Commits string.
#
# Inverse of `decode`. Round-trips canonical inputs:
#   `'feat(ui)!: x' | decode | encode` returns `'feat(ui)!: x'`.
#
# Fields used (all optional unless noted):
#   - kind         — required for a conventional subject; if null or missing,
#                    the raw `subject` field is emitted verbatim so that
#                    non-conventional decoded records round-trip
#   - scope        — wrapped in parens when set
#   - breaking     — when true AND no BREAKING (CHANGE|-CHANGE) footer is
#                    present, adds `!` to the prefix. When a BREAKING footer
#                    is present the `!` is suppressed (canonical minimal form);
#                    this means `feat!: x\n\nBREAKING CHANGE: y` collapses to
#                    `feat: x\n\nBREAKING CHANGE: y` on a decode→encode round
#   - description  — required when `kind` is set
#   - body         — emitted after one blank line; pre-joined with `\n\n`
#                    between paragraphs (the shape `decode` produces)
#   - footers      — emitted after one blank line, one per line, with `: `
#                    separator. The alternate ` #` separator is NOT preserved.
@category conventional-commits
@search-terms format render serialize build conventional
@example "basic" { {kind: feat, description: "add picker"} | ccommit encode } --result "feat: add picker"
@example "with scope and breaking" { {kind: feat, scope: api, breaking: true, description: "drop /v1"} | ccommit encode } --result "feat(api)!: drop /v1"
@example "round-trip" { 'feat(ui): add picker' | ccommit decode | ccommit encode } --result "feat(ui): add picker"
export def encode []: record -> string {
    let r = $in
    let kind = $r.kind? | default null
    let scope = $r.scope? | default null
    let breaking = $r.breaking? | default false
    let description = $r.description? | default null
    let body = $r.body? | default null
    let footers = $r.footers? | default []

    let subject = if ($kind | is-empty) {
        # No kind → emit the raw subject (round-trips non-conventional decodes).
        $r.subject? | default ''
    } else {
        if ($description | is-empty) {
            error make --unspanned {msg: "encode: `description` is required when `kind` is set"}
        }
        let scope_part = if ($scope | is-empty) { '' } else { '(' + $scope + ')' }
        # If a BREAKING (CHANGE|-CHANGE) footer is already present, the
        # spec considers that sufficient — suppress `!` for the canonical
        # minimal form (rules 11, 16).
        let has_breaking_footer = $footers | any {$in.token in ['BREAKING CHANGE' 'BREAKING-CHANGE']}
        let bang = if ($breaking and (not $has_breaking_footer)) { '!' } else { '' }
        $"($kind)($scope_part)($bang): ($description)"
    }

    let body_part = if ($body | is-empty) { '' } else { "\n\n" + $body }
    let footer_part = if ($footers | is-empty) { '' } else {
        "\n\n" + ($footers | each {|f| $"($f.token): ($f.value)"} | str join "\n")
    }

    $subject + $body_part + $footer_part
}
# List commits in a git range with each message fully decoded.
#
# Walks `git log <from>..<to>` reading the full message body (`%B`),
# with NUL-separated records (`-z`) so multi-line messages survive
# intact. Each row carries hash/author/date plus the same fields
# returned by `ccommit decode`. Errors if the working directory is
# not a git repository or if a revision cannot be resolved.
@category conventional-commits
@search-terms list log range git conventional
@example "recent commits" { ccommit list HEAD~10 HEAD }
@example "between tags" { ccommit list v1.4.0 v1.5.0 }
@example "full history" { ccommit list }
@example "breaking only" { ccommit list | where breaking }
@example "non-conformant" { ccommit list | where not conventional }
export def list [
    from?: string      # Starting revision (exclusive). Omit to walk full history.
    to: string = HEAD  # Ending revision (inclusive). Defaults to HEAD.
]: nothing -> table {
    let range = if ($from | is-empty) { [] } else { [$"($from)..($to)"] }
    let sep = char us
    let nul = char nul
    let res = ^git --no-pager log -z --pretty=format:%H%x1f%an%x1f%aI%x1f%B ...$range | complete
    if $res.exit_code != 0 { error make --unspanned {msg: $res.stderr} }
    $res.stdout | split row $nul | where {|s| not ($s | is-blank)} | each {|rec|
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
