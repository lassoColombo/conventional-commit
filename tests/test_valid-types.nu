use std/assert
use std/testing *
use ../mod.nu *

# ---------- default ----------

@test
def "is unrestricted by default" [] {
    assert equal (valid-types) []
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
def "empty-string env var means unrestricted" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: ""} {
        assert equal (valid-types) []
    }
}

# ---------- usage shape ----------

@test
def "a configured policy is a flat list of strings" [] {
    with-env {CONVENTIONAL_COMMIT_VALID_TYPES: [feat fix]} {
        assert equal (valid-types | describe) "list<string>"
    }
}
