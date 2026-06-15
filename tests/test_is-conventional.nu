use std/assert
use std/testing *
use ../mod.nu *

# ---------- normal behaviour ----------

@test
def "accepts feat with description" [] {
    assert equal ('feat: add picker' | is-conventional) true
}

@test
def "accepts type with scope" [] {
    assert equal ('feat(ui): add picker' | is-conventional) true
}

@test
def "accepts type with ! breaking marker" [] {
    assert equal ('feat!: drop /v1' | is-conventional) true
}

@test
def "accepts type with scope and ! breaking marker" [] {
    assert equal ('feat(api)!: drop /v1' | is-conventional) true
}

@test
def "accepts any letter-only type per spec rule 14" [] {
    # The parser does NOT restrict to the Angular set.
    assert equal ('wip: stuff' | is-conventional) true
    assert equal ('hotfix: it' | is-conventional) true
    assert equal ('chore: bump' | is-conventional) true
}

@test
def "type match is case-insensitive per spec rule 15" [] {
    assert equal ('FIX: typo' | is-conventional) true
    assert equal ('Feat: stuff' | is-conventional) true
    assert equal ('fEaT(ui): mixed case' | is-conventional) true
}

# ---------- edge cases ----------

@test
def "rejects non-conformant subject" [] {
    assert equal ('wip stuff' | is-conventional) false
}

@test
def "rejects empty input" [] {
    assert equal ('' | is-conventional) false
}

@test
def "rejects type with digits per spec letter-only rule" [] {
    assert equal ('feat2: x' | is-conventional) false
}

@test
def "rejects missing space after colon" [] {
    # The spec requires `: ` followed by a description.
    assert equal ('feat:no-space' | is-conventional) false
}

@test
def "rejects empty description after colon-space" [] {
    assert equal ('feat: ' | is-conventional) false
}

@test
def "rejects empty scope" [] {
    # `(?P<scope>[^)]+)` requires at least one char inside parens.
    assert equal ('feat(): x' | is-conventional) false
}

@test
def "rejects missing colon entirely" [] {
    assert equal ('feat add picker' | is-conventional) false
}

@test
def "rejects type prefixed with whitespace" [] {
    assert equal (' feat: x' | is-conventional) false
}

@test
def "only the first line is inspected" [] {
    # A valid first line wins regardless of garbage body.
    assert equal ("feat: x\nwhatever\nrandom" | is-conventional) true
}

@test
def "non-conformant subject is not rescued by BREAKING CHANGE footer" [] {
    assert equal ("wip\n\nBREAKING CHANGE: ignored" | is-conventional) false
}

@test
def "scope can contain hyphens, slashes, dots and spaces" [] {
    # The regex permits any non-`)` chars inside parens.
    assert equal ('feat(some/long.scope-name v2): x' | is-conventional) true
}
