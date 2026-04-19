---
name: dont-sink-yr-ship-fix
description: |
  Applies fixes for findings from a SINKING-SHIP-REPORT.md produced by
  /dont-sink-yr-ship. Reads the report, asks which findings to fix
  (e.g. "fix 2, 4, 16" or "all-critical" or "all"), applies the fixes
  to source files, commits atomically per finding if in a git repo, and
  updates the report with FIXED/SKIPPED/DEFERRED status. Use when the user
  has a SINKING-SHIP-REPORT.md and wants fixes applied, or invoked as
  /dont-sink-yr-ship-fix.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - AskUserQuestion
---

# /dont-sink-yr-ship-fix — apply fixes

This skill is a companion to `/dont-sink-yr-ship`. It does not run detection. It reads the report, takes a fix list from the user, and applies it.

## Rules

- **Require the report.** If `SINKING-SHIP-REPORT.md` is not in the project root, stop and tell the user to run `/dont-sink-yr-ship` first. Do not try to re-detect.
- **Respect the user's list.** If they say "fix 2, 4, 16," do not apply #1, #3, or any others.
- **Atomic commits when git is available.** One commit per fixed finding.
- **Commit message default:** `chore: apply dont-sink-yr-ship #<N> fix — <short>`. Users hate skill-branded commits; keep it modest. If the project's commit log uses conventional commits, match the type (`fix:` / `chore:` / `refactor:`). If they use plain prose, drop the conventional prefix.
- **Dependency installs are their own step.** If a fix needs a new package, list all new deps at the END of the session and run a SINGLE batched install with one user confirmation, not per-finding prompts.
- **Never touch findings marked `UNKNOWN` in the report** — those need human verification first.
- **Preserve user style.** Match existing indentation, quote style, and import conventions. Read the target file fully before editing.
- **Dry-run mode.** If the user says "dry run" or "show me what you'd change," print diffs instead of applying. No commits, no edits.

## Phase 0 — Load the report

```bash
ls SINKING-SHIP-REPORT.md 2>/dev/null || echo "MISSING"
```

If missing, print:

> No `SINKING-SHIP-REPORT.md` found in this directory. Run `/dont-sink-yr-ship`
> first to produce one, then re-run this skill.

Then stop.

If present, read the full report. Parse findings by their headings (`### [FAIL] #N SEVERITY — title`). Build an in-memory list of findings with: number, severity, title, location, confidence, fix direction.

Also check git status:

```bash
git rev-parse --is-inside-work-tree 2>/dev/null && echo "GIT" || echo "NO_GIT"
git status --short 2>/dev/null | head -20
```

If git is available, warn the user if there are uncommitted changes — suggest committing first so fixes land on a clean base.

## Phase 1 — Ask what to fix

Print a compact list of all `FAIL` findings (not `PASS`, `N/A`, or `UNKNOWN`), grouped by severity:

```
CRITICAL (4):
  [ ] 1  No rate limiting on API routes              (confidence: MEDIUM)
  [ ] 2  Auth tokens in localStorage                  (confidence: HIGH)
  [ ] 4  Hardcoded API keys in shipped client code    (confidence: HIGH)
  [ ] 16 Admin routes without authz                   (confidence: LOW — verify manually)

HIGH (3):
  [ ] 6  Missing indexes on non-PK `where` fields     (confidence: LOW)
  [ ] 8  Sessions that never expire                   (confidence: MEDIUM)
  [ ] 9  Unbounded public list endpoints              (confidence: MEDIUM)

MEDIUM (2):
  [ ] 11 No env var validation at startup             (confidence: MEDIUM)
  [ ] 18 No production logging                        (confidence: MEDIUM)
```

Then ask **one** AskUserQuestion with these options:

- `All CRITICAL` — fix all CRITICAL findings (highest priority, usually the ones you can't ignore).
- `All FAIL` — fix every `FAIL` finding across severities.
- `Pick specific` — user types a list like "2, 4, 16" or "2-6" in the custom response.
- `Dry run` — show the diffs for all FAILs without applying.

If they pick `Pick specific` and don't provide the list in the custom response, prompt once more for the list.

## Phase 2 — Apply fixes

For each finding in the user's list, in severity order (CRITICAL first):

1. **Read evidence.** Read the target file(s) named in the finding's `Where:` line. If the finding's confidence is `LOW`, read surrounding context more carefully — low-confidence findings are the ones most likely to be false positives that need judgment.
2. **Apply fix.** Use `Edit` or `Write`. Minimal change. Match existing style. If the fix requires adding a new file (e.g. `src/lib/ratelimit.ts`), place it near related existing files.
3. **Verify.** Read the edited file back. If the fix didn't land cleanly (e.g. `Edit`'s `old_string` was non-unique or missing), stop and report the failure — do not force it.
4. **Commit (if git).** `git add <files> && git commit -m "<message per rules above>"`. Use `git diff --cached --stat` in the commit output summary.
5. **Update report.** Change the heading from `[FAIL]` to `[FIXED]`. Add a `- **Commit:** <sha>` line if git is available. Add `- **Applied:** <ISO date>`.
6. **Track new deps.** If the fix needs a new npm/pip/go dep, add it to a pending-install list. Do NOT install mid-phase.

If a specific fix is non-obvious or the file shape doesn't match what the finding assumed, **stop and tell the user** what you found. Don't guess — a bad fix at CRITICAL severity is worse than no fix.

## Phase 3 — Batch dependency installs

After all fixes are applied, if the pending-install list is non-empty:

1. Detect package manager from lockfile: `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `bun.lockb` → bun; `package-lock.json` → npm. Fallback to npm. For Python: `poetry.lock` → poetry; `uv.lock` → uv; else pip.
2. Print the single batched install command. Example:
   ```
   New dependencies needed:
     - @upstash/ratelimit  (for #1 rate limiting)
     - @upstash/redis      (for #1 rate limiting)
     - pino                (for #18 logging)

   Run: pnpm add @upstash/ratelimit @upstash/redis pino
   ```
3. Ask once (AskUserQuestion): `Install now` / `Skip, I'll install manually` / `Show me the commit range first`.
4. If the user says install, run it. Capture output. If install fails, report clearly and mark deps as pending in the report.

## Phase 4 — Report update + summary

Update `SINKING-SHIP-REPORT.md`:
- Fixed findings: `[FAIL]` → `[FIXED]`, add commit SHA + applied date.
- Not-in-list findings: unchanged.
- Findings whose fix was aborted: add a `- **Fix blocked:** <reason>` line, keep `[FAIL]` status.
- Append a `## Fix Session — <ISO date>` section at the end summarizing: what was fixed, what was skipped, what dependencies were installed.

Final chat summary:
- What was fixed (by finding number).
- What commits were made (compact SHA list).
- What deps were installed.
- What was skipped or blocked.
- Remaining `FAIL` count in the report.

Do not print a score. Do not imply completeness.

## Fix templates (per finding)

Use these as starting points. Adapt to the detected stack and existing code style.

**#1 Rate limiting** — Add middleware. For Next.js app router: `middleware.ts` matching `/api/*` using `@upstash/ratelimit`. For Express: `app.use('/api', rateLimit({ windowMs: 60_000, max: 60 }))`.

**#2 localStorage tokens** — Replace with httpOnly cookies. On login, set `Set-Cookie: token=...; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=604800`. Remove client-side `localStorage.setItem` and update all read call sites to use the cookie (server-side auth check only).

**#4 Hardcoded keys** — Move key to `.env` (server-only, no `NEXT_PUBLIC_` prefix). Update code to read from `process.env.STRIPE_SECRET_KEY` (or equivalent). Add to `.env.example`. Tell the user to **rotate the key** in the provider dashboard since it was shipped.

**#5 Stripe webhook verification** — Add `stripe.webhooks.constructEvent(body, signature, secret)` at the top of the handler. Return 400 on verification failure. Import `Stripe` and initialize with `STRIPE_WEBHOOK_SECRET` env var.

**#6 Missing indexes** — Add `@@index([fieldName])` to the Prisma model (or equivalent for drizzle/Django). Generate + run a migration. Tell the user to run `pnpm prisma migrate dev --name add_<field>_index`.

**#7 Error boundaries** — Next.js app router: add `app/error.tsx`. React: wrap root with `react-error-boundary`'s `ErrorBoundary`. Include a reset button and a user-visible error UI.

**#8 Session expiry** — JWT: add `expiresIn: '7d'` to the sign call. NextAuth: set `session: { maxAge: 7 * 24 * 60 * 60 }` in config.

**#9 Pagination** — Add `take: <limit>` and cursor/offset params to the query. Enforce a max (e.g. `Math.min(requestedLimit, 100)`). Return a cursor for next page.

**#10 Reset token expiry** — Add `expiresAt: new Date(Date.now() + 60 * 60 * 1000)` to token creation. On use, check `expiresAt > new Date()` before proceeding.

**#11 Env validation** — Add `src/env.ts` with a zod schema (or @t3-oss/env-nextjs if Next.js). Import it at app entry so boot fails fast on missing vars.

**#12 Disk uploads** — Swap disk storage for S3/R2/Cloudinary/UploadThing/Supabase Storage. Change route handler to upload to the chosen provider and store only the URL in the DB.

**#13 CORS** — Add `cors` middleware with an explicit origin allowlist. For Next.js, add a `middleware.ts` that sets `Access-Control-Allow-Origin` on `/api/*` for known origins. Never use `*` in production.

**#14 Sync emails** — Move send to a background job (BullMQ, Inngest, Resend's async, trigger.dev). In the handler, enqueue the job and return immediately.

**#15 Connection pooling** — Prisma: use `new PrismaClient()` at module scope, export as singleton. For serverless: add Prisma Accelerate or pgBouncer. Update DATABASE_URL to pooled version.

**#16 Admin authz** — Add a role check in middleware or at the top of admin routes: `if (session?.user?.role !== 'admin') return new Response('Forbidden', { status: 403 })`. Tell the user to verify all admin routes are covered, not just the ones this fix touched.

**#17 Health endpoint** — Create `app/api/health/route.ts` returning `{ status: 'ok' }` with a cheap DB ping if possible.

**#18 Production logging** — Add `pino` with a pretty transport in dev, JSON in prod. Replace the highest-traffic `console.log` calls in request handlers. Suggest Sentry or Axiom for aggregation.

**#19 DB backup** — If self-hosted: add a daily `pg_dump` cron with offsite storage. Document the restore procedure. If managed: confirm retention period and document it in README.

**#20 TypeScript strict** — Set `"strict": true` in `tsconfig.json`. Expect errors. Warn the user that fixing the errors is out of scope for this skill — just enabling strict mode is step one.

## What this skill does NOT do

- Detection — that's `/dont-sink-yr-ship`.
- Key rotation — it tells the user to rotate keys it finds in shipped code; it does not rotate them.
- Database migrations — it edits the schema; the user runs the migration command.
- Business-logic changes — fixes are surface-level pattern corrections, not refactors.
