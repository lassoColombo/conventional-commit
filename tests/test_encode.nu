use std/assert
use std/testing *
use ../mod.nu *

# ---------- basic rendering ----------

@test
def "renders type and description" [] {
    assert equal ({type: feat, description: "add picker"} | encode) "feat: add picker"
}

@test
def "wraps scope in parens" [] {
    assert equal ({type: fix, scope: api, description: "retry on 503"} | encode) "fix(api): retry on 503"
}

@test
def "adds bang for a breaking change" [] {
    assert equal ({type: feat, scope: api, breaking: true, description: "drop /v1"} | encode) "feat(api)!: drop /v1"
}

# ---------- non-conventional ----------

@test
def "emits the raw subject when type is missing" [] {
    assert equal ({subject: "hello world"} | encode) "hello world"
}

@test
def "requires a description when type is set" [] {
    assert error { {type: feat} | encode }
}

# ---------- round-trip ----------

@test
def "round-trips a canonical subject" [] {
    assert equal ('feat(ui): add picker' | decode | encode) "feat(ui): add picker"
}

@test
def "round-trips a space-hash footer separator" [] {
    let msg = "fix: x\n\nCloses #42"
    assert equal ($msg | decode | encode) $msg
}

@test
def "round-trips mixed footer separators" [] {
    let msg = "fix: x\n\nCloses #42\nReviewed-by: alice"
    assert equal ($msg | decode | encode) $msg
}

@test
def "a footer record without a sep field defaults to colon-space" [] {
    let r = {type: fix, description: "x", footers: [{token: "Refs", value: "42"}]}
    assert equal ($r | encode) "fix: x\n\nRefs: 42"
}

# ---------- valid-types policy ----------

@test
def "emits any type when no policy is configured" [] {
    assert equal ({type: wip, description: "stuff"} | encode) "wip: stuff"
}

@test
def "emits an in-policy type when a policy is configured" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "feat fix"} {
        assert equal ({type: feat, description: "x"} | encode) "feat: x"
    }
}

@test
def "errors on an out-of-policy type when a policy is configured" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "feat fix"} {
        assert error { {type: wip, description: "stuff"} | encode }
    }
}

@test
def "policy check is case-insensitive" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "feat fix"} {
        assert equal ({type: FEAT, description: "x"} | encode) "FEAT: x"
    }
}
