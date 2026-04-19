# Changelog

## v0.1.0 — 2026-04-19

Initial release.

- `/dont-sink-yr-ship` — 20-point static audit skill. Writes `SINKING-SHIP-REPORT.md` with per-finding confidence (HIGH / MEDIUM / LOW).
- `/dont-sink-yr-ship-fix` — companion skill that reads the report, applies user-selected fixes, commits atomically per finding.
- Covers: Next.js, Express, Fastify, Hono, Django/DRF, FastAPI. Other stacks degrade to UNKNOWN for stack-specific checks.
- No `N/20 seaworthy` score — severity counts only. The README is explicit that this is a heuristic checklist, not a security audit.
- Rewritten heuristics for #3, #6, #9, #13, #16 to reduce false-positive rate on the target audience (solo builders on Next.js + Prisma stacks).