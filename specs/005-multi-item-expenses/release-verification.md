# Release Verification: 005 Multi-Item Expenses

Constitution Principle II record for migration `007_expense_items` (quickstart §3, task T062).

| Item | Value |
|---|---|
| Date (UTC) | 2026-10-20 08:31 |
| Target | VPS `srv1982020.hstgr.cloud`, compose project `wizesite` (no 004 cutover recorded; data = migrated Firestore copy) |
| Release | `main` @ `d15f6b8` (`git -c core.autocrlf=false archive HEAD server ops`) |
| Migration applied | `007_expense_items` (`items` column present) |
| Backup before deploy | `/srv/wizesite/state/pre-005-20261020T082830Z/` (original app files + `db.sql.gz`) and `pre-005-20261020T083112Z/` |
| Health after deploy | `{"status":"ok","db":"ok","sync":"ok"}`; public `https://api.buildozer.dpdns.org/healthz` OK |

## Totals snapshot (active expenses, per project)

| Project | Before | After |
|---|---|---|
| demo6tukdkkqvsmroqpm2r | 332000.00 | 332000.00 |
| demofpnvg9snpamroqpsew | 197000.00 | 197000.00 |
| demouftxtevpubmroqppq3 | 322000.00 | 322000.00 |
| ODxe9XiyW82ojGcS7hXK | 50000.00 | 50000.00 |
| pD7W4N82RTVcj8pb9M4f | 33200.00 | 33200.00 |
| Expense rows | 18 | 18 |

**Result: identical, mismatches: 0.**

## Notes

- First deploy attempt aborted harmlessly at `deploy.sh` line 10 (`set: pipefail: invalid option`):
  `git archive` on Windows applied `core.autocrlf`, giving the scripts CRLF endings. No container or
  database change happened; the archive was rebuilt with `-c core.autocrlf=false` and redeployed.
- **AI eval (`npm run eval:receipts`) not passed yet**: every call fell back to rules because
  OpenRouter returns `401 "User not found"` for the `OPENROUTER_API_KEY` in `/srv/wizesite/.env`.
  The key is invalid or revoked. Until it is replaced, voice transcription and "Organize with AI"
  on this server cannot work (voice was already affected before this release). Replace the key,
  then re-run the eval (quickstart §2).
