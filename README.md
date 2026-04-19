# dont-sink-yr-ship

> Pre-launch safety scan for AI/vibe-coded apps. Two Claude Code skills: one audits, one fixes.

Your AI wrote confident, shippable-looking code. It did not tell you about the 20 things that will sink your app when real users show up. These skills find them.

## The two skills

- `/dont-sink-yr-ship` — scans your code for 20 known patterns, writes `SINKING-SHIP-REPORT.md` with per-check confidence. Touches no source files.
- `/dont-sink-yr-ship-fix` — reads the report, lets you pick which findings to fix (e.g. `fix 2, 4, 16` or `all-critical`), applies them, commits atomically.

They're separate because detection and remediation are different jobs. Running `/dont-sink-yr-ship` on a strange repo should be safe — no edits until you invoke the fix skill.

## What this is NOT

A heuristic checklist, not a security audit. A clean report means none of these 20 patterns matched your code. It does **not** mean your app is safe. Real production killers — broken authz, multi-tenant data leaks, webhook replay, business-logic bugs — are out of scope. The skills report their own confidence per finding because some of these checks are more reliable than others; trust the HIGH-confidence ones, verify the LOW-confidence ones manually.

There is no `N/20 seaworthy` score. A ratio would imply completeness the skills can't deliver.

## The 20 checks

| # | Check | Severity |
|---|---|---|
| 1 | No rate limiting on API routes | CRITICAL |
| 2 | Auth tokens in localStorage | CRITICAL |
| 3 | No input validation on mutation endpoints | CRITICAL |
| 4 | Hardcoded API keys in shipped client code | CRITICAL |
| 5 | Stripe webhooks without signature verification | CRITICAL |
| 6 | Missing indexes on non-PK `where` fields | HIGH |
| 7 | No error boundaries in UI | HIGH |
| 8 | Sessions that never expire | HIGH |
| 9 | Unbounded public list endpoints | HIGH |
| 10 | Password reset tokens that don't expire | HIGH |
| 11 | No environment variable validation at startup | MEDIUM |
| 12 | Images uploaded to local disk | MEDIUM |
| 13 | Missing CORS policy on cross-origin API | MEDIUM |
| 14 | Synchronous emails in request handlers | MEDIUM |
| 15 | No database connection pooling | MEDIUM |
| 16 | Admin routes without authz | CRITICAL |
| 17 | No health check endpoint | LOW |
| 18 | No production logging | MEDIUM |
| 19 | No database backup strategy | HIGH |
| 20 | No TypeScript / strict mode off | LOW |

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/udaheju/dont-sink-yr-ship/main/install.sh | bash
```

### Manual

```bash
git clone https://github.com/udaheju/dont-sink-yr-ship /tmp/dont-sink-yr-ship
cp -r /tmp/dont-sink-yr-ship/audit ~/.claude/skills/dont-sink-yr-ship
cp -r /tmp/dont-sink-yr-ship/fix   ~/.claude/skills/dont-sink-yr-ship-fix
```

Restart Claude Code (new session picks up the skills).

### Requirements

- Claude Code
- bash + git (WSL on Windows)

## Usage

Audit:

```
/dont-sink-yr-ship
```

Produces `SINKING-SHIP-REPORT.md` in your project root with findings by severity, each tagged `Confidence: HIGH | MEDIUM | LOW`. Takes about 30-90 seconds depending on repo size.

Fix:

```
/dont-sink-yr-ship-fix
```

Reads the report, shows a compact list of `FAIL` findings, asks which to apply. Options:

- `All CRITICAL` — fix every CRITICAL finding
- `All FAIL` — fix everything
- `Pick specific` — `fix 2, 4, 16` in free text
- `Dry run` — show diffs without applying

Atomic commit per fix when in a git repo. Single batched dependency install at the end.

### Voice triggers

Any of these will invoke `/dont-sink-yr-ship`:

- "audit my app"
- "sinking ship check"
- "is my app production ready"
- "pre-launch audit"
- "don't sink my ship"

## Example report excerpt

```markdown
# Sinking Ship Report

**Scanned:** 2026-04-20
**Stack:** Next.js 15 (app router) + Prisma + Postgres + NextAuth
**Counts:** 3 CRITICAL · 2 HIGH · 1 MEDIUM · 12 PASS · 2 N/A

> This is a heuristic checklist, not a security audit. A clean run means none
> of 20 known patterns matched. Business-logic bugs, multi-tenant data leaks,
> broken authz, and webhook replay are out of scope.

---

## Findings

### [FAIL] #2 CRITICAL — Auth tokens in localStorage

- **Where:** `src/lib/auth.ts:23` — `localStorage.setItem('token', jwt)`
- **Confidence:** HIGH — grep pattern is unambiguous.
- **Risk:** Any XSS payload exfiltrates every user's session.
- **Fix direction:** Switch to httpOnly + Secure + SameSite=Lax cookies.

### [FAIL] #6 HIGH — Missing indexes on non-PK `where` fields

- **Where:** `prisma/schema.prisma` — `User.email` (used in where at 2 sites)
- **Confidence:** LOW — static analysis of dynamic queries is imperfect.
  Verify these are actually the hot paths before adding indexes.
```

## Limits — read this before trusting the report

These detections are heuristics. The skill flags each finding's confidence:

- **HIGH confidence** (#2, #4, #5, #12, #17, #20): grep patterns are unambiguous. Trust these findings.
- **MEDIUM confidence** (#1, #7, #8, #9, #10, #11, #14, #15, #18): detection is stack-specific and can miss edge cases. Verify before applying fixes.
- **LOW confidence** (#3, #6, #13, #16, #19): these checks have known false-positive shapes. Read the finding's "confidence" line; the skill will say which false positives to expect.

In particular:
- #3 treats "no zod import" as a signal — it cannot tell that your Django serializers validate input.
- #6 flags fields used in `where` across multiple call sites without an index; it doesn't know which fields are hot paths in production.
- #13 only flags CORS gaps when it sees evidence of cross-origin usage; same-origin Next.js apps are correctly skipped.
- #16 misses the common pattern where authz lives in middleware the grep can't trace. Verify every admin route manually.

If a finding feels wrong, it probably is. Open an issue.

## Why

AI-generated code ships fast and looks right. It usually passes the happy path. What it misses is the unglamorous infrastructure hygiene that separates a prototype from something that survives contact with the public internet — and those misses are remarkably consistent across codebases. These skills encode the 20 most common ones into a repeatable audit.

## License

MIT. See [LICENSE](./LICENSE).

## Credits

The 20-point list comes from [`starting.txt`](./starting.txt).
