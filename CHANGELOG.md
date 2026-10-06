# Changelog

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
