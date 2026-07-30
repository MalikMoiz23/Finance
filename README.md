# Finance — home expense tracker

Flutter app for tracking household spending: log an expense, then read it back by
**week / month / year** and see which categories the money went to.

Currency is **PKR** (`Rs 1,250`, no decimals). There is **no database** — expenses
are stored as one JSON string in `shared_preferences`, so data survives a restart
but stays entirely on the device.

## Run it

```bash
flutter pub get
flutter run              # pick a device; also runs on Windows/Chrome
flutter test             # 22 tests: aggregation maths + full-app widget tests
flutter analyze
```

First launch seeds ~4 months of sample expenses so the charts aren't empty.
**Overview → ⋯ → Clear all expenses** wipes it (sample data does not come back).

## Screens

| Tab | What it does |
|---|---|
| **Overview** | Period filter, total spent + change vs the previous period, spend-over-time bars, top 5 categories, recent expenses |
| **Insights** | Stat tiles (total, per day, biggest category, priciest weekday), full category ranking with per-category change, spending by weekday, biggest single spends |
| **Expenses** | Every expense in the period, grouped by day with day totals; search, filter by category, tap to edit, swipe to delete with undo |

A single filter row (Week/Month/Year + ‹ › stepping) scopes **everything** below
it, so no two cards can disagree about the numbers.

## Layout

```
lib/
  main.dart                     boot: load storage, then runApp
  app.dart                      MaterialApp + theme mode
  core/
    app_theme.dart              validated palette, VizColors theme extension, ThemeData
    formatters.dart             PKR money, compact money, exact axis ticks, dates
  models/
    expense.dart                one spend (immutable, JSON)
    expense_category.dart       the 8 categories + their fixed palette slots
    period.dart                 Week/Month/Year, half-open DateRange, anchor maths
    analytics.dart              pure aggregation -> PeriodSummary (unit-tested)
  data/
    expense_repository.dart     shared_preferences read/write
    demo_data.dart              seeded sample expenses
  state/
    expense_store.dart          ChangeNotifier: list + period + derived summary
    theme_controller.dart       light/dark/system, persisted
  screens/                      home_shell, dashboard, insights, expenses, editor sheet
  widgets/                      charts, cards, tiles, filter bar, entrance animations
```

State is `provider` + `ChangeNotifier`. All aggregation lives in `Analytics`
(no Flutter imports), so the numbers are testable without a widget tree.

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

Deliberately out of scope for v1: income/balance, per-category budgets, recurring
expenses, multi-currency, cloud sync, CSV export.
