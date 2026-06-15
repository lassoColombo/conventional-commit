use std/assert
use std/testing *
source ../mod.nu

# `kinds` is private — sourced into this file's scope so we can call it.

@test
def "returns the Angular convention list" [] {
    assert equal (kinds) [feat fix perf refactor revert test ci build docs style chore]
}

@test
def "is a non-empty list of strings" [] {
    let k = (kinds)
    assert greater ($k | length) 0
    let types = ($k | each { describe } | uniq)
    assert equal $types ["string"]
}

@test
def "every entry is lowercase" [] {
    let k = (kinds)
    let lowered = ($k | each { str downcase })
    assert equal $k $lowered
}

@test
def "has no duplicates" [] {
    let k = (kinds)
    assert equal ($k | length) ($k | uniq | length)
}

@test
def "every entry passes is-conventional" [] {
    # Every recommended kind is, by construction, also a valid spec kind.
    for k in (kinds) {
        assert equal ($"($k): x" | is-conventional) true
    }
}
