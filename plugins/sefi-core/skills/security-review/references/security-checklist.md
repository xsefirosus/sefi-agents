# Security Checklist -- expanded per-surface detail

Read on demand by the security-review skill. One section per surface; each item is a
yes/no check against the diff.

## Secrets and credentials
- No hardcoded API keys, tokens, passwords, or connection strings (grep the diff for
  key-like entropy and known prefixes: AKIA, ghp_, sk-, xox, -----BEGIN).
- Fixtures and examples use obvious placeholders ($AGENT_API_KEY, changeme).
- Nothing secret-shaped is echoed to logs, error messages, or CI output.
- .gitignore covers local env files before any is created.

## Injection surfaces
- Shell: user input reaches a shell only via argument arrays or is strictly validated;
  no string-built commands from external data.
- SQL/queries: parameterized statements only; string concatenation into a query is a
  finding regardless of current input source.
- Templates: autoescape on; raw/safe markers on external data are findings.
- Deserialization: no pickle/marshal/yaml.load (unsafe loader) on untrusted bytes.
- Paths: user-supplied paths are resolved and prefix-checked before use.

## Transport and process
- TLS verification never disabled (verify=False, InsecureSkipVerify, -k).
- Downloads that execute are pinned (checksum or version), never curl | sh unpinned.
- Child processes inherit a minimal environment, not the parent's secrets.

## Dependencies
- New dep: name, license, what it replaces, why minimization-ladder rungs 2-5 fail.
- Pinned version or lockfile updated; no floating "latest".
- Install scripts (postinstall) reviewed for network or filesystem writes.

## Authorization and data
- Changed handlers keep permission checks; a removed check is Critical until justified.
- New logging reviewed for PII; vault writes pass the privacy filter (strip secrets and
  <private>...</private> blocks).
- Test data contains no real personal data.

## For this repo specifically
- Shell scripts keep set -euo pipefail and quote expansions.
- Hook-injected content stays under the 1,500-char cap (a hook is an injection surface
  into the model's context).
- Loop-consumed inbox items are validated as repo-local paths before acting.
