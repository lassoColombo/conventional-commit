use std/assert
use std/testing *
use ../mod.nu *

# A controlled git repo seeded with messages that exercise every code path.

@before-each
def setup [] {
    let repo = mktemp --tmpdir --directory
    cd $repo
    ^git init --quiet --initial-branch=main
    ^git config user.email "test@example.invalid"
    ^git config user.name "Test"
    ^git config commit.gpgsign false

    # Commit 1 — plain feat
    "a" | save -f a.txt
    ^git add a.txt
    ^git commit -q -m "feat(ui): add picker"

    # Commit 2 — fix with body and footers
    "b" | save -f b.txt
    ^git add b.txt
    ^git commit -q -m "fix(api): retry on 503

The upstream returns 503 during deploys.

Refs #42
Reviewed-by: alice"

    # Commit 3 — breaking via `!`
    "c" | save -f c.txt
    ^git add c.txt
    ^git commit -q -m "feat(api)!: drop /v1"

    # Tag the third commit as v1.0.0 (so the first 3 commits are contained by v1.0.0).
    ^git tag v1.0.0

    # Commit 4 — breaking via BREAKING CHANGE footer
    "d" | save -f d.txt
    ^git add d.txt
    ^git commit -q -m "feat: rework auth

BREAKING CHANGE: legacy clients must upgrade"

    # Commit 5 — non-conventional
    "e" | save -f e.txt
    ^git add e.txt
    ^git commit -q -m "hello world"

    # Tag the fifth commit as v1.1.0 (so commits 4-5 are contained by v1.1.0 first).
    ^git tag v1.1.0

    {repo: $repo}
}

@after-each
def cleanup [] {
    rm --recursive --force $in.repo
}

# ---------- column shape ----------

@test
def "returns a table with the documented columns in order" [] {
    cd $in.repo
    let l = (list)
    assert equal ($l | columns) [hash author date subject type scope breaking description body footers conventional]
}

@test
def "row count matches the number of commits" [] {
    cd $in.repo
    assert equal ((list) | length) 5
}

# ---------- per-row parsing ----------

@test
def "parses a plain feat row" [] {
    cd $in.repo
    let row = (list | where subject == "feat(ui): add picker" | first)
    assert equal $row.type "feat"
    assert equal $row.scope "ui"
    assert equal $row.description "add picker"
    assert equal $row.breaking false
    assert equal $row.body null
    assert equal $row.footers []
    assert equal $row.conventional true
}

@test
def "parses a row with body and footers, preserving multi-line message" [] {
    cd $in.repo
    let row = (list | where type == "fix" | first)
    assert equal $row.scope "api"
    assert equal $row.description "retry on 503"
    assert equal $row.body "The upstream returns 503 during deploys."
    assert equal ($row.footers | length) 2
    assert equal $row.footers.0 {token: "Refs", value: "42"}
    assert equal $row.footers.1 {token: "Reviewed-by", value: "alice"}
}

@test
def "flags ! as breaking" [] {
    cd $in.repo
    let row = (list | where subject == "feat(api)!: drop /v1" | first)
    assert equal $row.breaking true
}

@test
def "flags BREAKING CHANGE footer as breaking" [] {
    cd $in.repo
    let row = (list | where subject == "feat: rework auth" | first)
    assert equal $row.breaking true
    assert equal $row.footers.0.token "BREAKING CHANGE"
}

@test
def "non-conventional commit keeps shape, conventional=false" [] {
    cd $in.repo
    let row = (list | where subject == "hello world" | first)
    assert equal $row.conventional false
    assert equal $row.type null
    assert equal $row.scope null
    assert equal $row.breaking false
    assert equal $row.body null
    assert equal $row.footers []
}

# ---------- git metadata ----------

@test
def "fills hash, author and date columns" [] {
    cd $in.repo
    let row = (list | first)
    assert equal ($row.hash | str length) 40
    assert equal $row.author "Test"
    assert equal ($row.date | describe) "datetime"
}

# ---------- range semantics ----------

@test
def "with no args walks the full history" [] {
    cd $in.repo
    assert equal ((list) | length) 5
}

@test
def "from equal to to yields an empty range" [] {
    cd $in.repo
    # Positional `from` swallows the first arg, so `list HEAD` is `HEAD..HEAD`.
    # To walk full history, omit `from` entirely.
    assert equal ((list HEAD) | length) 0
    assert equal ((list HEAD HEAD) | length) 0
}

@test
def "narrows to a from..to range" [] {
    cd $in.repo
    # `from` is exclusive: HEAD~3..HEAD includes the last 3 commits.
    assert equal ((list HEAD~3 HEAD) | length) 3
}

@test
def "defaults `to` to HEAD" [] {
    cd $in.repo
    # `list HEAD~2` should equal `list HEAD~2 HEAD`.
    let a = (list HEAD~2)
    let b = (list HEAD~2 HEAD)
    assert equal ($a | get hash) ($b | get hash)
}

# ---------- error handling ----------

@test
def "errors on a non-existent revision" [] {
    cd $in.repo
    assert error { list nonexistent-ref HEAD }
}

@test
def "errors when not in a git repo" [] {
    let nonrepo = mktemp --tmpdir --directory
    cd $nonrepo
    assert error { list }
    cd /
    rm --recursive --force $nonrepo
}

# ---------- streaming integrity ----------

@test
def "messages containing \\x1f bytes do not corrupt columns" [] {
    cd $in.repo
    # Append a commit whose body contains a literal \x1f. The `--number 10`
    # cap on the split should keep the bytes inside the `body` field.
    "f" | save -f f.txt
    ^git add f.txt
    let payload = $"feat: extra(char nul)body has (char us) inside"
    # ^^ can't pass NUL via -m, use here-doc instead
    let msg = $"feat: extra\n\nbody has (char us) inside"
    $msg | ^git commit -q -F -
    let row = (list | where subject == "feat: extra" | first)
    assert str contains $row.body "inside"
    assert equal $row.type "feat"
}

# ---------- decoration flags ----------

@test
def "with-email adds author_email between author and date" [] {
    cd $in.repo
    let cols = (list --with-email | columns)
    assert equal $cols [hash author author_email date subject type scope breaking description body footers conventional]
    let row = (list --with-email | first)
    assert equal $row.author_email "test@example.invalid"
}

@test
def "with-committer adds committer trio after date" [] {
    cd $in.repo
    let cols = (list --with-committer | columns)
    assert equal $cols [hash author date committer committer_email committer_date subject type scope breaking description body footers conventional]
    let row = (list --with-committer | first)
    assert equal $row.committer "Test"
    assert equal $row.committer_email "test@example.invalid"
    assert equal ($row.committer_date | describe) "datetime"
}

@test
def "with-merge-info adds parents and is_merge" [] {
    cd $in.repo
    let cols = (list --with-merge-info | columns)
    assert equal $cols [hash author date parents is_merge subject type scope breaking description body footers conventional]
    # All seeded commits are linear; only the very first commit has 0 parents.
    let head = (list --with-merge-info | first)
    assert equal ($head.parents | length) 1
    assert equal $head.is_merge false
    let root = (list --with-merge-info | last)
    assert equal ($root.parents | length) 0
    assert equal $root.is_merge false
}

@test
def "with-merge-info flags a real merge commit" [] {
    cd $in.repo
    # Build a feature branch off HEAD~1, then merge it back with --no-ff.
    ^git checkout -q -b side HEAD~1
    "g" | save -f g.txt
    ^git add g.txt
    ^git commit -q -m "chore: side branch work"
    ^git checkout -q main
    ^git merge -q --no-ff -m "chore: merge side" side
    let row = (list --with-merge-info | first)
    assert equal $row.subject "chore: merge side"
    assert equal $row.is_merge true
    assert equal ($row.parents | length) 2
}

@test
def "with-signature adds an N for unsigned commits" [] {
    cd $in.repo
    let cols = (list --with-signature | columns)
    assert equal $cols [hash author date signature subject type scope breaking description body footers conventional]
    let row = (list --with-signature | first)
    # Fixture explicitly disables gpgsign — every commit is unsigned (N).
    assert equal $row.signature "N"
}

@test
def "with-tag returns the earliest containing tag, or null" [] {
    cd $in.repo
    let cols = (list --with-tag | columns)
    assert equal $cols [hash author date subject type scope breaking description body footers conventional tag]
    # Commit 1-3 are contained by v1.0.0 (earlier than v1.1.0).
    let c1 = (list --with-tag | where subject == "feat(ui): add picker" | first)
    assert equal $c1.tag "v1.0.0"
    # Commits 4-5 are not reachable from v1.0.0 but are reachable from v1.1.0.
    let c4 = (list --with-tag | where subject == "feat: rework auth" | first)
    assert equal $c4.tag "v1.1.0"
}

@test
def "with-tag yields null when no tag contains the commit" [] {
    cd $in.repo
    # Add a fresh commit on top of v1.1.0 — no tag will contain it.
    "z" | save -f z.txt
    ^git add z.txt
    ^git commit -q -m "feat: untagged"
    let row = (list --with-tag | where subject == "feat: untagged" | first)
    assert equal $row.tag null
}

@test
def "with-stats adds files_changed / insertions / deletions" [] {
    cd $in.repo
    let cols = (list --with-stats | columns)
    assert equal $cols [hash author date subject type scope breaking description body footers conventional files_changed insertions deletions]
    let row = (list --with-stats | last)  # the first commit added a single 1-byte file
    assert equal $row.files_changed 1
    assert equal $row.insertions 1
    assert equal $row.deletions 0
}

@test
def "with-changes buckets paths into added / modified / deleted" [] {
    cd $in.repo
    let cols = (list --with-changes | columns)
    assert equal $cols [hash author date subject type scope breaking description body footers conventional added modified deleted]
    # Every seeded commit adds a new file; none modify or delete.
    let row = (list --with-changes | where subject == "feat(ui): add picker" | first)
    assert equal $row.added ["a.txt"]
    assert equal $row.modified []
    assert equal $row.deleted []
}

@test
def "with-changes routes modify and delete actions to the right buckets" [] {
    cd $in.repo
    # Modify an existing file.
    "aa" | save -f a.txt
    ^git add a.txt
    ^git commit -q -m "chore: modify a"
    # Delete an existing file.
    ^git rm -q b.txt
    ^git commit -q -m "chore: drop b"
    let modify = (list --with-changes | where subject == "chore: modify a" | first)
    let drop = (list --with-changes | where subject == "chore: drop b" | first)
    assert equal $modify.modified ["a.txt"]
    assert equal $modify.added []
    assert equal $modify.deleted []
    assert equal $drop.deleted ["b.txt"]
    assert equal $drop.added []
    assert equal $drop.modified []
}

@test
def "combining flags produces the union of columns in stable order" [] {
    cd $in.repo
    let cols = (list --with-email --with-tag --with-stats --with-changes | columns)
    assert equal $cols [hash author author_email date subject type scope breaking description body footers conventional tag files_changed insertions deletions added modified deleted]
}

@test
def "default list without flags keeps the original 11-column shape" [] {
    cd $in.repo
    let cols = (list | columns)
    assert equal $cols [hash author date subject type scope breaking description body footers conventional]
}

@test
def "row order is preserved when par-each enrichment flags are set" [] {
    cd $in.repo
    let plain = (list | get hash)
    let decorated = (list --with-tag --with-stats --with-changes | get hash)
    assert equal $decorated $plain
}
