# Security Audit Categories (§6–§11)

Companion checklist to [../SKILL.md](../SKILL.md). Apply alongside `../../stack/references/<profile>/security-audit.md` for every detected profile.

## 6. Authentication and Authorization

**Goal**: identity is verified before every privileged action, and the check cannot be bypassed or side-channeled.

**Missing authorization checks** — a handler that authenticates *who* the caller is but never checks *whether they may* perform the action. Enumerate privileged endpoints and confirm each gates on an ownership or role check, not merely on being logged in.

**User enumeration** — an auth path that returns distinguishable errors for "user not found" versus "wrong password" lets an attacker enumerate valid accounts. The response and timing for both cases must be identical. This pairs with the constant-time note in §5.

**Timing side-channels in auth** — an early return before password verification (short-circuiting on missing user) leaks account existence through response time even when the message is generic. Verify the verify step runs unconditionally.

**Insecure session/token handling** — tokens without expiry, session ids that are sequential or predictable, JWTs accepted with `alg: none`, without signature verification, or with an algorithm chosen by the token header, decoded instead of verified, or transmitted in URLs (where they land in logs and history). Flag each.

**Privilege escalation surfaces** — a role or permission field deserialized directly from client input, or an admin flag settable through a mass-assignment path.

---

## 7. Crash and Resource-Exhaustion Denial of Service

**Goal**: no untrusted input can crash the process, stall it, or exhaust its memory.

**Crash on untrusted input** — a parse, lookup, or conversion that panics or throws an uncaught error on malformed input is a remote crash: one bad request kills the worker. On the request path, every such site is a P2 DoS finding. (Crashes in tests, examples, build scripts, and startup are fine — scope the audit to request-handling code.)

**Unchecked indexing on external offsets** — an index from input used without a bounds check.

**Unbounded allocation** — covered in §4; an allocation sized by attacker-controlled input is memory-exhaustion DoS.

**Unbounded recursion** — a recursive parser (nested JSON, expression trees) with no depth limit overflows the stack on deeply-nested input. Verify a depth cap exists.

**Process-wide failure mode** — when one failure terminates the whole process rather than one task (abort-on-panic, crash-on-unhandled-rejection), every finding in this section rises in severity.

**Runtime starvation** — blocking or CPU-heavy work on an async runtime or event loop stalls every request on it; one slow request degrades all of them. Flag each, and any per-request task spawning or fan-out without a bound.

**Cancellation leaving state inconsistent** — work abandoned mid-way (timeout, race, client disconnect) after a partial write or half-completed transaction leaves corrupted state that a later request can exploit. Check multi-step mutations for cancel safety or an explicit rollback.

---

## 8. Supply-Chain Trust

**Goal**: understand and bound what third-party code executes at build, install, and run time.

**Build- and install-time code** — build scripts, compile-time macros, and package lifecycle scripts run arbitrary code on the developer's and CI machine with full permissions. Review every one that does network I/O, shells out, or writes outside its output directory. A malicious install or build script is the highest-leverage supply-chain attack.

**Dependency surface** — a large transitive graph is a large attack surface. Note single-maintainer, low-download, or recently-added dependencies on security-sensitive paths (crypto, parsing, auth) as candidates for vetting.

**Registry sources and git dependencies** — only the public registry and named private registries are allowed; a git dependency must pin a commit, since a branch or bare URL re-resolves to whatever the remote serves next. Applications commit their lockfile, otherwise every build resolves a different tree.

**Lockfile integrity** — resolved URLs point at the expected registry over HTTPS and every entry carries an integrity hash; a lockfile change that does not match a manifest change is a finding until explained.

**Typosquatting and dependency confusion** — the package name is the well-known one; internal package names resolve only from the private registry. A recently-added dependency with a near-duplicate name is a P1 until verified.

**Provenance and vetting** — for dependencies on security-sensitive paths, check the profile's vetting or provenance tooling.

---

## 9. Network and Service Hardening

**Goal**: the service cannot be turned into a proxy, cannot be starved by a single client, and does not trust the network more than it must.

**Server-side request forgery** — an outbound request whose URL, host, or port comes from input lets an attacker reach internal services and cloud metadata endpoints (`169.254.169.254`). Require an allowlist of hosts and schemes, resolve and re-check redirects, and block link-local and private ranges.

**TLS verification disabled** — certificate or hostname verification turned off, a custom verifier that accepts everything, or `http://` for credentialed traffic. Any of these on a non-test path is P1: the connection is plaintext to an active attacker.

**Missing request and connection limits** — no body-size cap, no header-count or header-size cap, no per-connection timeout, no maximum concurrent connections, no rate limit on expensive endpoints. Slowloris and oversized bodies exhaust memory or file descriptors with one client. Verify each limit exists at the framework or reverse-proxy layer.

**CORS and CSRF** — `Access-Control-Allow-Origin: *` with credentials, origin reflected without validation, or state-changing endpoints authenticated by cookies without a CSRF token or `SameSite` policy.

**Cross-site scripting and CSP** — untrusted data rendered as HTML, into a script context, or into a URL attribute (`javascript:` URLs) through a framework escape hatch; no Content-Security-Policy, or one that allows `unsafe-inline`/`unsafe-eval` for scripts.

**Header, CRLF, and log injection** — input written into response headers, redirect targets, or log lines without stripping `\r\n` lets an attacker forge headers or fake log entries. Unvalidated redirect targets are also open redirects.

**Insecure defaults** — binding `0.0.0.0` when only local access is needed, debug or metrics endpoints without authentication, verbose error bodies (stack traces, SQL) in production responses, default credentials in shipped config, cookies without `HttpOnly`/`Secure`.

---

## 10. Filesystem and Archives

**Goal**: file operations cannot be redirected, raced, or inflated by an attacker who controls names, links, or archive contents.

**TOCTOU and symlink races** — checking a path (exists, metadata, canonicalize) and then opening it lets an attacker swap a symlink in between. Open first, then validate the opened file, or operate on directory handles.

**Predictable temporary files** — hand-built names under `/tmp` are guessable and pre-creatable. Require atomic exclusive creation in a private directory.

**Permission modes** — secrets written with default umask are world-readable; `0o777` on directories invites tampering. Check the mode on every write of sensitive data.

**Zip-slip on extraction** — archive entries named `../../etc/cron.d/x` escape the destination unless each entry path is joined, canonicalized, and checked against the destination before writing. Applies to zip, tar, and custom formats.

**Decompression bombs** — decompressors and image decoders expand small inputs to gigabytes. Require a cap on decompressed size and on entry count.

---

## 11. Verification Gates

**Goal**: the project has automated defenses that keep the classes above from returning. Their absence is a finding in its own right (Low, or Medium on request-path code).

Gate classes; the profile names the concrete gates:

- Escape hatches forbidden by the compiler or linter wherever the code has no legitimate use for them.
- A strict lint profile on request-path code (crash sites, unchecked indexing, unhandled async errors, dynamic evaluation).
- Dynamic checkers or sanitizers on code containing unsafe or native constructs.
- A fuzz or property-test target for every parser of untrusted input (§0 lists them), and round-trip tests for encoders/decoders.
- Dependency scanners in CI, not only on developer machines, with the lockfile committed and installs frozen.

Report the gate matrix (present / absent per crate or package) in the handoff even when every gate is present — it is the evidence that the audit's negative findings hold.
