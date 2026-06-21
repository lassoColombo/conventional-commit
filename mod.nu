# Conventional Commits parser.
#
# Implements https://www.conventionalcommits.org/en/v1.0.0/. Parses a
# commit message into its structured pieces (type, scope, breaking,
# subject, body, footers), or walks a git range and produces a table of
# fully parsed commits.

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

# The project's allowed type list — an **optional** policy overlay.
#
# By default this is empty, meaning *no restriction*: any letter-only
# type is conventional, matching the spec, which reserves meaning only
# for `feat`/`fix` and otherwise leaves the type set open (rule 14).
#
# Set `$env.CONVENTIONAL_COMMIT_VALID_TYPES` to enforce a closed set —
# `is-conventional` and `decode` then reject any type outside it. The
# value may be a `list<string>` or a comma/space-separated string (env
# vars set from POSIX shells are always strings). An unset or empty
# value means "unrestricted" and returns `[]`.
@category conventional-commits
@search-terms types allowed policy valid convention whitelist
@example "default — unrestricted (any type valid)" { ccommit valid-types } --result []
@example "with project override" { with-env {CONVENTIONAL_COMMIT_VALID_TYPES: 'feat fix chore'} { ccommit valid-types } } --result [feat fix chore]
export def valid-types []: nothing -> list<string> {
  let raw = $env.CONVENTIONAL_COMMIT_VALID_TYPES? | default null
  if ($raw | is-empty) {
    []
  } else if (($raw | describe) | str starts-with 'list') {
    $raw
  } else {
    # Comma/space-separated string form, for shell-friendly setup.
    $raw | split row --regex '[\s,]+' | where {|s| ($s | str trim | is-not-empty)}
  }
}

# Build the subject-line regex from `valid-types`. When a policy list is
# configured the types are joined as an alternation (`feat|fix|...`)
# sorted longest-first so the regex engine can't accept a shorter type
# as a prefix of a longer one (`fix` vs `fixtures`, etc.). When the list
# is empty (the default), the type slot matches any letter-only token —
# the spec only requires the type to be a noun (rule 14), not a member
# of a fixed set.
def subject-regex []: nothing -> string {
  let types = valid-types
  let type_pat = if ($types | is-empty) {
    '[a-zA-Z]+'
  } else {
    $types | sort-by {|t| $t | str length} --reverse | str join '|'
  }
  {types: $type_pat} | format pattern r#'^(?P<type>({types}))(?:\((?P<scope>[^)]+)\))?(?P<breaking>!)?: (?P<description>.+)$'#
}

# Check whether the piped message has a conformant subject line.
#
# Only the first line is inspected — body and footers are ignored.
# By default any letter-only type is accepted (matching the spec); when
# `valid-types` is configured, the type must appear in it. Matching is
# case-insensitive (spec rule 15). A message with a `BREAKING CHANGE`
# footer but a non-conformant header still returns false.
@category conventional-commits
@search-terms validate check conventional
@example "valid feat" { 'feat(ui): add picker' | ccommit is-conventional } --result true
@example "case-insensitive" { 'FIX: typo' | ccommit is-conventional } --result true
@example "any type valid by default" { 'wip: stuff' | ccommit is-conventional } --result true
@example "out-of-policy type when configured" { with-env {CONVENTIONAL_COMMIT_VALID_TYPES: 'feat fix'} { 'wip: stuff' | ccommit is-conventional } } --result false
export def is-conventional []: string -> bool {
  $in | lines | first | default '' | $in =~ ('(?i)' + (subject-regex))
}

# Decode the piped commit message into its structured parts.
#
# Always returns a record with the same shape, so non-conventional
# input is still safe to consume:
#   - type         — lowercased type, or null when not conventional
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
  let m = $s.subject | parse --regex ('(?i)' + (subject-regex))
  if ($m | is-empty) {
    {
      type: null
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
      type: ($r.type | str downcase)
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
#   - type         — required for a conventional subject; if null or missing,
#                    the raw `subject` field is emitted verbatim so that
#                    non-conventional decoded records round-trip
#   - scope        — wrapped in parens when set
#   - breaking     — when true AND no BREAKING (CHANGE|-CHANGE) footer is
#                    present, adds `!` to the prefix. When a BREAKING footer
#                    is present the `!` is suppressed (canonical minimal form);
#                    this means `feat!: x\n\nBREAKING CHANGE: y` collapses to
#                    `feat: x\n\nBREAKING CHANGE: y` on a decode→encode round
#   - description  — required when `type` is set
#   - body         — emitted after one blank line; pre-joined with `\n\n`
#                    between paragraphs (the shape `decode` produces)
#   - footers      — emitted after one blank line, one per line, with `: `
#                    separator. The alternate ` #` separator is NOT preserved.
@category conventional-commits
@search-terms format render serialize build conventional
@example "basic" { {type: feat, description: "add picker"} | ccommit encode } --result "feat: add picker"
@example "with scope and breaking" { {type: feat, scope: api, breaking: true, description: "drop /v1"} | ccommit encode } --result "feat(api)!: drop /v1"
@example "round-trip" { 'feat(ui): add picker' | ccommit decode | ccommit encode } --result "feat(ui): add picker"
export def encode []: record -> string {
  let r = $in
  let type = $r.type? | default null
  let scope = $r.scope? | default null
  let breaking = $r.breaking? | default false
  let description = $r.description? | default null
  let body = $r.body? | default null
  let footers = $r.footers? | default []

  let subject = if ($type | is-empty) {
    # No type → emit the raw subject (round-trips non-conventional decodes).
    $r.subject? | default ''
  } else {
    if ($description | is-empty) {
      error make --unspanned {msg: "encode: `description` is required when `type` is set"}
    }
    let scope_part = if ($scope | is-empty) { '' } else { '(' + $scope + ')' }
    # If a BREAKING (CHANGE|-CHANGE) footer is already present, the
    # spec considers that sufficient — suppress `!` for the canonical
    # minimal form (rules 11, 16).
    let has_breaking_footer = $footers | any {$in.token in ['BREAKING CHANGE' 'BREAKING-CHANGE']}
    let bang = if ($breaking and (not $has_breaking_footer)) { '!' } else { '' }
    $"($type)($scope_part)($bang): ($description)"
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
#
# Optional decoration flags add extra columns:
#   --with-email      author_email
#   --with-committer  committer, committer_email, committer_date
#   --with-merge-info parents (list<string>), is_merge (bool)
#   --with-signature  signature ('G'/'B'/'U'/'N'/'E' from `%G?`)
#   --with-tag        tag — earliest tag containing each commit, or null
#   --with-stats      files_changed, insertions, deletions (ints)
#   --with-changes    added, modified, deleted — file paths bucketed by change type
@category conventional-commits
@search-terms list log range git conventional
@example "recent commits" { ccommit list HEAD~10 HEAD }
@example "between tags" { ccommit list v1.4.0 v1.5.0 }
@example "full history" { ccommit list }
@example "breaking only" { ccommit list | where breaking }
@example "non-conformant" { ccommit list | where not conventional }
@example "which release shipped each" { ccommit list HEAD~10 --with-tag }
@example "drop merges" { ccommit list --with-merge-info | where not is_merge }
@example "biggest changes" { ccommit list --with-stats | sort-by insertions --reverse | first 5 }
@example "commits that touch mod.nu" { ccommit list --with-changes | where {|r| ([...$r.added ...$r.modified ...$r.deleted] | any { $in =~ 'mod.nu' })} }
@example "deletion commits only" { ccommit list --with-changes | where {|r| ($r.deleted | is-not-empty)} }
export def list [
  from?: string             # Starting revision (exclusive). Omit to walk full history.
  to: string = HEAD         # Ending revision (inclusive). Defaults to HEAD.
  --with-email              # Include the author email.
  --with-committer          # Include committer name, email, and date.
  --with-merge-info         # Include parent hashes and an is_merge flag.
  --with-signature          # Include GPG signature status (`%G?`).
  --with-tag                # Include the earliest tag containing each commit.
  --with-stats              # Include files_changed / insertions / deletions per commit.
  --with-changes            # Include `added` / `modified` / `deleted` file-path lists.
]: nothing -> table {
  let range = if ($from | is-empty) { [] } else { [$"($from)..($to)"] }
  let fmt = '%H%x1f%an%x1f%ae%x1f%aI%x1f%cn%x1f%ce%x1f%cI%x1f%P%x1f%G?%x1f%B'
  let res = ^git --no-pager log -z $"--pretty=format:($fmt)" ...$range | complete
  if $res.exit_code != 0 { error make --unspanned {msg: $res.stderr} }

  let rows = $res.stdout
  | split row (char nul) 
  | where {|s| not ($s | is-blank)} 
  | each {|rec|
    let fields = $rec | split row --number 10 (char us)
    let message = $fields | get 9? | default ''
    let p = $message | decode
    let parents = if ($fields.7 | is-empty) { [] } else { $fields.7 | split row ' ' }
    {
      hash: $fields.0
      author: $fields.1
      author_email: $fields.2
      date: ($fields.3 | into datetime)
      committer: $fields.4
      committer_email: $fields.5
      committer_date: ($fields.6 | into datetime)
      parents: $parents
      is_merge: (($parents | length) > 1)
      signature: $fields.8
      subject: $p.subject
    } | merge ($p | reject subject)
  }

  # `par-each` does not preserve input order. Each enrichment block below
  # therefore enumerates, parallelises, then sorts back by the original index.
  let rows = if not $with_tag { $rows } else {
    $rows | enumerate | par-each {|er|
      let r = $er.item
      let t = ^git tag --contains $r.hash --sort=creatordate | complete
      let tag = if $t.exit_code == 0 {
        let lines = $t.stdout | lines
        if ($lines | is-empty) { null } else { $lines | first }
      } else { null }
      {idx: $er.index, row: ($r | insert tag $tag)}
    } | sort-by idx | get row
  }

  let rows = if not $with_stats { $rows } else {
    $rows | enumerate | par-each {|er|
      let r = $er.item
      let s = ^git show --shortstat --format='' $r.hash | complete
      let stat_line = if $s.exit_code == 0 {
        $s.stdout | lines | where {|l| $l =~ 'changed'} | first | default ''
      } else { '' }
      let pick = {|pat|
        let m = $stat_line | parse --regex $pat
        if ($m | is-empty) { 0 } else { $m | first | get n | into int }
      }
      let enriched = $r
      | insert files_changed (do $pick '(?P<n>\d+) files? changed')
      | insert insertions    (do $pick '(?P<n>\d+) insertions?')
      | insert deletions     (do $pick '(?P<n>\d+) deletions?')
      {idx: $er.index, row: $enriched}
    } | sort-by idx | get row
  }

  let rows = if not $with_changes { $rows } else { 
    let tab = char tab
    $rows | enumerate | par-each {|er|
      let r = $er.item
      let s = ^git show --name-status --format='' $r.hash | complete
      let empty = {added: [], modified: [], deleted: []}
      let buckets = if $s.exit_code == 0 {
        $s.stdout | lines | where {|l| ($l | str trim | is-not-empty)} | reduce --fold $empty {|line, acc|
          let parts = $line | split row $tab
          # `--name-status` emits `<S>\t<path>` for A/M/D/T/U and
          # `<S><score>\t<old>\t<new>` for R/C. Renamed/copied files
          # land in `modified` under their NEW path — the old path is
          # gone, the new path is what the commit produced.
          let status = $parts | get 0 | str substring 0..1
          let path = if $status in ['R' 'C'] {
            $parts | get 2? | default ''
          } else {
            $parts | get 1? | default ''
          }
          match $status {
            'A' => ($acc | update added ($acc.added | append $path))
            'D' => ($acc | update deleted ($acc.deleted | append $path))
            _   => ($acc | update modified ($acc.modified | append $path))
          }
        }
      } else { $empty }
      let enriched = $r | insert added $buckets.added | insert modified $buckets.modified | insert deleted $buckets.deleted
      {idx: $er.index, row: $enriched}
    } | sort-by idx | get row
  }

  mut drop = []
  if not $with_email      { $drop = ($drop | append 'author_email') }
  if not $with_committer  { $drop = ($drop | append [committer committer_email committer_date]) }
  if not $with_merge_info { $drop = ($drop | append [parents is_merge]) }
  if not $with_signature  { $drop = ($drop | append 'signature') }
  if ($drop | is-empty) { $rows } else { $rows | reject ...$drop }
}
