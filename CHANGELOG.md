# Changelog

## 1.2.1

- Added weekly checks for updated Phoenix data.
- Equipment estimates now include Kyoshu Kyahan's accuracy bonus while Footwork is active.

## 1.2.0

More accurate TP, attack and recovery estimates, with clearer explanations, more ways to arrange the timers and safer settings changes.

- TP estimates include known Store TP traits, merits, equipment, augments, food and effects, plus Dual Wield and Martial Arts gear. Your actual gains still refine the estimate.
- Choose a TP goal of 1000, 2000 or 3000. Successful hits shows how many of your own hits remain, separately from rounds. Time to TP goal can show approximate seconds once enough timing and hit information is available.
- Resting predictions include Clear Mind, eligible Signet bonuses, equipment, augments, food and known effects. Time until full can appear before your first tick. Optional Next tick gains and Ticks until full readouts mark uncertain estimates.
- Recovery estimates count Regen, Refresh and drains on their separate three-second passes. Full times follow the learned resting pattern. Recovery goals show time to a chosen HP/MP amount or percentage without changing the full recovery sound. Finishing between ticks says "full before next tick".
- Attack estimates count gear haste and slow, flat and percentage delay changes, and known conditional bonuses. Relevant gear swaps update the next interval. Percentage delay uses Phoenix's haste limit, and Hundred Fists starts from the correct delay with staves and clubs too.
- Blue Magic spells contribute their stat bonuses and relevant traits. Changing spells updates the estimate, and Details shows spell names, trait tiers and whether the set is confirmed. Known Assault conditions also count; missing information stays estimated.
- Refreshing a speed effect starts fresh timing observations even when its icon stays. A new target or an accuracy or extra-attack gear change restarts recent hit-rate estimates while keeping valid TP per hit.
- The Details tab explains each estimate, its sources, observations and missing bonuses. Speed details separates raw and applied bonuses and shows the caps. Search, collapsible groups, Copy shown, Copy all and separate relearn buttons help you find and share what you need.
- Hover over a timer for a short explanation. `/cadence info` lists known bonuses and remaining estimates. `/cadence info details` adds their contributions and timing evidence. Optional recording and `/cadence report` save a local timing report.
- The enemy timer keeps following slow attackers through their expected round and shows "waiting" when an attack is overdue. Longer Elegy effects no longer teach a slowed speed as normal. The "TP move" and "casting" row stays visible when other text is hidden.
- Observed Sleep, Stun, Petrification and Terror hold the enemy timer. Interrupted gaps do not teach a new attack speed, and old observations clear when a monster leaves sight.
- Supported spells you cast keep the gear, buffs and merits from when they landed for their duration estimates. An estimated expiration never claims an exact next attack. Expired speed effects are cleared before timing resumes after paralysis or an instant action.
- Direct heals, drains and spikes no longer teach false Regen or Refresh. Late healing messages can still correct a mistaken sample. Attacks arriving together no longer teach a zero-length delay, and incomplete action messages cannot change the timers.
- Unchanged vitals and Regen-only updates no longer restart the resting timer or erase the last HP gain on jobs without MP.
- HP and MP full times stay independent when one recovery amount is unknown. Timing reports can save live buff, equipment and merit lists.
- Fixed dropped game updates that left resting gains and full times blank and attack timers without new observations.
- Hold Shift and drag a timer's bottom edge to shrink or grow its whole height, including text and spacing. The corner changes width and height together, and Text only can resize vertically too. Each timer also has a Height slider; Bar height still sets just the colored bar's thickness.
- Character and zone changes clear pending TP samples and old fight evidence while keeping eligible learned gains through zoning.
- Added Mint and Lavender skins for the timers, settings window and chat colors. Ready, almost ready, full and enemy warning colors stay distinct.
- Appearance replaces the Look tab and brings Window and Window colors into separate collapsible sections. You can fold each window color group. Existing settings and commands still work.
- Find settings highlights matching controls, with Previous and Next match buttons and a counter. Tabs wrap above scrolling pages, and search opens matching folded sections while keeping your usual folds for afterward. Search controls fit narrow windows, and a blank search leaves your folds alone.
- Hide unused tabs in Appearance or restore them all. Their features keep running, and search or a Details shortcut can reveal a hidden tab. Appearance stays available. Tab choices stay with each character, including while sharing a layout.
- Minimal, Melee / TP, Resting and Enemy tracking starter layouts explain their changes and can be previewed before applying. They keep your colors, fonts, labels, positions, goals, sounds and saved profiles.
- Appearance has an embedded timer and chat sample. The Preview tab has selectable sample states, pause and optional alignment guides for arranging timers. Samples leave live observations and sounds alone.
- Timer readouts have an Enabled only filter and expandable options. Details shortcuts open the matching timing explanation. Text only is the clearer name for hiding a bar while keeping its text.
- Undo keeps the last eight settings changes, including timer moves, resizing, profile loads and starter layouts. Commands finish a pending control edit as its own step, and repeating layout sharing keeps your history. Reset one section without resetting the rest. Interrupted drags cannot carry an Undo layout to another character or survive Reset all.
- Profiles show Using or Modified from so you can see which setup you started with. Undo overwrite restores the previous saved version only if nobody changed it again. Undo delete restores the last deleted profile without replacing newer names or job links.
- Profile and shared-layout saves keep the previous file if writing fails. Failed profile loads report the problem. Closing settings or changing characters finishes pending shared edits. A failed character-switch save keeps the shared edit available to retry, and each character keeps their own tab choices and job links.
- Editing settings stays solid under Shift, including controls on scrolling pages. Timer drawing, search highlights, profile status and estimates do less repeated work while continuing to watch for changes. Resting readouts share one full-recovery forecast, and stat polling and Undo use less memory.

## 1.0.0

First release.

- An auto attack timer that counts down to your next attack. It starts from the delay of the weapons you have on, then learns your real delay from your own attacks, so it covers gear haste too. What it learns stays through zoning, kept for each mix of weapons, jobs, levels and haste buffs.
- The auto attack timer holds for job abilities, weapon skills, spells, items and ranged attacks the way the server does. Sleep, stun, petrification, terror and the like stop it where it is, and it carries on once they wear off.
- While a spell, item or ranged attack runs, or sleep, stun or the like is on you, the auto attack bar dims and says why, like "casting" or "asleep".
- The auto attack bar says "too far" or "not facing" as soon as you step out of reach or turn away from the monster you're fighting.
- Your TP under the auto attack bar, with about how many rounds until 1000. It learns how much TP your hits really give, and counts the TP you've been getting from being hit and from Regain too. Your TP turns its own color at 1000.
- A resting timer that follows Phoenix's 9, 9, 12 second ticks. It shows what your last tick restored and how long until you're full, or when your HP and your MP will each be full. It can flash on each tick and hide once you're full.
- The resting bar dims and says "diseased", "plagued" or "cursed" while one of those keeps your ticks from healing you. It stays in step with the ticks the whole time.
- A sound that plays once resting fills your HP and MP. It's off until you turn it on. Two sounds come with cadence, FF VII Save and FF IX Moogle, and FF VII Save is picked to start. You can also put your own .mp3 or .wav files in `config\addons\cadence\sounds\`. It has its own volume and a Play button.
- An enemy attack timer, off by default. It follows your target or whoever is hitting you, and stays on its monster while you target a party member, an NPC or nothing. It learns the monster's speed and counts Slow, Elegy, Haste and Hundred Fists on it.
- The enemy attack timer says "TP move" or "casting" while the monster readies a TP move or casts a spell. Its name and stripe turn a color you pick when the monster's last attack was on you.
- The enemy attack timer remembers the speed of each monster it follows by name and zone, so the next one with that name there starts from it.
- The enemy attack timer can sit right under the auto attack timer as a slim strip that moves with it.
- Six presets. They're Phoenix, Classic FFXI, Minimal, High contrast, Ember and Colorblind safe. Each one sets the timers' colors, card, text shadow and corners, and cadence's chat colors.
- Once you change a preset's colors, the Preset list says which one you started from, like Custom (from Phoenix). Picking it again puts its look back. Undo takes back your last preset or Reset look.
- Change any color, the corner roundness, the font, the overall size and the size of the numbers, names and small text. Add a text shadow or outline, and pick the card's background, border and accent stripe. Hide a timer's name or type your own. Bars can fill or drain, or you can show just the numbers.
- Any .ttf or .otf you put in `config\addons\cadence\fonts\` shows up in the Font list.
- Hold Shift and drag a timer to move it, or drag its edges to resize it. You can lock the timers in place, or have the auto attack and resting timers share one spot. A timer past the edge of a smaller game window is drawn just inside it.
- The timers and the settings window hide during cutscenes and NPC conversations, on the map and while you've hidden the game's interface. `/cadence hide` hides the timers until you type it again.
- A settings window with tabs for the timers, the enemy timer, the look, the window and its colors, and your profiles. Every setting has a (?) that explains it. You can move and resize the window, and it opens where you left it. Hold Shift to see through it.
- The settings window takes the colors, corners and spacing of the preset you pick. Untick Window matches the look and presets leave the window as it is. It has a font and font size of its own, and each of its colors has a swatch on the Window colors tab.
- Pick the colors of cadence's lines in chat, the [cadence] tag and the answer after it, on the Window tab or with `/cadence chatcolor`. Print a sample shows them in your chat.
- A command for every setting in the settings window, sliders, colors and labels included. `/cadence help` lists them, and `/cad` is short for `/cadence`.
- `/cadence info` says what cadence has worked out about you, to paste into a bug report.
- Settings for each character, or one layout for all of them.
- Save every setting as a named profile and load it on any character. Link a profile to a main job and it loads when you change to that job and zone.
- cadence checks your settings on load, on login and before each save. A number outside its slider's range is pulled back in, and anything cadence can't use goes back to its default.
