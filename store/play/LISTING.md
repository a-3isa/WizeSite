# Google Play — Store Listing

Copy-paste fields for **Create default store listing** (English – United States).

---

## App name  (max 30)

```
Buildozer
```

## Short description  (max 80)

```
Log site expenses by voice. See real-time profit. Works offline. AR + EN.
```

*(73 / 80 characters)*

## Full description  (max 4000)

```
Buildozer is the field-ready money tracker built for construction contractors and site managers — not for the office. Track every pound on every site, log expenses the moment they happen, and always know your real profit.

WHY BUILDOZER

Site money lives in pockets, texts, and memory. By the time it reaches a spreadsheet, the project has moved on and the margin is a guess. Buildozer captures the money as it moves — on site, in the field, in the language your crew speaks.

LOG EXPENSES BY VOICE
Record on site → transcribe → parse → confirm → save. Speak a cost while your hands are full and Buildozer files it in the right project and category. No typing on a dusty screen, no receipts lost in a truck.

Voice notes are sent to a third-party AI provider (on our servers) to transcribe and suggest expense fields. You review and confirm every result before anything is saved. Do not record conversations you do not intend to store.

REAL-TIME PROFIT
Every expense and payment updates net profit, budget health, and expected final cost instantly — for each project and across your whole workspace. The number you opened the app for is the first thing you see.

WORKS OFFLINE
Basements, tunnels, remote plots — log freely with no signal. Everything queues safely and syncs the moment you're back online.

ARABIC + ENGLISH, FULL RTL
English and Arabic as first-class citizens, with proper right-to-left layout, so your whole crew reads the same numbers.

TRACK EVERYTHING ON SITE
• Projects with contract value, budget and completion
• Expenses and payments with payment status (paid, partial, unpaid)
• Workers, contractors, equipment, transport and materials
• Suppliers and payment methods (cash, bank, cheque)

REPORTS OWNERS TRUST
Export clean, professional PDF reports for any project or period, and hand owners a number they can rely on.

BUILT FOR THE JOBSITE
• Mobile-first, fast, low-friction
• Light and dark themes
• Bank-grade security with Firebase
• Free to start; upgrade to Pro for unlimited projects, reports and team

Stop guessing your margin. Put the site's money in your pocket with Buildozer.
```

## Graphics — files in `out/`

| Play field | File | Size |
|---|---|---|
| App icon | `out/icon.png` | 512 × 512 |
| Feature graphic | `out/feature.png` | 1024 × 500 |
| Phone screenshots | `out/phone-1.png` … `out/phone-5.png` | 1080 × 1920 |
| 7-inch tablet | `out/tablet7-1.png`, `out/tablet7-2.png` | 1200 × 1920 |
| 10-inch tablet | `out/tablet10-1.png`, `out/tablet10-2.png` | 1600 × 2560 |

All PNGs are within Play's file-size limits (icon ≤ 1 MB, feature ≤ 15 MB, screenshots ≤ 8 MB).

## Screenshot captions (for reference — baked into the images)

1. Real-time profit — *Know your margin at a glance*
2. Signature feature — *Log expenses by voice*
3. Every site, live — *All your projects in one place*
4. Fast entry — *Structured in seconds*
5. One money feed — *Search and filter every transaction*

## Video

Optional. Leave blank, or add a public/unlisted YouTube URL (ads off, not age-restricted).

---

### Regenerating the graphics

```bash
cd store/play
node build.js                 # writes HTML canvases to html/
# then render with Chrome headless (see build note); PNGs land in out/
```
