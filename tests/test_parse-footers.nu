use std/assert
use std/testing *
source ../mod.nu

# `parse-footers` turns already-identified footer-block lines into a
# table of {token, value} records. It is private — sourced here.

# ---------- empty / single ----------

@test
def "empty input yields empty list" [] {
    assert equal (parse-footers []) []
}

@test
def "single footer with colon-space separator" [] {
    assert equal (parse-footers ['Refs: 42']) [{token: "Refs", value: "42"}]
}

@test
def "single footer with space-hash separator" [] {
    assert equal (parse-footers ['Refs #42']) [{token: "Refs", value: "42"}]
}

# ---------- multiple footers ----------

@test
def "multiple footers in order" [] {
    let out = (parse-footers ['Refs: 42' 'Reviewed-by: alice' 'Acked-by: bob'])
    assert equal ($out | length) 3
    assert equal $out.0 {token: "Refs", value: "42"}
    assert equal $out.1 {token: "Reviewed-by", value: "alice"}
    assert equal $out.2 {token: "Acked-by", value: "bob"}
}

@test
def "preserves both separator styles in one block" [] {
    let out = (parse-footers ['Refs #42' 'Reviewed-by: alice'])
    assert equal $out.0.value "42"
    assert equal $out.1.value "alice"
}

# ---------- BREAKING (rules 11, 12, 16) ----------

@test
def "captures BREAKING CHANGE as a single token with embedded space" [] {
    assert equal (parse-footers ['BREAKING CHANGE: drop /v1']) [{token: "BREAKING CHANGE", value: "drop /v1"}]
}

@test
def "captures BREAKING-CHANGE hyphen variant" [] {
    assert equal (parse-footers ['BREAKING-CHANGE: yep']) [{token: "BREAKING-CHANGE", value: "yep"}]
}

@test
def "lowercase 'breaking change' is NOT recognised as the special token" [] {
    # The regex only allows letters + digits + `-` for non-BREAKING tokens,
    # so 'breaking change: x' has a space in the token, doesn't match the
    # generic alternation, and (since no previous footer exists) drops.
    assert equal (parse-footers ['breaking change: x']) []
}

# ---------- continuation lines (rule 10) ----------

@test
def "appends continuation lines to the previous footer value" [] {
    let out = (parse-footers ['Refs: a' '  continuation'])
    assert equal $out [{token: "Refs", value: "a\n  continuation"}]
}

@test
def "multiple continuation lines stack up" [] {
    let out = (parse-footers ['Refs: a' '  c1' '  c2' '  c3'])
    assert equal $out.0.value "a\n  c1\n  c2\n  c3"
}

@test
def "continuation only attaches to the most recent footer" [] {
    let out = (parse-footers ['Refs: a' '  c1' 'Reviewed-by: bob' '  c2'])
    assert equal ($out | length) 2
    assert equal $out.0.value "a\n  c1"
    assert equal $out.1.value "bob\n  c2"
}

@test
def "leading non-footer lines are dropped when there is no previous footer" [] {
    # Without a previous footer to attach to, a non-matching line cannot
    # become a continuation, so it is silently discarded.
    let out = (parse-footers ['orphan continuation' 'Refs: 42'])
    assert equal $out [{token: "Refs", value: "42"}]
}

@test
def "token with hyphen and digits is accepted" [] {
    let out = (parse-footers ['Co-authored-by-2: someone'])
    assert equal $out.0.token "Co-authored-by-2"
}

# ---------- empty values ----------

@test
def "footer with empty value is captured" [] {
    # The regex's `(?P<value>.*)$` matches the empty string.
    assert equal (parse-footers ['Refs: ']) [{token: "Refs", value: ""}]
}

# ---------- non-matching lines mid-stream ----------

@test
def "a non-footer-shaped line that does not match becomes a continuation" [] {
    # The footer regex requires a `: ` or ` #` separator. A bare word
    # following a footer is treated as a continuation, per rule 10.
    let out = (parse-footers ['Refs: 42' 'Just some text'])
    assert equal $out [{token: "Refs", value: "42\nJust some text"}]
}
