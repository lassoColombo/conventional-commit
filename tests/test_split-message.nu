use std/assert
use std/testing *
source ../mod.nu

# `split-message` partitions a raw commit message into
# {subject, body, footer_lines}. It is private — sourced into this file.

# ---------- empty / single-line inputs ----------

@test
def "empty input gives empty subject and no body" [] {
    let s = (split-message '')
    assert equal $s.subject ''
    assert equal $s.body null
    assert equal $s.footer_lines []
}

@test
def "single-line message has no body and no footers" [] {
    let s = (split-message 'feat: x')
    assert equal $s.subject 'feat: x'
    assert equal $s.body null
    assert equal $s.footer_lines []
}

# ---------- blank-line gate (rule 6) ----------

@test
def "missing blank line after subject means subject-only" [] {
    let s = (split-message "feat: x\nimmediately after")
    assert equal $s.subject 'feat: x'
    assert equal $s.body null
    assert equal $s.footer_lines []
}

@test
def "blank line followed by content yields a body" [] {
    let s = (split-message "feat: x\n\nbody here")
    assert equal $s.subject 'feat: x'
    assert equal $s.body 'body here'
    assert equal $s.footer_lines []
}

@test
def "multiple blank lines between subject and body are tolerated" [] {
    let s = (split-message "feat: x\n\n\n\nbody")
    assert equal $s.body 'body'
}

@test
def "trailing blank lines are stripped" [] {
    let s = (split-message "feat: x\n\nbody\n\n\n")
    assert equal $s.body 'body'
}

@test
def "subject + only blank lines collapses to subject-only" [] {
    let s = (split-message "feat: x\n\n\n\n")
    assert equal $s.body null
    assert equal $s.footer_lines []
}

# ---------- body composition ----------

@test
def "joins multi-paragraph body with double newline" [] {
    let s = (split-message "feat: x\n\npara 1\n\npara 2\n\npara 3")
    assert equal $s.body "para 1\n\npara 2\n\npara 3"
}

@test
def "keeps multi-line paragraphs intact" [] {
    let s = (split-message "feat: x\n\nline a\nline b\n\npara 2")
    assert equal $s.body "line a\nline b\n\npara 2"
}

@test
def "whitespace-only lines act as paragraph separators" [] {
    let s = (split-message "feat: x\n\npara 1\n   \npara 2")
    assert equal $s.body "para 1\n\npara 2"
}

# ---------- footer detection ----------

@test
def "trailing footer-shaped paragraph is captured as footer_lines, not body" [] {
    let s = (split-message "feat: x\n\nbody\n\nRefs: 42\nReviewed-by: alice")
    assert equal $s.body 'body'
    assert equal $s.footer_lines ['Refs: 42' 'Reviewed-by: alice']
}

@test
def "footers without a body returns null body" [] {
    let s = (split-message "feat: x\n\nRefs: 42")
    assert equal $s.body null
    assert equal $s.footer_lines ['Refs: 42']
}

@test
def "BREAKING CHANGE footer is detected" [] {
    let s = (split-message "feat: x\n\nBREAKING CHANGE: drop /v1")
    assert equal $s.footer_lines ['BREAKING CHANGE: drop /v1']
}

@test
def "last paragraph without a footer-shaped first line is treated as body" [] {
    let s = (split-message "feat: x\n\nbody\n\nclosing remark not a footer")
    assert equal $s.body "body\n\nclosing remark not a footer"
    assert equal $s.footer_lines []
}

@test
def "space-hash footer separator is detected" [] {
    let s = (split-message "feat: x\n\nRefs #42")
    assert equal $s.footer_lines ['Refs #42']
}

@test
def "footer block carries continuation lines forward" [] {
    # `split-message` captures raw footer lines; continuation handling
    # is the job of `parse-footers`.
    let s = (split-message "feat: x\n\nRefs: a\n  continuation\nReviewed-by: bob")
    assert equal $s.footer_lines ['Refs: a' '  continuation' 'Reviewed-by: bob']
}

# ---------- preserves the raw subject ----------

@test
def "does not parse or rewrite the subject" [] {
    let s = (split-message "FIX(API)!: typo\n\nbody")
    assert equal $s.subject "FIX(API)!: typo"
}

@test
def "non-conventional subject is still split correctly" [] {
    let s = (split-message "not a commit\n\nbody\n\nRefs: 1")
    assert equal $s.subject "not a commit"
    assert equal $s.body "body"
    assert equal $s.footer_lines ['Refs: 1']
}
