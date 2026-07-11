# KOReader Merchant Plugin

A turn-based trading game for KOReader. Buy low, sell high, fend off raiders,
and pay off the moneylender before 30 days are up. It's a numbers game at
heart — perfect for an e-reader.

## Themes
The rules are always the same, but you choose the setting from
**Tools → Merchant → Theme**:

- **Silk Road caravan** (default) — haul saffron and silk between
  Constantinople and Chang'an, hire guards, and watch out for bandits.
- **Star trader** — run antimatter and quantum cores between stations while
  pirates prowl the belt.
- **Clipper captain** — carry tea and porcelain between the great ports of the
  China trade, cannons at the ready.
- **Antique dealer** — hunt manuscripts and pocket watches across the city's
  markets and don't let the forgers swindle you.

A theme change takes effect when you start a new game; a run in progress keeps
its own theme. High scores are tracked separately per theme.

## How to play
Open it from the main menu under **Tools → Merchant → Play**. You can also
bind a gesture to it: the game registers an **Open merchant game** action, so
assign it under **Settings → Taps and gestures → Gesture manager** (in the
*General* action list).

- **Buy / Sell** — trade the goods listed in the current market. Prices change
  every day and at every stop, so profit comes from spotting a cheap market
  and selling where prices are high.
- **Travel** — move to another trading post. Each trip costs you a day. New
  prices are rolled and random events may happen on the road.
- **Moneylender** — you start 5,500 in debt and it grows 10% a day. Pay it
  down, or borrow more if you're feeling brave.
- **Bank** — stash money safely; the bank pays 5% a day.

Watch your **carrying capacity** (you can only haul so much) and your
**health**. Now and then someone will offer you protection or extra capacity,
and now and then raiders will attack — **Fight** (if you have protection) or
**Flee**.

After 30 days the game ends and your **net worth** (cash + bank − debt) is
scored against your all-time best for that theme. Progress is saved
automatically, so you can put the book down and pick the game back up later.

## Languages
The game follows KOReader's UI language. Besides English it ships with
German, Spanish, French, Italian, Portuguese, and Turkish. Translations live
in `merchant_l10n/<lang>.lua` — one file per language mapping the English
source string to its translation; copy an existing file to add a language.
Strings missing from a dictionary fall back to KOReader's own translations,
then to English.

## Files
- `_meta.lua` — plugin manifest.
- `main.lua` — the KOReader UI: full-screen game board, menus, and persistence.
- `merchant_game.lua` — pure game model and rules (no UI), so the logic can be
  reasoned about and tested on its own.
- `merchant_themes.lua` — the theme definitions: goods, places, and all the
  narration for each setting.
- `merchant_l10n.lua` + `merchant_l10n/` — plugin-local translations (see
  above).

## Installation
1. Copy the `merchant.koplugin` folder into KOReader's `plugins` directory.
2. Restart KOReader.
