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
    assert equal ({type: feat, scope: api, breaking: true, bang: true, description: "drop /v1"} | encode) "feat(api)!: drop /v1"
}

# ---------- breaking signals: bang emits the `!`, footer alone does not ----------

@test
def "the ! comes from bang, not from a breaking footer" [] {
    # Breaking via the footer alone — bang false, so no `!` in the header.
    let r = {type: feat, description: "x", breaking: true, footers: [{token: "BREAKING CHANGE", sep: ": ", value: "y"}]}
    assert equal ($r | encode) "feat: x\n\nBREAKING CHANGE: y"
}

@test
def "round-trips a ! marker alongside a BREAKING CHANGE footer" [] {
    # `bang` is captured and reproduced, so this keeps both signals.
    let msg = "feat!: x\n\nBREAKING CHANGE: y"
    assert equal ($msg | decode | encode) $msg
}

# ---------- breaking consistency guard ----------

@test
def "errors when breaking is true but there is no bang and no footer" [] {
    assert error { {type: feat, breaking: true, description: "x"} | encode }
}

@test
def "errors when bang is set but breaking is false" [] {
    assert error { {type: feat, breaking: false, bang: true, description: "x"} | encode }
}

@test
def "errors when a breaking footer is present but breaking is false" [] {
    let r = {type: feat, breaking: false, description: "x", footers: [{token: "BREAKING CHANGE", sep: ": ", value: "y"}]}
    assert error { $r | encode }
}

@test
def "round-trips every decoded record through the guard" [] {
    # Whatever decode produces is internally consistent, so it never trips
    # the guard — exercised across all four breaking/bang/footer combinations.
    for msg in [
        "feat: plain"
        "feat!: header bang only"
        "feat: footer only\n\nBREAKING CHANGE: y"
        "feat!: both\n\nBREAKING CHANGE: y"
    ] {
        assert equal ($msg | decode | encode) $msg
    }
}

# ---------- required components (conventional path) ----------

@test
def "errors when type is missing on the conventional path" [] {
    # subject is ignored when conventional; without type there's nothing to build.
    assert error { {subject: "hello world"} | encode }
}

@test
def "errors when description is missing" [] {
    assert error { {type: feat} | encode }
}

@test
def "ignores subject entirely on the conventional path" [] {
    # A stale/contradicting subject must not leak into the output.
    let r = {type: feat, scope: api, description: "retry on 503", subject: "fix(server): retry on 503"}
    assert equal ($r | encode) "feat(api): retry on 503"
}

# ---------- non-conventional path (conventional: false) ----------

@test
def "emits the raw subject when conventional is false" [] {
    assert equal ({conventional: false, subject: "hello world"} | encode) "hello world"
}

@test
def "round-trips a non-conventional message" [] {
    let msg = "hello world\n\nsome body"
    assert equal ($msg | decode | encode) $msg
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
