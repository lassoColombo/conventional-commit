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
# {token, sep, value} records. `sep` is the literal separator the footer
# used — `': '` or `' #'` — kept so `encode` can reproduce it exactly.
# Lines that don't start a new footer are appended as continuation to the
# previous footer's value.
def decode-footers [lines: list<string>] {
  $lines | reduce --fold [] {|line, acc|
    let m = $line | parse --regex $FOOTER_REGEX
    if ($m | is-empty) {
      if ($acc | is-empty) { $acc } else {
        let prev = $acc | last
        let merged = {token: $prev.token, sep: $prev.sep, value: ($prev.value + "\n" + $line)}
        $acc | drop 1 | append $merged
      }
    } else {
      let r = $m | first
      $acc | append {token: $r.token, sep: $r.sep, value: $r.value}
    }
  }
}

# True when a footer table carries a breaking-change footer — the uppercase
# `BREAKING CHANGE` or its hyphenated synonym (spec rules 11, 16). The single
# place that token set is spelled out, shared by `decode` and `encode`.
def has-breaking-footer [footers: list]: nothing -> bool {
  $footers | any {|f| $f.token in ['BREAKING CHANGE' 'BREAKING-CHANGE']}
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
def valid-types []: nothing -> list<string> {
  let raw = $env.CONVENTIONAL_COMMIT_VALID_TYPES?
  if ($raw | is-empty) {
    []
  } else if (($raw | describe) | str starts-with 'list') {
    $raw
  } else {
    # Comma/space-separated string form, for shell-friendly setup.
    $raw | split row --regex '[\s,]+' | where {|s| ($s | str trim | is-not-empty)}
  }
}

# Build the subject-line regex for a given set of allowed `types`. When the
# list is non-empty the types are joined as an alternation (`feat|fix|...`)
# sorted longest-first so the regex engine can't accept a shorter type as a
# prefix of a longer one (`fix` vs `fixtures`, etc.). When the list is empty
# the type slot matches any letter-only token — the spec only requires the
# type to be a noun (rule 14), not a member of a fixed set.
#
# Callers pass `(valid-types)` to honour the project policy (`decode`,
# `is-conventional`), or `[]` for the spec-default grammar regardless of policy
# (`encode`, which validates its own output without consulting the env).
def subject-regex [types: list<string>]: nothing -> string {
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
# By default any letter-only type is accepted; when
# `valid-types` is configured, the type must appear in it. Matching is
# case-insensitive.
@category conventional-commits
@search-terms validate check conventional
@example "valid feat" { 'feat(ui): add picker' | ccommit is-conventional } --result true
@example "case-insensitive" { 'FIX: typo' | ccommit is-conventional } --result true
@example "any type valid by default" { 'wip: stuff' | ccommit is-conventional } --result true
@example "out-of-policy type when configured" { with-env {CONVENTIONAL_COMMIT_VALID_TYPES: 'feat fix'} { 'wip: stuff' | ccommit is-conventional } } --result false
export def is-conventional []: string -> bool {
  $in | lines | first | default '' | $in =~ ('(?i)' + (subject-regex (valid-types)))
}

# Decode the piped commit message into its structured parts.
#
# Always returns a record with the same shape, so non-conventional input is still safe to consume:
# - `type`: lowercased type, or null when not conventional
# - `scope`: text inside parens, or null
# - `breaking`: true when `!` is in the prefix OR a BREAKING CHANGE/BREAKING-CHANGE footer is present
# - `bang`: true when the `!` marker was literally in the header. Distinct from `breaking`, which also counts the footer.
# - `subject`: the raw first line of the message
# - `description`: text after `: ` (spec rule 5), or null otherwise
# - `body`: body paragraphs joined with `\n\n`, or null
# - `footers`: `table<token: string, sep: string, value: string>`;
#   `sep` is the literal `': '` or `' #'` the footer used
# - `conventional`: true when the subject line conforms
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
  let m = $s.subject | parse --regex ('(?i)' + (subject-regex (valid-types)))
  if ($m | is-empty) {
    {
      type: null
      scope: null
      breaking: false
      bang: false
      subject: $s.subject
      description: null
      body: $s.body
      footers: $footers
      conventional: false
    }
  } else {
    let r = $m | first
    let footer_breaking = has-breaking-footer $footers
    {
      type: ($r.type | str downcase)
      scope: $r.scope
      breaking: (($r.breaking == '!') or $footer_breaking)
      bang: ($r.breaking == '!')
      subject: $s.subject
      description: $r.description
      body: $s.body
      footers: $footers
      conventional: true
    }
  }
}

# Resolve the header `!` marker from a record's breaking-change signals.
#
# `breaking` is the declared intent; a `!` in the header (`bang`) and a
# BREAKING CHANGE footer are the two ways to realize it (spec rules 11, 16):
#   - breaking with an explicit `bang`        → honour it.
#   - breaking with no `bang` but a footer    → no `!`; the footer alone
#                                               carries it (minimal form).
#   - breaking with neither                   → synthesize the `!`, so the
#                                               declared intent isn't dropped.
#   - not breaking, but a `bang` or a footer  → a contradiction (evidence with
#                                               no claim); error rather than guess.
# Returns `'!'` when the header should carry the marker, `''` otherwise.
def breaking-marker [breaking: bool, bang: bool, footer: bool]: nothing -> string {
  if (not $breaking) and ($bang or $footer) {
    error make --unspanned {msg: "encode: `breaking` is false, but the record carries a `!` marker (`bang`) or a BREAKING CHANGE footer — set `breaking: true`, or drop the marker/footer"}
  }
  if ($bang or ($breaking and (not $footer))) { '!' } else { '' }
}

# Encode a structured commit record back into a Conventional Commits string.
# Inverse of `decode`.
#
# The `conventional` field selects the path (defaults to true):
# - `conventional: true`: the subject is built *solely* from the components (`type`, `scope`, `breaking`, `description`). The `subject` field is **never** read. The built header must be conventional by the same definition `decode` uses, the active type policy included. `encode` errors rather than emit something `decode` would call non-conventional.
# - `conventional: false`: the header isn't a `type: description` shape, so the components can't rebuild it. The raw `subject` line is emitted verbatim.
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
  let bang = $r.bang? | default false
  let description = $r.description? | default null
  let body = $r.body? | default null
  let footers = $r.footers? | default []
  let conventional = $r.conventional? | default true
  let subject = if (not $conventional) { $r.subject? | default '' } else {
    if ($type | is-empty) {
      error make --unspanned {msg: "encode: `type` is required"}
    }
    if ($description | is-empty) {
      error make --unspanned {msg: "encode: `description` is required"}
    }
    let scope_part = if ($scope | is-empty) { '' } else { '(' + $scope + ')' }
    let marker = breaking-marker $breaking $bang (has-breaking-footer $footers)
    let header = $"($type)($scope_part)($marker): ($description)"
    if not ($header =~ ('(?i)' + (subject-regex (valid-types)))) {
      error make --unspanned {msg: $"encode: the components form a non-conventional header \(\"($header)\"); fix `type`/`scope`/`description`, or set `conventional: false` and pass the raw line as `subject`"}
    }
    $header
  }

  let body_part = if ($body | is-empty) { '' } else { "\n\n" + $body }
  let footer_part = if ($footers | is-empty) { '' } else {
    "\n\n" + ($footers | each {|f| $"($f.token)($f.sep? | default ': ')($f.value)"} | str join "\n")
  }

  $subject + $body_part + $footer_part
}

# List commits in a git range with each message fully decoded.
#
# Walks `git log <from>..<to>` reading the full message body (`%B`),
# Each row carries hash/author/date plus the same fields
# returned by `ccommit decode`. Errors if the working directory is
# not a git repository or if a revision cannot be resolved.
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
export def list [
  from?: string             # Starting revision (exclusive). Omit to walk full history.
  to: string = HEAD         # Ending revision (inclusive).
  --with-email              # Include the author email.
  --with-committer          # Include committer name, email, and date.
  --with-merge-info         # Include parent hashes and an is_merge flag.
  --with-signature          # Include GPG signature status (`%G?`).
  --with-tag                # Include the earliest tag containing each commit.
  --with-stats              # Include files_changed / insertions / deletions per commit.
  --with-changes            # Include `added` / `modified` / `deleted` file-path lists.
  --no-abbrev               # Show the full commit hash instead of the abbreviated one.
]: nothing -> table {
  let range = if ($from | is-empty) { [] } else { [$"($from)..($to)"] }
  let hfmt = if $no_abbrev { '%H' } else { '%h' }
  let pfmt = if $no_abbrev { '%P' } else { '%p' }
  let fmt = $'($hfmt)%x1f%an%x1f%ae%x1f%aI%x1f%cn%x1f%ce%x1f%cI%x1f($pfmt)%x1f%G?%x1f%B'
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

  # `--with-stats` / `--with-changes` derive their data from the diff of
  # each commit. Rather than spawn one `git show` per row,
  # each enrichment makes a SINGLE `git log` pass over the same range and
  # builds a hash-keyed lookup. The format prefixes every commit with a
  # record-separator (`%x1e`) so the per-commit blocks can be split apart;
  # `--diff-merges=dense-combined` matches `git show`'s default handling of
  # merge commits (combined diff), so output is unchanged from the old path.
  let rs = char --unicode '1e'

  let rows = if not $with_stats { $rows } else {
    let res = ^git --no-pager log --diff-merges=dense-combined --shortstat $"--pretty=format:($rs)($hfmt)" ...$range | complete
    let stats = if $res.exit_code != 0 { {} } else {
      $res.stdout | split row $rs | where {|c| ($c | str trim | is-not-empty)} | reduce --fold {} {|c, acc|
        let ls = $c | lines
        let stat_line = $ls | where {|l| $l =~ 'changed'} | first | default ''
        let pick = {|pat|
          let m = $stat_line | parse --regex $pat
          if ($m | is-empty) { 0 } else { $m | first | get n | into int }
        }
        $acc | insert ($ls | first) {
          files_changed: (do $pick '(?P<n>\d+) files? changed')
          insertions: (do $pick '(?P<n>\d+) insertions?')
          deletions: (do $pick '(?P<n>\d+) deletions?')
        }
      }
    }
    let zero = {files_changed: 0, insertions: 0, deletions: 0}
    $rows | each {|r|
      let s = $stats | get -o $r.hash | default $zero
      $r | insert files_changed $s.files_changed | insert insertions $s.insertions | insert deletions $s.deletions
    }
  }

  let rows = if not $with_changes { $rows } else {
    let tab = char tab
    let empty = {added: [], modified: [], deleted: []}
    let res = ^git --no-pager log --diff-merges=dense-combined --name-status $"--pretty=format:($rs)($hfmt)" ...$range | complete
    let changes = if $res.exit_code != 0 { {} } else {
      $res.stdout | split row $rs | where {|c| ($c | str trim | is-not-empty)} | reduce --fold {} {|c, acc|
        let ls = $c | lines
        let buckets = $ls | skip 1 | where {|l| ($l | str trim | is-not-empty)} | reduce --fold $empty {|line, b|
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
            'A' => ($b | update added ($b.added | append $path))
            'D' => ($b | update deleted ($b.deleted | append $path))
            _   => ($b | update modified ($b.modified | append $path))
          }
        }
        $acc | insert ($ls | first) $buckets
      }
    }
    $rows | each {|r|
      let b = $changes | get -o $r.hash | default $empty
      $r | insert added $b.added | insert modified $b.modified | insert deleted $b.deleted
    }
  }

  mut drop = []
  if not $with_email      { $drop = ($drop | append 'author_email') }
  if not $with_committer  { $drop = ($drop | append [committer committer_email committer_date]) }
  if not $with_merge_info { $drop = ($drop | append [parents is_merge]) }
  if not $with_signature  { $drop = ($drop | append 'signature') }
  if ($drop | is-empty) { $rows } else { $rows | reject ...$drop }
}
