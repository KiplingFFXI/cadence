# cadence

cadence is an Ashita v4 addon for Phoenix. It shows auto attack and resting timers, TP estimates, and an optional enemy attack timer. Choose the readouts you need, change their look, and arrange them on screen.

Phoenix staff approved cadence for use on Phoenix. Author: **Kipling**.

[Download the latest release](https://github.com/KiplingFFXI/cadence/releases/latest) | [Full guide](docs/GUIDE.md) | [What's changed](CHANGELOG.md)

## Install or update

1. Download `cadence-<version>.zip` from the release page.
2. If updating, type `/addon unload cadence` first or close the game, then remove the old `addons\cadence` folder.
3. Extract the zip into your Phoenix `addons` folder. You should have `addons\cadence\cadence.lua`.
4. In game, type `/addon load cadence`.

To load it automatically, enable cadence under **Manually installed** on the Phoenix launcher's Addons page. Alternatively, add `/addon load cadence` to `scripts\default.txt`, outside the launcher's managed block. Use one method.

Leave `config\addons\cadence\` in place when updating. It holds your settings, profiles, and custom sounds and fonts.

## Start here

Type `/cadence` to open settings. Auto attack and resting timers start enabled. The enemy timer starts off. Use **Timers** and **Enemy** to choose what shows, or preview a starter layout under **Profiles** before applying it.

- **Appearance** holds eight skins, colors, fonts and visible tabs. Set each timer's width and Height under Timers or Enemy.
- **Preview** shows sample states for arranging the timers. Hold Shift and drag to move a timer; drag its right edge for width or bottom edge for overall height.
- **Find settings** searches controls and their help. **Details** explains estimates, observations and missing inputs, with search and copy buttons.
- **Undo last change** restores up to eight recent settings edits. Save a profile when you have a setup you want to keep, or share one layout across characters.

## What it shows

- Auto attack timing, including known haste, slow and delay changes, plus action holds and range or facing warnings.
- Optional re-engage estimates after combat ends. Turn on Show re-engage timer under Timers; the bar hides automatically after the estimate ends.
- TP toward a goal of 1000, 2000 or 3000, with rounds, successful hits and optional time-to-goal estimates.
- Resting ticks, HP/MP gains, time until full and optional recovery goals. Known traits, gear, food, Regen and Refresh inform the estimates.
- Optional enemy attack timing, observed slow and haste, disabling effects, casting and TP-move holds.

Starting estimates use Phoenix's rules and known bonuses, then refine from your observed attacks and recovery. Missing information stays estimated. Hover a timer for a short explanation, or [read the timing details and limits](docs/GUIDE.md#how-the-auto-attack-timer-works).

cadence only reads the game and displays information. It sends no requests or game commands and never writes to game memory. Optional resting sounds and timing reports stay local. [What cadence reads and saves](docs/GUIDE.md#what-cadence-reads).

## Source and license

Data and calculations follow [Phoenix's source](https://github.com/phoenixffxi/Phoenix). cadence uses [GNU GPL v3.0](LICENSE). The two bundled sounds are from Final Fantasy VII and Final Fantasy IX, belong to Square Enix, and are not covered by the GPL.
