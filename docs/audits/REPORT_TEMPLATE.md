# Audit Report Template

Copy this structure into `docs/audits/YYYY-MM-DD-full-audit-report.md`.
Severity, status, and finding fields are mandatory.

---

## Severity

| Severity | Meaning | Examples |
| --- | --- | --- |
| **P0 – Critical** | Exploitable security hole, data loss/corruption, wrong money shown as correct, leaked secret, store rejection, crash on a core flow | Cross-workspace read, committed private key, double quota, payments hidden |
| **P1 – High** | Serious bug or risk on a common path; compliance gap; broken offline recovery | Silent poison retries, missing account deletion, role bypass in UI |
| **P2 – Medium** | Edge-path bug, significant UX/perf/maintainability issue | Unbounded query, missing Arabic on a screen, 50 KB widget file |
| **P3 – Low** | Polish, consistency, hygiene, minor debt | Hard-coded padding, stale comment, junk file |
| **Idea** | Enhancement (playbook wave 7) | New feature, refactor, tooling |

## Finding template

```markdown
#### [P1][F-017] Short title
- **Status:** CONFIRMED | SUSPECTED
- **Domain:** D. Cloud Functions
- **Location:** `functions/src/index.ts:2423`, `lib/features/payments/data/payment_repository.dart:88`
- **What's wrong:** one or two precise sentences.
- **Failure scenario:** concrete inputs/state → observable wrong outcome.
- **Evidence:** code excerpt (≤ 10 lines) or command output summary. Never paste secrets.
- **Recommended fix:** specific change and where.
- **Verification:** test to add or manual check that proves the fix.
- **Effort:** S | M | L | XL  · **Fix risk:** low | medium | high
- **Related:** F-003, prior audit P1-4, spec 003 FR-041
```

P3 items may be compacted into a table: ID | file:line | issue | fix.

## Report outline

1. **Executive summary** (≤ 1 page)
   - Health score per domain A–W (0–10, one-line justification)
   - Top 10 risks
   - Top 10 improvements
   - Release-readiness: ship / ship with fixes / do not ship + reasons
2. **Baseline results** — versions, analyzer, tests, coverage if run, npm audit, outdated majors, commands that could not run
3. **Constitution compliance** — I–V and product constraints: PASS / PARTIAL / FAIL
4. **Prior-audit diff** — Fixed / Still open / Regressed / N/A
5. **Spec 003 status** — each task Done / Partial / Missing with evidence
6. **Findings by domain** A–W, sorted by severity
7. **Low-severity detail list** (P3 table)
8. **Enhancements** — Now / Next / Later, with competitor sources (links)
9. **Quick wins** (< 2 h each)
10. **Remediation roadmap** — Stop-the-bleeding → Stabilize → Harden → Improve → Grow
11. **Open questions** for the product owner
12. **Appendix** — files reviewed, flows traced, commands run, skips and why

## Lead disposition

Every entry in `LEAD_REGISTER.md` must appear as Confirmed, Refuted, or
Refined in the report appendix or in the register itself.

## Ship verdict rubric

- **Do not ship:** any unmitigated P0, or P1 that is a store-policy or money-integrity failure on a core path
- **Ship with fixes:** no P0; remaining P1s have a documented workaround or are console-gated
- **Ship:** no P0/P1; P2s tracked in the roadmap
