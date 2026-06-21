use std/assert
use std/testing *
source ../mod.nu

# `decode-footers` turns already-identified footer-block lines into a
# table of {token, sep, value} records, where `sep` is the literal
# separator (`: ` or ` #`). It is private — sourced here.

# ---------- empty / single ----------

@test
def "empty input yields empty list" [] {
    assert equal (decode-footers []) []
}

@test
def "single footer with colon-space separator" [] {
    assert equal (decode-footers ['Refs: 42']) [{token: "Refs", sep: ": ", value: "42"}]
}

@test
def "single footer with space-hash separator" [] {
    assert equal (decode-footers ['Refs #42']) [{token: "Refs", sep: " #", value: "42"}]
}

# ---------- multiple footers ----------

@test
def "multiple footers in order" [] {
    let out = (decode-footers ['Refs: 42' 'Reviewed-by: alice' 'Acked-by: bob'])
    assert equal ($out | length) 3
    assert equal $out.0 {token: "Refs", sep: ": ", value: "42"}
    assert equal $out.1 {token: "Reviewed-by", sep: ": ", value: "alice"}
    assert equal $out.2 {token: "Acked-by", sep: ": ", value: "bob"}
}

@test
def "preserves both separator styles in one block" [] {
    let out = (decode-footers ['Refs #42' 'Reviewed-by: alice'])
    assert equal $out.0 {token: "Refs", sep: " #", value: "42"}
    assert equal $out.1 {token: "Reviewed-by", sep: ": ", value: "alice"}
}

# ---------- BREAKING (rules 11, 12, 16) ----------

@test
def "captures BREAKING CHANGE as a single token with embedded space" [] {
    assert equal (decode-footers ['BREAKING CHANGE: drop /v1']) [{token: "BREAKING CHANGE", sep: ": ", value: "drop /v1"}]
}

@test
def "captures BREAKING-CHANGE hyphen variant" [] {
    assert equal (decode-footers ['BREAKING-CHANGE: yep']) [{token: "BREAKING-CHANGE", sep: ": ", value: "yep"}]
}

@test
def "lowercase 'breaking change' is NOT recognised as the special token" [] {
    # The regex only allows letters + digits + `-` for non-BREAKING tokens,
    # so 'breaking change: x' has a space in the token, doesn't match the
    # generic alternation, and (since no previous footer exists) drops.
    assert equal (decode-footers ['breaking change: x']) []
}

# ---------- continuation lines (rule 10) ----------

@test
def "appends continuation lines to the previous footer value" [] {
    let out = (decode-footers ['Refs: a' '  continuation'])
    assert equal $out [{token: "Refs", sep: ": ", value: "a\n  continuation"}]
}

@test
def "multiple continuation lines stack up" [] {
    let out = (decode-footers ['Refs: a' '  c1' '  c2' '  c3'])
    assert equal $out.0.value "a\n  c1\n  c2\n  c3"
}

@test
def "continuation only attaches to the most recent footer" [] {
    let out = (decode-footers ['Refs: a' '  c1' 'Reviewed-by: bob' '  c2'])
    assert equal ($out | length) 2
    assert equal $out.0.value "a\n  c1"
    assert equal $out.1.value "bob\n  c2"
}

@test
def "leading non-footer lines are dropped when there is no previous footer" [] {
    # Without a previous footer to attach to, a non-matching line cannot
    # become a continuation, so it is silently discarded.
    let out = (decode-footers ['orphan continuation' 'Refs: 42'])
    assert equal $out [{token: "Refs", sep: ": ", value: "42"}]
}

@test
def "token with hyphen and digits is accepted" [] {
    let out = (decode-footers ['Co-authored-by-2: someone'])
    assert equal $out.0.token "Co-authored-by-2"
}

# ---------- empty values ----------

@test
def "footer with empty value is captured" [] {
    # The regex's `(?P<value>.*)$` matches the empty string.
    assert equal (decode-footers ['Refs: ']) [{token: "Refs", sep: ": ", value: ""}]
}

# ---------- non-matching lines mid-stream ----------

@test
def "a non-footer-shaped line that does not match becomes a continuation" [] {
    # The footer regex requires a `: ` or ` #` separator. A bare word
    # following a footer is treated as a continuation, per rule 10.
    let out = (decode-footers ['Refs: 42' 'Just some text'])
    assert equal $out [{token: "Refs", sep: ": ", value: "42\nJust some text"}]
}
