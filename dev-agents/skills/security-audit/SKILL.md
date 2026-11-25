---
name: security-audit
description: >-
  Read-only vulnerability and security-hardening audit protocol for Rust,
  TypeScript, and Luau/Lua projects covering dependency advisories, unsafe/escape
  hatches, secrets, injection, crypto, auth, DoS, network/filesystem hardening,
  supply-chain trust, and verification gates. Loaded by security-analyst and
  security-maintenance; invoked directly via /security-audit [focus], delegates
  to a background security-analyst.
---

# Security Audit Protocol

You are performing a **read-only** security and vulnerability audit. Do NOT modify source files, manifests, or lockfiles. Identify vulnerabilities and file GitHub issues for findings. Fixes happen in a separate remediation session.

Default focus: `full` (or the focus argument passed by the user/caller).

## Direct Invocation

This protocol is loaded at startup by `security-analyst` (which runs the audit) and by `security-maintenance` (which uses it as the vulnerability catalogue while fixing). When invoked directly (`/security-audit`) in a session that is **neither** of those agents, delegate it via `invoke_subagent` so findings — not tool noise — land in the conversation:

```text
invoke_subagent(
  TypeName: "security-analyst",
  Role: "security-analyst — security audit",
  Prompt: "Read the security-audit skill (SKILL.md) and run it end to end with focus: <focus>. Report findings and filed issue URLs; do not modify source files."
)
```

End your turn to wait for the subagent's report. If you **are** `security-analyst`, continue with the protocol below. If you are `security-maintenance`, read the protocol as the catalogue of vectors to check and prove closed; do not file audit issues from it.

## Language Profile (MANDATORY)

This protocol is language-neutral. For every profile detected by the `stack` skill, apply `../stack/references/<profile>/security-audit.md`: under the same section numbers it holds the scanners and their commands, search patterns, advisory database, and language-specific vectors. Each section below is incomplete without it. In a polyglot repository, audit each language's code against its own profile and report findings per profile.

| Focus | What is audited |
|-------|-----------------|
| `dependencies` | Known advisories, unmaintained/deprecated/yanked packages, license violations, duplicate versions |
| `unsafe` | Unsafe and escape-hatch code: memory-unsafe blocks, FFI and native modules, type-system bypasses, dynamic code evaluation |
| `secrets` | Hardcoded keys/tokens/passwords, secrets in logs, errors, and client-shipped code, `.gitignore` gaps |
| `input` | SQL/NoSQL/command injection, path traversal, untrusted deserialization, prototype pollution, integer overflow, ReDoS, unvalidated external input |
| `crypto` | Weak algorithms, custom crypto, non-CSPRNG randomness, plaintext passwords, non-constant-time comparison |
| `auth` | Broken authn/authz, user enumeration, timing side-channels, insecure session/token handling |
| `panics` | Crash and resource-exhaustion DoS: panics, uncaught exceptions, and unhandled rejections on untrusted input; unbounded allocation or recursion; a blocked runtime or event loop |
| `supply-chain` | Build- and install-time code, registry sources and git dependencies, lockfile integrity, typosquatting and dependency confusion, provenance and vetting |
| `network` | SSRF, TLS verification, request/connection limits, CORS/CSRF, XSS and CSP, header and log injection, insecure defaults |
| `filesystem` | TOCTOU and symlink races, temp files, permission modes, zip-slip, decompression bombs |
| `gates` | Escape-hatch forbids, strict lint profiles, sanitizers, fuzz and property tests on parsers, scanners in CI |
| `full` | All categories |

## Core Principle

**Every trust boundary is an attack surface, and all external input is hostile until validated.** The audit ranks findings by *exploitability*, not by theoretical elegance: a known-exploitable advisory or a hardcoded credential outranks a defense-in-depth suggestion. Prove each finding with a concrete attack scenario — an input and the damage it causes. A vulnerability you cannot describe an attack for is a hardening note, not a P0.

Start with what is already known-vulnerable: run the dependency scanners first, because a matched advisory is a confirmed vulnerability with zero false-positive risk, whereas code-pattern findings require judgment.

Pattern searches only find what matches a pattern. Before the category passes, build the attack surface map (§0) and audit each boundary on it; every category below is then applied per boundary, not just per grep hit.

Reference frameworks for completeness checks: OWASP Top 10, CWE Top 25, and the language references the profile names. When a finding maps to a CWE, cite it.

**Unchanged HEAD** — never skip the audit and never re-audit the module you covered last. Read prior `journal/ci-*.md` entries (and `journal/archive/`) attributed to your role, pick the modules least recently audited, and audit those. Record the modules covered in the handoff.

**Scope structure (optional)** — when the project's CI rules define one, judge findings against it:

- **Trust boundaries** — where untrusted input enters; a finding is real only when an input on a listed boundary reaches the sink.
- **Accepted risks** — re-verify each cycle that the accepted condition still holds (for example, no unsafe code exists); do not re-file it. A change in the condition is a new finding.
- **Sensitive assets** — what an attacker would target; weight severity by reach to these.
- **Minimum floor** — a project checklist is a floor, re-derived against the code every cycle (new modules, dependencies, and entry points expand it), never a list to rubber-stamp.
- **CI-gated scanners** — when CI already runs a scanner on every push, a clean local run adds no signal; spend the effort on what CI does not cover (escape-hatch review, injection, crypto misuse, supply-chain trust).

---

## 0. Attack Surface Map

**Goal**: every place untrusted data or an untrusted party enters the program is listed before any pattern search starts.

Enumerate and record, with file paths:

- **Network listeners and handlers** — HTTP/gRPC routes, server actions, WebSocket handlers, raw socket readers; note authentication requirements per route.
- **Outbound requests** — any client whose URL, host, or headers derive from input (SSRF surface).
- **CLI arguments, environment, config files** — parsed by whom, validated where.
- **Files and archives read** — uploads, imports, plugin/config directories, anything extracted.
- **Deserialization sites** — every decode of external bytes, with its size and depth limits (or their absence).
- **IPC, signals, sockets, shared memory, worker messages** — local surfaces that are often assumed trusted.
- **Unsafe, FFI, and native-code boundaries** — where the language's guarantees stop.
- **Build- and install-time code** — build scripts, macros, code generators, package lifecycle scripts.
- **Client-delivered code** — anything bundled and shipped to browsers, where every embedded value is public.
- **Privileged operations** — process spawning, filesystem writes outside a sandbox, credential use, database mutations; for each, which boundary above can reach it.

Trace each entry point to the first privileged operation it can reach. That path is the audit unit for §4–§10: a finding is real when an input on a listed boundary reaches the sink.

---

## 1. Dependency Vulnerabilities

**Goal**: no dependency with a known, published vulnerability ships in the build.

Run the profile's scanners and read the output as the highest-confidence source of findings.

**Matched advisories** — every scanner hit is a confirmed vulnerability. Record the advisory id, the affected package and version, the fixed version, and whether it is reachable (a vulnerability in a dev-only or unused code path is lower severity than one on the request path).

**Unmaintained packages** — an unmaintained or deprecated marker means no security fixes will arrive. Flag it, and note whether a maintained alternative exists.

**Withdrawn versions** — a yanked, unpublished, or deprecated-for-security version in the lockfile means the release was withdrawn, often for a security or correctness defect. Treat as a finding.

**Duplicate/multiple versions** — several major versions of the same package inflate the audit surface and can mean an old, vulnerable copy is linked in transitively. Report the clusters.

**License violations** — a copyleft or unknown license pulled in transitively is a legal-exposure finding; report it under this category even though it is not a memory-safety issue.

Aggregate advisories: file **one** issue listing all current advisory hits rather than one issue per advisory, unless a single advisory is Critical and warrants its own tracked remediation.

---

## 2. Unsafe and Escape-Hatch Code

**Goal**: every construct that bypasses the language's guarantees is minimal, justified, and cannot be driven into undefined behavior, type confusion, or code execution by any caller.

**Undocumented bypass** — every unsafe block, cast on unvalidated data, or suppression must carry the profile's justification comment stating the invariant. Absence is a P1 finding: the invariant is either undocumented (unreviewable) or unknown (unsound).

**Reinterpretation of data** — any construct that tells the compiler a value has a type it was never checked to have. Flag every use; most are replaceable with a checked conversion or a schema.

**FFI and native boundaries** — foreign functions taking pointers, lengths, or buffers trust the caller completely. Any such entry point reachable from untrusted data is a high-severity surface; verify length and null checks precede every access.

**Dynamic code evaluation** — evaluating a string as code is code execution for whoever controls the string. Flag every use reachable from input.

**Uninitialized or unchecked memory** — APIs that skip initialization, validation, or bounds checks are sound only when an adjacent check guarantees the invariant.

The profile lists the constructs, the search commands, and the language-specific variants (thread-safety assertions, drop-time panics, sandbox APIs that are not security boundaries).

---

## 3. Secrets and Sensitive Data

**Goal**: no credential is committed, logged, embedded in the binary, or shipped to a client.

```bash
gitleaks detect --no-banner    # scans working tree and history
```

Then run the profile's source search for credential-shaped literals.

**Hardcoded credentials** — a string literal that is an API key, password, private key, or connection string with embedded credentials. This is a P0 the moment it is in git history: rotation, not deletion, is the fix, and that belongs in the issue text.

**Secrets in logs and errors** — a log call, error message, or debug representation that prints a token, password, key, or full request body. Secrets leak through logs into aggregation systems that have a wider audience than the database.

**Secrets in client-delivered code** — any value compiled into a browser bundle, mobile app, or published package is public. Check the profile's public-configuration conventions.

**`.gitignore` gaps** — `.env`, `*.key`, `*.pem`, `secrets/`, and credential config files must be ignored. A gap means the next `git add .` commits a secret. Verify coverage rather than assuming it.

**Secrets lingering in memory** — long-lived secret material held in ordinary strings survives use and can surface in a core dump or heap snapshot. Note it as a hardening finding where the profile offers a zeroizing type.

**Secrets in argv, environment, and CI logs** — a `--token` flag is visible to every user via `ps`; an environment variable is inherited by every child process and printed by crash reporters; a CI step that echoes its environment publishes the secret. Prefer files with restricted permissions, a secret store, or stdin, and check workflow logs for masked-value gaps.

---

## 4. Input Validation and Injection

**Goal**: no untrusted input reaches an interpreter, filesystem path, object prototype, or allocation size without validation.

**SQL and NoSQL injection** — queries assembled from runtime values by string building. The fix is always bound parameters; for document stores, reject operator objects in input. Grep with the profile's pattern and confirm each hit binds.

**Command injection** — a process spawned with a shell string built from external input. Passing user data as a discrete argument is safe (with an end-of-options marker when it may start with `-`); interpolating it into a shell string is not.

**Path traversal** — a filesystem path joined from external input without canonicalization lets `../../etc/passwd` escape the intended directory. The safe pattern extracts the file name, joins onto a fixed base, canonicalizes, and re-checks that the result is under the base.

**Untrusted deserialization** — decoding attacker-controlled bytes without a size cap or depth limit enables memory exhaustion; formats or libraries that reconstruct types or functions enable code execution. Verify a length bound precedes every decode.

**Object and prototype pollution** — merging, cloning, or assigning keys from untrusted input into shared objects lets an attacker set properties every object inherits. Applies where the language has mutable prototypes.

**Integer overflow and lossy conversions** — arithmetic or narrowing conversions on externally supplied sizes used for allocation or indexing. A wrapped or truncated length is a memory-safety or logic bug.

**Missing bounds on external quantities** — a count, size, or offset from the network used directly to allocate or loop lets a small malicious message request gigabytes. Every externally supplied quantity needs an explicit ceiling.

**XML external entities** — an XML parser with entity expansion or external entity resolution enabled on untrusted documents leaks files and pivots to SSRF (XXE, billion-laughs). Confirm the parser configuration disables both.

**Regular-expression denial of service** — a backtracking engine fed a user-supplied pattern or a crafted input hangs the worker. Also flag patterns compiled per request instead of once.

---

## 5. Cryptography

**Goal**: standard, current primitives used correctly; no home-grown crypto.

**Weak or broken algorithms** — MD5, SHA-1, DES, RC4, or ECB mode anywhere near a security decision. Flag their use for anything beyond non-security checksums.

**Home-grown cryptography** — a hand-written cipher, MAC, or "encryption" by XOR/rotation. Custom crypto is wrong by default; the finding is "replace with a vetted library" (the profile names them).

**Non-CSPRNG for secrets** — a general-purpose PRNG used to generate keys, tokens, nonces, IDs, or salts. Security-sensitive randomness must come from the OS CSPRNG. A predictable token is a guessable token.

**Plaintext or weakly-hashed passwords** — passwords stored raw, or hashed with a fast hash (SHA-256) instead of a password KDF (argon2, bcrypt, scrypt). A fast hash is brute-forceable; a bare hash with no salt is rainbow-table fodder.

**Non-constant-time comparison** — `==` on secrets (MACs, tokens, password hashes) leaks length and content through timing. Secret comparison must use a constant-time equality.

**Reused or hardcoded IV/nonce** — a fixed or counter-from-zero nonce with a stream cipher or GCM breaks confidentiality. Flag any hardcoded nonce/IV literal.

---

## 6–11. Auth, DoS, Supply Chain, Network, Filesystem, and Verification Gates

Read [references/categories.md](references/categories.md) for the full checklists covering §6 (Authentication & Authorization), §7 (Crash & Resource-Exhaustion DoS), §8 (Supply-Chain Trust), §9 (Network & Service Hardening), §10 (Filesystem & Archives), and §11 (Verification Gates), and apply every section alongside `../stack/references/<profile>/security-audit.md`.

---

## Triage and Filing

Assign a severity and map it to the cycle-journal priority column:

| Severity | Priority | Criteria |
|----------|----------|----------|
| **Critical** | `P0` | Actively exploitable now: committed secret, RCE, auth bypass, Critical advisory on the request path, secret shipped in a client bundle |
| **High** | `P1` | Clear exploit vector: injection, XSS, unsafe-code UB or type confusion, path traversal, undocumented unsafe code, weak/absent password hashing |
| **Medium** | `P2` | Real but bounded: crash-DoS on request path, weak crypto, advisory in a non-critical path, missing authz on a low-value action |
| **Low** | `P3` | Hardening / defense-in-depth: unmaintained deps without a known advisory, missing zeroize, license policy drift |

File a GitHub issue for every Critical, High, and Medium finding. Batch same-kind Low findings into one issue. The literal `P0`-`P3` label is set at creation (create it and the `security` and `vulnerability` labels if missing, with `gh label create`; never use another priority scheme). Findings without a proven root cause are still filed as symptoms.

**P0 branch** — before filing a Critical finding publicly, check whether the repository supports private reporting (`SECURITY.md` routes to a private channel, or GitHub private vulnerability reporting is enabled). If so, use that channel; otherwise file a public issue labeled `P0`.

Follow [github-issues](../github-issues/SKILL.md) for capability detection, duplicate search, issue types (`Bug` for a vulnerability, `Task` for hardening), and relations.

```bash
gh issue create \
  --title "<severity>: <concise vulnerability title>" \
  --type "<Bug|Task>" \
  --label "<P0|P1|P2|P3>,security,vulnerability" \
  --body "$(cat <<'EOF'
## Vulnerability
<what is wrong>

## Severity
<Critical | High | Medium | Low> — <one-line justification>

## Location
<file:line>  (or dependency + advisory id)

## Attack Scenario
<concrete input/state and the resulting damage — the proof this is real>

## Remediation
<the specific fix; for a leaked secret, say "rotate", not "delete">

## References
<advisory id (RUSTSEC / GHSA / CVE) / CWE-NNN / advisory URL, if applicable>
EOF
)"
```

Skip false positives and note them briefly: escape-hatch code in a vendored/vetted dependency, crash-on-error in tests or startup, a string-built query that only ever interpolates a compile-time constant, weak hashing used for a non-security checksum. The profile lists the language forms. A finding you cannot attach an attack scenario to is at most a Low hardening note.

Do not duplicate an existing open security issue — check first:

```bash
gh issue list --label security --state open
```

---

## Handoff Output

Write your handoff with a **Security Review** section:

```markdown
## Security Review

### Summary
- Findings: <N total> (Critical: N, High: N, Medium: N, Low: N)
- Issues filed: <links>
- Scanners: <per profile, each scanner and its result, e.g. `<tool>`: N advisories> | `gitleaks`: <clean/N hits>
- Modules audited: <list; feeds least-recently-audited selection next cycle>

### Findings by Category
| Category | Count | Top Issue |
|----------|-------|-----------|
| Dependency advisories | N | <link or —> |
| Unsafe / escape-hatch code | N | ... |
| Secrets | N | ... |
| Input / injection | N | ... |
| Cryptography | N | ... |
| Auth / authz | N | ... |
| Crash / resource DoS | N | ... |
| Supply chain | N | ... |
| Network hardening | N | ... |
| Filesystem / archives | N | ... |
| Verification gates | N absent | ... |

### Top Security Risk
<One sentence: the single most exploitable finding, and whether it needs immediate rotation/patch>
```
