# FinTrack — home expense tracker

Flutter app (**FinTrack**) for tracking household spending: log an expense, then read it back by
**week / month / year** and see which categories the money went to.

Currency is **PKR** (`Rs 1,250`, no decimals). Data lives in **Supabase**
(Postgres + auth): every account registers with name, email and password, and
row level security means an account can only ever read or write its own
expenses.

## Setup (once)

1. **Key** — Supabase dashboard → *Project Settings → API Keys* → copy the
   `anon public` / *Publishable* key into `_pastedKey` in
   [lib/core/supabase_config.dart](lib/core/supabase_config.dart), or pass it at
   run time with `--dart-define=SUPABASE_ANON_KEY=eyJ…`. That key is meant to be
   public; **never put the `service_role` key in this app**.
2. **Schema** — *SQL Editor* → paste and run [supabase/schema.sql](supabase/schema.sql).
   It creates every table (expenses, budgets, pay, family members, projects,
   vehicles and their service records), their indexes and RLS policies. Safe to
   re-run, so run it again after pulling a version that adds tables.
3. **Email confirmation** — *Authentication → Sign In / Providers* → turn
   **Confirm email** off, so registering logs you straight in. (If you leave it
   on, the app shows a "confirm your email" notice instead — both paths work.)

Until step 1 is done the app opens a setup screen with these instructions
instead of failing on the first request.

## Run it

```bash
flutter pub get
flutter run              # pick a device; also runs on Windows/Chrome
flutter test             # 135 tests: model maths + full-app widget tests
flutter analyze
```

New accounts start empty — there is no sample data. **Overview → ⋯ → Clear all
expenses** deletes every row in the signed-in account.

## Screens

| Tab | What it does |
|---|---|
| **Overview** | Period filter, total spent + change vs the previous period, budget ring and the two categories closest to their limit, spend-over-time bars, top 5 categories, recent expenses |
| **Insights** | Stat tiles (total, per day, biggest category, priciest weekday), category ranking with per-category change, spending by weekday, a **month calendar heatmap** with tap-to-inspect, most-bought items, biggest single spends |
| **Expenses** | Every expense grouped by day with day totals; search items/notes/categories/amounts, **all-time or this-period**, sort by newest or biggest, filter by category, tap to edit, swipe left to delete (with undo), swipe right to log it again today |
| **Budgets** | A monthly limit per category with presets; meters that band at 80% and 100% (*On track → Close to limit → Over budget*), what's left, and a safe amount per remaining day |
| **Projects** | One-off spending paid from savings (building a house, a wedding) — a separate ledger with its own totals, stages and estimate |
| **Vehicles** | Car and bike logbook: every tuning and service with date, odometer and cost, and when each job is due next |

## Who spent it

Every expense names the family member who spent it. A person filter (**Everyone · Abba · Ammi · …**) sits under the period filter on Overview, Insights and Expenses. Picking someone narrows every card on all three tabs at once — total, trend, categories, calendar, lists — the same way the period does. Pay and budgets stay household-wide, and the screen says so.

- **Overview** lists **every category with its own total** (groceries, fuel, bills…), biggest first, and a *Who spent it* card ranking each person's total. Tap a person to filter to them.
- **Expenses**: once a person, category or search narrows the list, a totals card shows exactly what the list adds up to, and splits it — by category, or, with a category picked, by person.

## Vehicles

A maintenance logbook for the household's cars and bikes:

- Log a **tuning, oil change, filter, brake job…** with its date, the **odometer reading**, the cost and the workshop.
- Picking a job fills its usual interval (bike tuning every 3,000 km or 6 months, car oil every 5,000 km or 6 months…). The fields stay editable — what the mechanic said is what is saved, on the record itself.
- **Next due = km interval or month interval, whichever comes first**, measured against the vehicle's current reading (the highest one logged). Jobs are *On schedule*, *Due soon* (within 10% of the km interval or 14 days) or *Overdue*.
- The Overview shows a *Vehicle service* reminder only when something needs attention.
- **Separate ledger**: service costs never enter monthly spending, budgets or savings, the same rule as Projects. Fuel stays an everyday expense.

## Pay and savings

Set your monthly pay and the Overview tab shows what you actually keep: pay, spent, saved, the savings rate, and how both spending and savings compare with last month.

Pay is stored **per month**, not as one global figure. A month with no entry inherits the most recent earlier one, so entering a raise applies from that month onward and never rewrites the savings history of the months before it. Spending more than you earned is shown as *overspent*, in words as well as colour.

## Adding expenses fast

Daily entry is meant to take seconds:

- **Item autocomplete** — type `chick` and it offers *Chicken* from your own history, with its category and the last price you paid. New accounts get the same completions from a built-in catalogue of ~90 household items.
- **Buy again chips** — one tap fills item, category and price.
- **Amount bumps** — `+50 +100 +200 +500 +1000` instead of typing.
- **Save & add another** — keeps the sheet open with the category and date, for a whole shopping trip.
- **Hold the + button** — logs your most recent expense again, dated today.
- **Swipe a row right** — the same, from the list.
- **Copy as spreadsheet** — ⋯ menu puts every expense on the clipboard as CSV.

A single filter row (Week/Month/Year + ‹ › stepping) scopes **everything** below
it, so no two cards can disagree about the numbers.

## Layout

```
lib/
  main.dart                     boot: init Supabase, build controllers, runApp
  app.dart                      MaterialApp + theme mode (+ SetupApp fallback)
  core/
    supabase_config.dart        url + publishable key (dart-define aware)
    app_theme.dart              validated palette, VizColors theme extension, ThemeData
    formatters.dart             PKR money, compact money, exact axis ticks, dates
    error_messages.dart         Supabase/transport error -> one actionable sentence
  models/
    app_user.dart               id, email, name of the signed-in account
    expense.dart                one spend (immutable, JSON)
    expense_category.dart       the 8 categories + their fixed palette slots
    period.dart                 Week/Month/Year, half-open DateRange, anchor maths
    analytics.dart              pure aggregation -> PeriodSummary (unit-tested)
    vehicle.dart                vehicle, service record, next-due maths (unit-tested)
    service_catalog.dart        usual car / bike service intervals
  data/
    auth_gateway.dart           AuthGateway interface + Supabase implementation
    expense_api.dart            ExpenseApi interface + Supabase implementation
    local_prefs.dart            theme choice + per-user read cache
  state/
    auth_controller.dart        session + auth form state
    expense_store.dart          expenses + period + derived summary, cache/sync
    theme_controller.dart       light/dark/system, persisted
  screens/                      auth_gate, auth_screen, home_shell, dashboard,
                                insights, expenses, editor sheet, setup notice
  widgets/                      charts, cards, tiles, filter bar, entrance animations
supabase/
  schema.sql                    table + index + RLS policies
```

State is `provider` + `ChangeNotifier`. `AuthGateway` and `ExpenseApi` are
interfaces, so the widget tests drive the real screens against in-memory fakes
([test/support/fakes.dart](test/support/fakes.dart)) — no network, no project
needed, and account isolation is actually asserted. All aggregation lives in
`Analytics` (no Flutter imports), so the numbers are testable without a widget
tree.

## How data flows

- **Reads**: the on-device cache paints first, then Supabase overwrites it. If
  the fetch fails, the cached numbers stay on screen and a banner appears with a
  Retry — the app stays readable with no connection.
- **Writes**: land in the device's database (SQLite; browser storage on web)
  and an outbox, so the app works fully offline. The outbox drains to Supabase
  whenever a connection is available, parents (projects, people, vehicles)
  before the rows that point at them.
- **Sessions** persist, so a returning user goes straight to the dashboard.
- **Names** are stored in the auth user's metadata (`full_name`) — no profiles
  table, no trigger.

## Chart decisions worth keeping

These are not stylistic preferences — changing them breaks accessibility:

- **Category colours come from a validated categorical palette** and are checked
  for colour-vision-deficiency separation in *both* light and dark. Eight is the
  ceiling; a 9th generated hue would be indistinguishable from an existing one.
  Colour follows the *category*, never its rank, so sorting never repaints a row.
- Category colour appears **only on small icon chips**, always beside the icon
  glyph and a text label — identity never rests on hue alone.
- **Magnitude marks (trend bars, share meters) use one hue** (the reserved blue
  ramp) with *emphasis* on the focused bar. Ranked bars are used instead of a
  donut: past three simultaneous slices no colour ordering stays separable.
- Bars: ≤24px, 4px rounded top, square on a single baseline; gridlines are solid
  hairlines; axis ticks are exact, never rounded.
- Up = red, down = green (for spending, more is worse), always with an arrow icon
  and a worded label, plus a spelled-out screen-reader label.
- The **Expenses tab is the table view**: every value a chart shows as a mark is
  readable there as a number.

## Not built yet

Deliberately out of scope: recurring expenses, multi-currency, and password
reset (needs redirect URLs and deep links).
