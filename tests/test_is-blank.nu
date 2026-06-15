use std/assert
use std/testing *
source ../mod.nu

# `is-blank` is a private helper sourced into this file.

# ---------- normal behaviour ----------

@test
def "empty string is blank" [] {
    assert equal ('' | is-blank) true
}

@test
def "single space is blank" [] {
    assert equal (' ' | is-blank) true
}

@test
def "tab-only string is blank" [] {
    assert equal ("\t" | is-blank) true
}

@test
def "newline-only string is blank" [] {
    assert equal ("\n" | is-blank) true
}

@test
def "mixed whitespace is blank" [] {
    assert equal ("  \t\n  " | is-blank) true
}

@test
def "non-empty content is not blank" [] {
    assert equal ('x' | is-blank) false
}

@test
def "padded content is not blank" [] {
    assert equal ('  hello  ' | is-blank) false
}

@test
def "content with embedded whitespace is not blank" [] {
    assert equal ("a\tb" | is-blank) false
}

# ---------- works in closure positions ----------

@test
def "composes with skip while" [] {
    let r = (['' '  ' "\t" 'x' 'y' ''] | skip while { is-blank })
    assert equal $r ['x' 'y' '']
}

@test
def "composes with where" [] {
    let r = (['a' '' 'b' '  ' 'c'] | where {|s| not ($s | is-blank)})
    assert equal $r ['a' 'b' 'c']
}
