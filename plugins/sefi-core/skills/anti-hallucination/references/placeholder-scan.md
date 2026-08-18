# Placeholder Scan -- interpreting scan-placeholders.sh hits

`${CLAUDE_PLUGIN_ROOT}/scripts/scan-placeholders.sh` is a deterministic post-hoc scan across 4 categories. It
always exits 0 and reports hit counts on stderr; it is evidence for a verdict, never a
verdict itself. Read the matched lines, not just the count -- a category name tells you
where to look, not what to conclude.

## Reading a hit, per category

**uncertain_language** -- a hedge word attached to a claim the output asserts as fact
("this probably works") is the actual defect: verify-before-cite failed. The SAME word
inside a sentence explaining *why* something is uncertain ("I could not verify this,
so I am marking it UNKNOWN because I only think the endpoint accepts POST") is the
discipline working correctly, not a violation -- read the surrounding sentence before
judging.

**incomplete_implementation** -- a `TODO:`/`FIXME:`/`HACK:` left in delivered code is
almost never a false positive: it is a marker the author left for exactly this scan to
find. The narrow exception is a `TODO:` inside a comment explaining a DELIBERATE, cited
follow-up already logged elsewhere (e.g. an `inbox/` entry) -- confirm the citation exists
before treating it as acceptable; an uncited "later" is still incomplete.

**placeholder_content** -- `lorem ipsum`, `your_api_key_here`, and `xxx`/`aaa`/`zzz` runs
are near-zero false-positive: real prose does not produce these by accident. `placeholder`
as a bare word has one legitimate reading -- a sentence discussing the concept of a
placeholder (e.g. documentation ABOUT this very scan) -- distinguishable by whether the
surrounding sentence is describing template material or describing the word itself.

**test_urls** -- `example.com`/`localhost`/`127.0.0.1` appearing in delivered output is a
real defect UNLESS the deliverable is itself documentation about testing or local
development, where naming a test URL is the correct content, not a leaked placeholder.

## What a hit is not

A hit is not an automatic REJECT. The qa-engineer judges it against the plan's Done
Criteria the same way it judges every other finding -- severity-labeled (Critical /
Important / Minor per qa-engineer.md item 8), never praised away, never auto-failed either.
A category with zero hits is not proof of a clean deliverable; it means these 4 specific
pattern families were not found, nothing more.

See the anti-hallucination skill's own rule for what this scan is the detection-side
counterpart to (prevention: verify-before-cite; detection: this scan).
