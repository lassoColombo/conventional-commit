use std/assert
use std/testing *
use ../mod.nu *

# ---------- default ----------

@test
def "returns the Angular convention by default" [] {
    assert equal (valid-types) [feat fix docs style refactor perf test build ci chore revert]
}

# ---------- env override ----------

@test
def "respects a list-shaped env override" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: [feat fix chore]} {
        assert equal (valid-types) [feat fix chore]
    }
}

@test
def "respects a comma-separated string env override" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "feat,fix,chore"} {
        assert equal (valid-types) [feat fix chore]
    }
}

@test
def "respects a space-separated string env override" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "feat fix chore"} {
        assert equal (valid-types) [feat fix chore]
    }
}

@test
def "tolerates mixed whitespace and commas in the string form" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: "  feat,  fix ,chore  perf "} {
        assert equal (valid-types) [feat fix chore perf]
    }
}

@test
def "empty-string env var falls back to the default" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: ""} {
        assert equal (valid-types) [feat fix docs style refactor perf test build ci chore revert]
    }
}

# ---------- usage shape ----------

@test
def "result is a flat list of strings" [] {
    let t = valid-types
    assert equal ($t | describe) "list<string>"
}
