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
def "accepts the common Angular types out of the box" [] {
    for t in [feat fix docs style refactor perf test build ci chore revert] {
        assert equal ($"($t): x" | is-conventional) true
    }
}

@test
def "accepts arbitrary types by default" [] {
    # With no `valid-types` policy, any letter-only type is conventional,
    # matching the spec — it reserves meaning only for feat/fix (rule 14).
    assert equal ('wip: stuff' | is-conventional) true
    assert equal ('hotfix: it' | is-conventional) true
}

@test
def "rejects types outside the configured whitelist" [] {
    # Once `valid-types` is set, the parser enforces it — out-of-policy
    # types become non-conventional.
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: [feat fix]} {
        assert equal ('wip: stuff' | is-conventional) false
        assert equal ('hotfix: it' | is-conventional) false
    }
}

@test
def "env override widens what counts as conventional" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: [wip hotfix]} {
        assert equal ('wip: stuff' | is-conventional) true
        assert equal ('hotfix: it' | is-conventional) true
        # And NARROWS — `feat` is no longer in the configured set.
        assert equal ('feat: x' | is-conventional) false
    }
}

@test
def "env override is honored from a CSV string too" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "wip, hotfix"} {
        assert equal ('wip: stuff' | is-conventional) true
        assert equal ('feat: x' | is-conventional) false
    }
}

@test
def "type match is case-insensitive per spec rule 15" [] {
    assert equal ('FIX: typo' | is-conventional) true
    assert equal ('Feat: stuff' | is-conventional) true
    assert equal ('fEaT(ui): mixed case' | is-conventional) true
}

@test
def "case-insensitive matching applies to env-set types too" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: [wip]} {
        assert equal ('WIP: x' | is-conventional) true
        assert equal ('Wip(api): x' | is-conventional) true
    }
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
