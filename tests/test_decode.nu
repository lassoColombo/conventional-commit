use std/assert
use std/testing *
use ../mod.nu *

# ---------- normal behaviour: subject extraction ----------

@test
def "extracts kind, scope and description" [] {
    let p = ('feat(ui): add picker' | decode)
    assert equal $p.kind "feat"
    assert equal $p.scope "ui"
    assert equal $p.description "add picker"
}

@test
def "lowercases the kind" [] {
    assert equal ('FIX: typo' | decode | get kind) "fix"
    assert equal ('Feat: stuff' | decode | get kind) "feat"
}

@test
def "scope is null when absent" [] {
    let p = ('feat: x' | decode)
    assert equal $p.scope null
}

@test
def "subject-only commit has null body and empty footers" [] {
    let p = ('feat(ui): add picker' | decode)
    assert equal $p.body null
    assert equal $p.footers []
}

@test
def "conventional flag is true for valid subject" [] {
    assert equal ('feat: x' | decode | get conventional) true
}

@test
def "raw subject is preserved verbatim" [] {
    let p = ('FIX(API)!: typo' | decode)
    assert equal $p.subject "FIX(API)!: typo"
}

# ---------- breaking flag ----------

@test
def "sets breaking when ! is in the prefix" [] {
    assert equal ('feat!: x' | decode | get breaking) true
    assert equal ('feat(api)!: x' | decode | get breaking) true
}

@test
def "sets breaking from BREAKING CHANGE footer" [] {
    let p = ("feat: x\n\nBREAKING CHANGE: drop /v1" | decode)
    assert equal $p.breaking true
}

@test
def "sets breaking from BREAKING-CHANGE hyphen variant" [] {
    let p = ("feat: x\n\nBREAKING-CHANGE: yep" | decode)
    assert equal $p.breaking true
}

@test
def "breaking is true when ! and footer both present" [] {
    let p = ("feat!: x\n\nBREAKING CHANGE: yep" | decode)
    assert equal $p.breaking true
}

@test
def "breaking is false without ! or BREAKING footer" [] {
    assert equal ('feat: x' | decode | get breaking) false
    assert equal ("feat: x\n\nbody\n\nRefs: 1" | decode | get breaking) false
}

@test
def "lowercase 'breaking change:' in a footer does NOT trip the flag" [] {
    # Spec rule 16: only the uppercase synonyms count as breaking footers.
    let p = ("feat: x\n\nbreaking change: nope" | decode)
    assert equal $p.breaking false
}

# ---------- body ----------

@test
def "body requires a blank line after the subject" [] {
    let p = ("feat: x\nbody here" | decode)
    assert equal $p.body null
}

@test
def "joins body paragraphs with double newline" [] {
    let p = ("feat: x\n\npara 1\n\npara 2" | decode)
    assert equal $p.body "para 1\n\npara 2"
}

@test
def "keeps multi-line paragraphs intact" [] {
    let p = ("feat: x\n\nline a\nline b\n\npara 2" | decode)
    assert equal $p.body "line a\nline b\n\npara 2"
}

@test
def "strips trailing blank lines" [] {
    let p = ("feat: x\n\nbody\n\n\n" | decode)
    assert equal $p.body "body"
}

@test
def "body is null when only footers follow the blank line" [] {
    let p = ("feat: x\n\nRefs: 1" | decode)
    assert equal $p.body null
    assert equal ($p.footers | length) 1
}

@test
def "whitespace-only lines are treated as blank for paragraph splitting" [] {
    let p = ("feat: x\n\npara 1\n   \npara 2" | decode)
    assert equal $p.body "para 1\n\npara 2"
}

# ---------- footers ----------

@test
def "collects footers with colon-space separator" [] {
    let p = ("feat: x\n\nbody\n\nRefs: 42\nReviewed-by: alice" | decode)
    assert equal ($p.footers | length) 2
    assert equal $p.footers.0 {token: "Refs", value: "42"}
    assert equal $p.footers.1 {token: "Reviewed-by", value: "alice"}
}

@test
def "collects footers with space-hash separator" [] {
    let p = ("feat: x\n\nbody\n\nRefs #42" | decode)
    assert equal $p.footers.0 {token: "Refs", value: "42"}
}

@test
def "mixes separator styles in one footer block" [] {
    let p = ("feat: x\n\nRefs #42\nReviewed-by: alice" | decode)
    assert equal ($p.footers | length) 2
    assert equal $p.footers.0.value "42"
    assert equal $p.footers.1.value "alice"
}

@test
def "appends non-footer-shaped lines to the previous footer per rule 10" [] {
    let p = ("feat: x\n\nRefs: a\n  continuation\nReviewed-by: bob" | decode)
    assert equal $p.footers.0.value "a\n  continuation"
    assert equal $p.footers.1.token "Reviewed-by"
}

@test
def "footer-shaped line without a blank line above is NOT a footer" [] {
    # Without the blank line separator, the whole message is subject-only.
    let p = ("feat: x\nfoo: bar" | decode)
    assert equal $p.body null
    assert equal ($p.footers | length) 0
}

@test
def "BREAKING CHANGE footer survives in the footers table" [] {
    let p = ("feat: x\n\nBREAKING CHANGE: drop /v1" | decode)
    assert equal $p.footers.0 {token: "BREAKING CHANGE", value: "drop /v1"}
}

# ---------- shape preservation ----------

@test
def "non-conventional input keeps the same record shape" [] {
    let p = ('hello world' | decode)
    assert equal ($p | columns) [kind scope breaking subject description body footers conventional]
    assert equal $p.kind null
    assert equal $p.scope null
    assert equal $p.breaking false
    assert equal $p.subject "hello world"
    assert equal $p.description null
    assert equal $p.body null
    assert equal $p.footers []
    assert equal $p.conventional false
}

@test
def "empty input keeps the same record shape" [] {
    let p = ('' | decode)
    assert equal $p.subject ""
    assert equal $p.kind null
    assert equal $p.conventional false
    assert equal $p.body null
    assert equal $p.footers []
}

@test
def "non-conventional subject + body shape" [] {
    # Body parsing still applies even when the subject is non-conformant.
    let p = ("not a commit\n\nsome body" | decode)
    assert equal $p.conventional false
    assert equal $p.body "some body"
}

@test
def "conventional record has all expected fields" [] {
    let p = ('feat: x' | decode)
    assert equal ($p | columns) [kind scope breaking subject description body footers conventional]
}
