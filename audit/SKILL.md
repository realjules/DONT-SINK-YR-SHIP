---
name: dont-sink-yr-ship
description: |
  20-point pre-launch safety scan for AI/vibe-coded apps. Detects the stack,
  runs 20 heuristic checks (no rate limiting, tokens in localStorage,
  hardcoded API keys, missing Stripe webhook verification, etc.), writes
  findings with per-check confidence to SINKING-SHIP-REPORT.md. This skill
  ONLY produces the report — to apply fixes, run /dont-sink-yr-ship-fix
  afterwards. Use when asked to "audit my app", "sinking ship check",
  "is my app production ready", "pre-launch audit", "don't sink my ship",
  or invoked as /dont-sink-yr-ship.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Write
---

# /dont-sink-yr-ship — audit

Two-phase: **detect stack → scan → write report**. This skill does **not** apply fixes. After the report is written, tell the user to run `/dont-sink-yr-ship-fix` when they're ready to apply fixes.

## What this skill is NOT

This is a **heuristic checklist, not a security audit.** A clean run does not mean your app is safe — it means none of these 20 known patterns matched. Real risks like broken authz logic, multi-tenant data leaks, webhook replay attacks, and business-logic bugs are outside its scope. State this plainly in the report header and in the chat summary.

## Rules

- **Report is the only output.** Do not edit any source files.
- **Evidence per finding.** Every `FAIL` has `file:line` or a specific "absent from repo" note.
- **Confidence per finding.** Every finding gets `Confidence: HIGH | MEDIUM | LOW` with a one-line justification. A false positive at HIGH hurts the skill's trust; be honest.
- **Don't count a score.** No `N/20`. No percentage. Severity counts only.
- **No speculative fixes.** If the stack is ambiguous, ask the user once (AskUserQuestion). If unambiguous, proceed silently.
- **Respect monorepos.** If CWD has no `package.json` but has `apps/*/package.json` or `packages/*/package.json`, ask which subdir to audit.

## Phase 0 — Detect stack

```bash
# Monorepo sniff
ls package.json 2>/dev/null || ls apps/*/package.json packages/*/package.json 2>/dev/null
# Framework
grep -E '"(next|react|vue|svelte|express|fastify|hono|nestjs|remix|astro)"' package.json 2>/dev/null
# ORM / DB
ls prisma/schema.prisma drizzle.config.* 2>/dev/null
grep -lE "mongoose|sequelize|typeorm|kysely|knex|sqlalchemy|drf" package.json pyproject.toml 2>/dev/null
# Auth
grep -lE "next-auth|@clerk|lucia|better-auth|passport" package.json 2>/dev/null
# Env file
ls .env .env.local .env.example 2>/dev/null
# Deploy target hints
ls vercel.json fly.toml render.yaml netlify.toml railway.toml 2>/dev/null
```

Write detected stack to report header: `Stack: Next.js 15 (app router) + Prisma + Postgres + NextAuth, deployed to Vercel`.

If detection is ambiguous (e.g. both Express and Next.js hints), ask once.

## Phase 1 — Run the 20 checks

Each check produces one of:
- `PASS` — pattern checked, not found.
- `FAIL` — pattern found (or required pattern absent). Must include evidence + confidence.
- `N/A` — check doesn't apply to this stack (e.g. Stripe check on a static site).
- `UNKNOWN` — detection couldn't run cleanly (parse error, unreadable file). Name what failed.

Never silently skip. `UNKNOWN` is a valid outcome and must surface in the report.

### Severity map

| # | Check | Severity | Default Confidence |
|---|---|---|---|
| 1 | No rate limiting on API routes | CRITICAL | MEDIUM |
| 2 | Auth tokens in localStorage | CRITICAL | HIGH |
| 3 | No input validation on mutation endpoints | CRITICAL | LOW |
| 4 | Hardcoded API keys in shipped client code | CRITICAL | HIGH |
| 5 | Stripe webhooks without signature verification | CRITICAL | HIGH |
| 6 | Missing indexes on non-PK `where` fields | HIGH | LOW |
| 7 | No error boundaries in UI | HIGH | MEDIUM |
| 8 | Sessions that never expire | HIGH | MEDIUM |
| 9 | Unbounded public list endpoints | HIGH | MEDIUM |
| 10 | Password reset tokens that don't expire | HIGH | MEDIUM |
| 11 | No env var validation at startup | MEDIUM | MEDIUM |
| 12 | Images uploaded to local disk | MEDIUM | HIGH |
| 13 | Missing CORS policy on cross-origin API | MEDIUM | LOW |
| 14 | Synchronous emails in request handlers | MEDIUM | MEDIUM |
| 15 | No DB connection pooling | MEDIUM | MEDIUM |
| 16 | Admin routes without authz | CRITICAL | LOW |
| 17 | No health check endpoint | LOW | HIGH |
| 18 | No production logging | MEDIUM | MEDIUM |
| 19 | No DB backup strategy | HIGH | LOW |
| 20 | No TypeScript / strict mode off | LOW | HIGH |

**Confidence defaults reflect how fragile the detection is.** Raise or lower per-repo based on what you find.

### Detection notes (rewritten to reduce false positives)

**#1 Rate limiting (MEDIUM confidence)** — Look for rate-limit middleware wired into API routes. Libraries: `express-rate-limit`, `@upstash/ratelimit`, `hono/rate-limiter`, `next-safe-action` throttle, Django REST `DEFAULT_THROTTLE_CLASSES`, FastAPI `slowapi`. `FAIL` only if at least one public API route exists AND none of these are wired up. Static-only sites → `N/A`.

**#2 Auth tokens in localStorage (HIGH confidence)** — Grep for `localStorage\.(setItem|getItem).*(token|jwt|auth|session|access_token|refresh)` in frontend code. Any match = `FAIL`. Grep is reliable here.

**#3 Input validation (LOW confidence — heuristic)** — For each `POST`/`PUT`/`PATCH`/`DELETE` route, check if the handler: (a) passes the body through a validator (`zod.parse`, `yup.validate`, `joi.validate`, `valibot`, Django/DRF serializer `.is_valid()`, pydantic, class-validator), OR (b) never touches the body directly. `FAIL` if a handler reads raw body properties without validation. **Confidence is LOW**: this check has high false-positive rate on codebases that use custom validators or pre-middleware. Report as "possible gap, verify manually." Do NOT treat a single zod import as proof of app-wide validation.

**#4 Hardcoded keys in shipped code (HIGH confidence)** — Grep shipped-to-client paths (`app/`, `pages/`, `src/components/`, `public/`, `client/`) for: `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_`, `AIza[0-9A-Za-z_-]{35}`, `AKIA[0-9A-Z]{16}`, `xoxb-`, `ghp_[A-Za-z0-9]{36}`, `Bearer [A-Za-z0-9]{20,}`. Also flag any `NEXT_PUBLIC_*` / `VITE_*` / `REACT_APP_*` whose name contains `SECRET` or `PRIVATE`. HIGH confidence — these prefixes are unambiguous.

**#5 Stripe webhooks (HIGH confidence)** — Find handlers in files matching `stripe.*webhook|webhook.*stripe|/api/webhooks/stripe`. Check that each handler calls `stripe.webhooks.constructEvent(body, signature, secret)` before trusting the payload. `FAIL` if handler reads `JSON.parse(body)` or `req.body` before verification. HIGH confidence — verification pattern is well-defined.

**#6 Missing indexes (LOW confidence)** — For ORMs, parse the schema (`prisma/schema.prisma`, drizzle schema, Django models) and build a set of `@unique` / `@@index` / `db_index=True` fields per model. Then grep the codebase for `.where(...)`, `.findMany({ where: {...} })`, `filter(...)` calls. **Only flag fields that:** (a) are NOT the primary key, (b) are used in `where` across ≥2 call sites, and (c) have no matching index. Skip `findUnique` / `findFirst { where: { id } }` entirely — they hit PK by definition. Report per-field, not per-callsite. LOW confidence — static analysis of dynamic ORM queries is hard; expect false positives on computed filters. Note this in the finding.

**#7 Error boundaries (MEDIUM confidence)** — React only. Check for `ErrorBoundary` class, `react-error-boundary` dep, or Next.js `app/**/error.tsx` files. `FAIL` if none present AND app has React components. MEDIUM confidence — non-React stacks → `N/A`.

**#8 Session expiry (MEDIUM confidence)** — JWT: check `jwt.sign(..., { expiresIn })` — missing or set to implausible values (years) = `FAIL`. NextAuth: `session.maxAge` in config missing = `FAIL`. Cookie-based: cookie set without `maxAge`/`expires`/`Max-Age`. MEDIUM confidence — bespoke session systems may hide expiry in middleware.

**#9 Unbounded public lists (MEDIUM confidence)** — Find API routes that return arrays. `FAIL` only if ALL of these are true: (a) the route is public (no auth middleware upstream), (b) the query is `findMany` / `.find({})` / `SELECT *` without any `take` / `limit` / cursor, (c) the result is serialized to JSON without a post-filter `.slice()`. **Exclude:** `findUnique`, `findFirst`, admin-prefixed routes, and internal queries that feed aggregates. MEDIUM confidence — auth detection is imperfect.

**#10 Reset token expiry (MEDIUM confidence)** — Find password reset token generation. Either (a) JWT with no `expiresIn` or (b) DB token with no `expiresAt` column (check migrations/schema). `FAIL` if either. Note: short expiry (1h) isn't enforced here — just that *some* expiry exists. MEDIUM confidence — reset flows are diverse.

**#11 Env validation (MEDIUM confidence)** — Look for a central env-validation schema: `@t3-oss/env-nextjs`, `envsafe`, `zod` schema that reads `process.env`, or explicit `if (!process.env.X) throw` at app entry (`src/env.ts`, `server.ts`, `main.ts`, `wsgi.py`). `FAIL` if env vars are referenced in ≥3 files but no central validation exists.

**#12 Images to local disk (HIGH confidence)** — Grep for `multer.diskStorage`, `formidable` with `uploadDir`, `busboy` writing to fs. `FAIL` if uploads land in local `./uploads/` or similar. HIGH confidence — pattern is explicit.

**#13 CORS (LOW confidence)** — Skip entirely if: (a) Next.js app with API routes served same-origin as frontend (no external callers), (b) single-origin Express/Fastify. Only `FAIL` if there's evidence of cross-origin usage (mobile client, separate frontend domain, `Access-Control-*` references in frontend code) AND no CORS policy on server. LOW confidence — same-origin deployments are the majority of Next.js apps and should not be flagged.

**#14 Sync emails (MEDIUM confidence)** — Grep handlers for `await sendEmail|transporter.sendMail|resend.emails.send|ses.sendEmail|sgMail.send` INSIDE a request handler (not in a queue/worker/background function). `FAIL` if the email send is on the request critical path.

**#15 Connection pooling (MEDIUM confidence)** — PASS if: Prisma/Drizzle/Mongoose used (module-level singleton). `FAIL` if: `new Client()` / `new Pool()` inside a handler, or serverless deploy without pgbouncer/Accelerate. MEDIUM confidence — serverless nuance matters.

**#16 Admin authz (LOW confidence)** — Two-pronged: (a) grep for routes under `/admin/*`, `/api/admin/*`, or files with `admin` in name; (b) check for middleware files (`middleware.ts`, `auth.ts`, `guards/`) that enforce role checks. `FAIL` only if admin routes exist AND neither the handler nor upstream middleware checks `role === 'admin'` / `is_staff` / `is_superuser`. LOW confidence — authz often lives in middleware or decorators the grep can miss; mark findings as "verify the middleware wiring manually."

**#17 Health endpoint (HIGH confidence)** — Grep for `/health`, `/healthz`, `/api/health`, `/_health`, `/ping`. `FAIL` if none exist in the routes. HIGH confidence — pattern is unambiguous.

**#18 Production logging (MEDIUM confidence)** — Check for one of: `pino`, `winston`, `bunyan`, `@sentry/*`, `@logtail/*`, `@axiom-co/*`, OpenTelemetry setup, Vercel/Railway log-drain. `FAIL` if only `console.log` and no log aggregation is configured.

**#19 DB backup (LOW confidence)** — Managed DB (Neon/Supabase/PlanetScale/Aiven/RDS based on connection string or env var names) → `PASS` with note "managed provider handles backups, verify retention policy." Self-hosted Postgres/MySQL → check for backup cron, `pg_dump` scripts, Docker volume backup config. `FAIL` only if self-hosted with no visible backup strategy. LOW confidence — infrastructure intent is hard to see from repo alone.

**#20 TypeScript (HIGH confidence)** — `tsconfig.json` missing = `FAIL`. Present but `"strict": false` or missing `"strict"` = `FAIL`. Count `// @ts-nocheck` / `// @ts-ignore` — flag count in finding. Pure JS project with `.js`/`.jsx` only → `FAIL`. HIGH confidence.

## Phase 2 — Write the report

Overwrite any existing `SINKING-SHIP-REPORT.md` in the project root. If one exists, rename it to `SINKING-SHIP-REPORT.prev.md` first so the user can diff.

### Report format

```markdown
# Sinking Ship Report

**Scanned:** {ISO date}
**Stack:** {detected stack}
**Counts:** {n} CRITICAL · {n} HIGH · {n} MEDIUM · {n} LOW · {n} PASS · {n} N/A · {n} UNKNOWN

> This is a heuristic checklist, not a security audit. A clean run means none of
> 20 known patterns matched. Business-logic bugs, multi-tenant data leaks, broken
> authz, and webhook replay are out of scope. Do not interpret this report as
> proof that your app is safe to launch.

---

## Findings

### [FAIL] #2 CRITICAL — Auth tokens in localStorage

- **Where:** `src/lib/auth.ts:23` — `localStorage.setItem('token', jwt)`
- **Confidence:** HIGH — grep pattern is unambiguous.
- **Risk:** Any XSS payload exfiltrates every user's session.
- **Fix direction:** Switch to httpOnly + Secure + SameSite=Lax cookies; remove client-side token handling.

### [FAIL] #6 HIGH — Missing indexes on non-PK `where` fields

- **Where:** `prisma/schema.prisma` — `User.email` (used in `where` at `app/api/auth/route.ts:14` and `src/lib/users.ts:8`); `Post.authorId` (used at 3 call sites)
- **Confidence:** LOW — static analysis of dynamic queries is imperfect. Verify the two fields above are actually the hot paths before adding indexes.
- **Risk:** Full table scans at scale; fine at 100 users, breaks at 10k.
- **Fix direction:** Add `@@index([email])` and `@@index([authorId])` and run migration.

### [UNKNOWN] #5 — Stripe webhook verification

- **Where:** `app/api/webhooks/stripe/route.ts` exists but could not be parsed (syntax error on line 47).
- **Reason:** Skipped. Verify manually that the handler calls `stripe.webhooks.constructEvent(...)` before trusting payload.

...

---

## Passed

- [PASS] #17 Health check — `app/api/health/route.ts` exists.
- [PASS] #20 TypeScript — `tsconfig.json` strict mode enabled.

---

## Not applicable

- [N/A] #12 — No file upload paths detected in repo.

---

## Next step

To apply fixes for the findings above, run `/dont-sink-yr-ship-fix`.
It reads this report, lets you pick which findings to fix (e.g. "fix 2, 4, 16"
or "all-critical"), and applies them atomically.
```

After writing the report, summarize in chat:
- The stack you detected.
- Counts per severity.
- **Do not report a score.**
- Point at the report file and name the next skill: `/dont-sink-yr-ship-fix`.

## What this skill does NOT do

- Penetration testing or active exploitation.
- Runtime analysis — static only.
- Business-logic review, multi-tenant isolation checks, or replay-attack review.
- Replacing a proper security review for apps handling PII, PCI, or HIPAA data. If the skill surfaces sensitive-data handling, flag this to the user explicitly.
