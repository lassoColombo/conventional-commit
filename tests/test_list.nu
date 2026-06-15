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

    # Commit 4 — breaking via BREAKING CHANGE footer
    "d" | save -f d.txt
    ^git add d.txt
    ^git commit -q -m "feat: rework auth

BREAKING CHANGE: legacy clients must upgrade"

    # Commit 5 — non-conventional
    "e" | save -f e.txt
    ^git add e.txt
    ^git commit -q -m "hello world"

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
    assert equal ($l | columns) [hash author date subject kind scope breaking description body footers conventional]
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
    assert equal $row.kind "feat"
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
    let row = (list | where kind == "fix" | first)
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
    assert equal $row.kind null
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
    # Append a commit whose body contains a literal \x1f. The `--number 4`
    # cap on the split should keep the bytes inside the `body` field.
    "f" | save -f f.txt
    ^git add f.txt
    let payload = $"feat: extra(char nul)body has (char us) inside"
    # ^^ can't pass NUL via -m, use here-doc instead
    let msg = $"feat: extra\n\nbody has (char us) inside"
    $msg | ^git commit -q -F -
    let row = (list | where subject == "feat: extra" | first)
    assert str contains $row.body "inside"
    assert equal $row.kind "feat"
}
