# cadence

cadence is an Ashita v4 addon for the Phoenix FFXI private server. It shows an auto attack timer that counts down to your next attack, with your TP under it. It also counts down to your next resting tick. If you turn it on, it shows when a monster will attack next. You can restyle the timers, and you move them by holding Shift and dragging.

Its timings come from the Phoenix server's own code, so they match what the server does instead of general FFXI numbers.

> **Phoenix staff approved cadence, so you can use it on Phoenix.** cadence reads what your game already knows and draws it on screen. It never sends anything to the server, hides anything the server sends, writes to game memory or sends commands to the game. That goes for the enemy attack timer, the TP line and the range and facing warning too. The resting sound only plays a sound file through Windows, once resting fills your HP and MP or when you press Play.

## Features

- **Auto attack timer.** A thin bar that fills up until your next auto attack. It starts from the delay of the weapons you have on, then learns your real delay from your own attacks. That way it also covers gear haste the game can't show. It holds for job abilities, weapon skills and spells the same way the server does.
- **Your TP.** A line under the auto attack bar shows your TP. Next to it is about how many rounds until 1000, from how much TP your hits really give and what being hit or Regain has been adding.
- **Resting timer.** A countdown to your next HP and MP tick while you /heal. Resting ticks on Phoenix land 9, 9 and 12 seconds apart instead of every 10. cadence follows that pattern by watching your real ticks. It also shows what your last tick restored, and says "full" once your HP and MP are topped off.
- **Enemy attack timer (off by default).** Shows when a monster will attack next, from the attack packets your game already gets. It follows your target or whoever is hitting you, and counts Slow, Elegy, Haste and Hundred Fists on the monster. It can sit under your auto attack timer as a slim strip.
- **Full look controls.** Start from one of six presets. They're Phoenix, Classic FFXI, Minimal, High contrast, Ember and Colorblind safe. Then change any color, the corner roundness, the font, the overall size and the size of the numbers, names and small text. Add a text shadow or outline, and choose the card's background, border and accent stripe. Set each timer's width and bar height. Hide a timer's name, or type your own. Bars can fill or drain, or you can show just the numbers. The default look matches the Phoenix site and launcher.
- **Extras you can switch on or off.** An "almost ready" color for the last moment before an attack, with a mark on the bar where it starts. A flash on each resting tick. A sound once resting fills your HP and MP, one of the two that come with cadence or an .mp3 or .wav of your own. Time until full on the resting timer, like "full in 28s", or when your HP and MP will each be full. Hiding the resting timer once you're full. A shared spot so both timers use one place on screen. Hiding during cutscenes and NPC conversations, while the map is open or while you've hidden the game's interface.
- **Settings for each character, or one layout for all.** Ashita saves your settings for each character. Tick "One layout for all characters" and every character uses the same setup.
- **Profiles.** Save your whole setup under a name, like "Solo BLM", and load it again on any character. Link a profile to a main job and it loads when you change to that job.

## Installing

1. Download `cadence-<version>.zip` from the newest release at https://github.com/KiplingFFXI/cadence/releases.
2. Extract the zip into your Phoenix `addons` folder, for example `C:\Games\PhoenixXI\addons`. The zip holds the `cadence` folder, so you end up with `addons\cadence\cadence.lua`.
3. In game, type `/addon load cadence`.
4. To load it every time, open the Phoenix launcher, go to Addons, pick "Manually installed" and switch cadence on. Or add `/addon load cadence` at the bottom of `scripts\default.txt`, outside the block the launcher manages. Only do one of those, or it loads twice.

Your settings live in `config\addons\cadence\`, outside the addon folder, so updating the addon keeps them. cadence checks them on load, on login and before each save. A number outside its slider's range is pulled back in. Anything cadence can't use goes back to its default.

To update, type `/addon unload cadence` first, or close the game. Then delete your old `addons\cadence` folder, extract the new zip in its place the same way you installed it, and type `/addon load cadence`. Your profiles and your own sounds and fonts are in `config\addons\cadence\` too, so they carry over.

## Commands

| Command | What it does |
|---|---|
| `/cadence` | Opens or closes the settings window. |
| `/cadence attack [on\|off]` | Turns the auto attack timer on or off. |
| `/cadence resting [on\|off]` | Turns the resting timer on or off. |
| `/cadence enemy [on\|off]` | Turns the enemy attack timer on or off. |
| `/cadence attack <part> [on\|off]` | Turns one box of the auto attack timer on or off, like `/cadence attack tp off`. The parts are `seconds` (Seconds left), `delay` (Weapon delay), `tp` (Your TP), `rounds` (Rounds to 1000), `numbers` (Numbers only), `mark` (Ready mark), `almost` (Almost ready), `range` (Range / facing), `why` (Why it stopped) and `label` (Show its name, the box in front of its label on the Look tab). |
| `/cadence resting <part> [on\|off]` | The same for the resting timer. The parts are `seconds` (Seconds left), `gains` (Last tick gains), `untilfull` (Time until full), `fulltimes` (Full times), `numbers` (Numbers only), `hidefull` (Hide once full), `flash` (Flash on each tick), `why` (Why it can't heal), `sound` (Sound, the box in front of the Sound list) and `label` (Show its name). |
| `/cadence enemy <part> [on\|off]` | The same for the enemy attack timer. The parts are `keeplast` (Keep the last monster), `attach` (Attach under auto attack), `seconds` (Seconds left), `name` (Enemy name), `speed` (Attack speed), `effects` (Slow and haste), `tpmove` (TP move / casting), `onyou` (On you), `numbers` (Numbers only), `mark` (Ready mark), `almost` (Almost ready) and `label` (Show its name). |
| `/cadence enemy follow first\|target\|hits` | Sets Follows to My target first, My target only or Whoever hits me. |
| `/cadence attack\|resting\|enemy <slider> <number>` | Sets one of that timer's sliders, like `/cadence attack width 300`. Every timer has `width` (Width, 120 to 640) and `barheight` (Bar height, 2 to 32). The auto attack and enemy timers have `almostat` (Almost ready at, 0.1 to 2.0 seconds), and the resting timer has `flashlength` (Flash length, 0.2 to 1.5 seconds) and `soundvolume` (Volume, 0 to 100). |
| `/cadence attack\|resting\|enemy labeltext <text>` | Types that timer's label, the same as its box under LABELS on the Look tab, like `/cadence attack labeltext AA`. It needs no quotes, and keeps up to 23 characters from an English keyboard. `/cadence attack labeltext ""` puts the timer's own name back. |
| `/cadence resting soundfile <name>` | Picks the sound that plays once resting fills your HP and MP, the same as the Sound list on the Timers tab, like `/cadence resting soundfile ff ix moogle`. It's one of the two sounds that come with cadence or one of the .mp3 and .wav files in `config\addons\cadence\sounds\`, with or without its .mp3 or .wav. Capital letters don't matter, and the name needs no quotes. cadence looks in the folder again first, so a file you just put there works. |
| `/cadence resting playsound` | Same as Play. Plays the sound now at its volume, even with the sound turned off. |
| `/cadence hideevents\|hidemap\|hideui [on\|off]` | Sets Hide during events, Hide on the map or Hide with the game UI. |
| `/cadence <word> [on\|off]` | Sets a box on the Look tab. The words are `windowlook` (Window matches the look), `labels` (Show labels), `background`, `border`, `accent` (Accent stripe), `outline` (Text outline), `shadow` (Text shadow), `drain` (Drain instead of fill), `onespot` (Share one spot), `onelayout` (One layout for all characters) and `peek` (Peek with Shift). |
| `/cadence <slider> <number>` | Sets a slider on the Look tab. The sliders are `scale` (Scale, 0.5 to 2.5), `textsize` (Text size, 10 to 28), `detailsize` (Detail size, 8 to 32 or `auto`), `labelsize` (Label size, 8 to 32 or `auto`) and `corners` (Corner roundness, 0 to 12). |
| `/cadence color <what> <rrggbb>` | Sets one of the timers' colors, the same as its swatch, like `/cadence color attack_ready ffffff`. Two more digits set how solid it is, from `00` for clear to `ff` for solid, like `c55151cc`. A timer's color starts with its word, like `attack_tp` or `enemy_on_you`. The Look tab's are `background`, `border`, `accent`, `labels`, `values`, `details`, `bar_track` and `outline`. `/cadence help colors` lists them all. |
| `/cadence preset <name>` | Picks a preset the same way the Preset list does, so Undo can take it back. The names are `phoenix`, `classic`, `minimal`, `contrast`, `ember` and `colorblind`. The full names work too. Naming the preset you already have does nothing. Once you've changed a preset's look, naming that preset again puts its look back. |
| `/cadence undo` | Same as Undo. Puts back the look you had before your last preset or Reset look. |
| `/cadence font <name>` | Picks a font from the Font list, with or without its spaces, like `/cadence font tahoma bold` or `/cadence font tahomabold`. `ashita` is Ashita's own pixel font. |
| `/cadence windowfont <name>` | Picks the settings window's font, the same as the Font list on the Window tab, with or without its spaces, like `/cadence windowfont segoe ui`. The fonts are Ashita, Segoe UI, Arial, Tahoma, Verdana, Calibri and Consolas. A font that won't load is still picked, and cadence says so. |
| `/cadence windowfontsize <12-24>` | Sets the settings window's font size in pixels, the same as Font size on the Window tab. |
| `/cadence windowcorners <0-12>` | Sets how round the settings window's corners are, in pixels. 0 is square. |
| `/cadence windowspacing <2-14>` | Sets the space between the settings window's rows, in pixels. |
| `/cadence windowcolor <what> <rrggbb>` | Sets one of the settings window's colors, the same as its swatch on the Window colors tab, like `/cadence windowcolor buttons 3a2525`. Two more digits set how solid it is, from `00` for clear to `ff` for solid, like `c55151cc`. `/cadence help windowcolors` lists the colors. |
| `/cadence chatcolor <what> <color>` | Sets one of cadence's chat colors, the same as its list under CHAT on the Window tab, like `/cadence chatcolor replies lawn green`. `<what>` is `tag_brackets`, `tag_word` or `replies`. The color is its name, with or without its spaces, or its number. `/cadence help chatcolors` lists them. |
| `/cadence profile save <name>` | Saves your settings as a new profile, the same as Save as new on the Profiles tab, like `/cadence profile save Solo BLM`. Capital letters don't matter in a profile name, so a name another profile has in any case is refused. |
| `/cadence profile overwrite <name>` | Saves your settings over that profile, the same as Overwrite. |
| `/cadence profile load <name>` | Loads that profile, the same as Load. Undo can't take it back. |
| `/cadence profile rename <old> <new>` | Gives a profile a new name, the same as Rename. Put a name with spaces in quotes, like `/cadence profile rename "Solo BLM" Nuker`. The other profile commands take one with or without quotes. Your job links to it follow. |
| `/cadence profile delete <name>` | Deletes that profile, the same as Delete, and your job links to it. |
| `/cadence joblink <job> <profile>` | Links a profile to a main job, the same as that job's list under JOB LINKS on the Profiles tab, like `/cadence joblink blm Solo BLM`. The profile loads when you change to that job and zone. The job is its short name, from `war` to `pup`. Capital letters don't matter, and the name needs no quotes. |
| `/cadence joblink <job> none` | Stops that job loading a profile. `(none)` works too, the way the list shows it. |
| `/cadence lock` / `unlock` | Stops or allows moving the timers with Shift + drag. |
| `/cadence reset` | Puts the timers back where they started. On a screen too short for them, they start higher up. |
| `/cadence reset look` | Same as Reset look. `/cadence undo` takes it back. |
| `/cadence reset all` | Puts every setting back to its default, including where the timers sit and which ones are on, and clears your job links. Type it twice within 10 seconds. Undo can't take it back. Your saved profiles stay. The settings window keeps its spot and size, and One layout for all characters stays as it is. While that's on, every character gets the defaults. |
| `/cadence hide` | Hides the timers until you type it again. `/cadence show` and Show them in the settings window bring them back too. It isn't saved, so they also come back when the addon reloads or the game restarts. |
| `/cadence info` | Says in chat what cadence has worked out about you right now. That's the version, your auto attack delay and where it came from, how many learned delays are saved, your TP per hit, and whether the resting timer knows the 9, 9, 12 pattern. In a fight, with the auto attack timer and Your TP on, it also says about how much more TP a round has lately come from things like being hit or Regain, when that's at least 1. Out of a fight, the delay is the one your next fight starts on. It says nothing about monsters. If a timer looks off, paste these lines into your bug report. |
| `/cadence help [word]` | Lists the commands by tab. `/cadence help attack`, `resting` or `enemy` lists that timer's parts, sliders, label and colors, and for the resting timer its sound commands too. `/cadence help look` lists the Look tab's sliders, labels and colors, and `/cadence help colors` lists every timer color. `/cadence help preset`, `font` or `reset` says more about one. `/cadence help window` and `/cadence help windowcolors` list the commands for the Window and Window colors tabs, `/cadence help chatcolors` lists the chat colors, and `/cadence help profiles` lists the profile and job link commands, your profiles and your job links. |

Every setting in the settings window has a command. Leave out on|off and a switch flips, so one macro line can turn it on and off. Each command says in chat what it did. A wrong word gets one line that says what to type. So does a number outside its slider's range, or a number that isn't whole for a slider that only takes whole numbers. A number with more decimal places than its slider shows is rounded, like 0.66 to 0.7. `/cad` works as a short version of every command.

## Moving and styling

Hold Shift and drag any timer to move it. Drag its right edge to change its width, its bottom edge to change the bar height, or the bottom right corner for both. The timer under your mouse gets an outline while Shift is down. Shift does nothing to the timers while you type in the game's chat line, so capital letters can't grab one. The enemy strip attached under the auto attack timer moves with that timer and takes its width.

While the settings window is open, a timer with nothing live to show uses sample values. That way you can place and style the timers without being in a fight or resting. "Reset positions" stacks them neatly at whatever size you've picked.

A timer whose spot is past the edge of a smaller game window is drawn just inside it. Its spot stays where you put it, so a bigger window shows it there again.

Drag the settings window's edges or its bottom right corner to resize it. Its sections sit in two columns when there's room and stack into one when it's narrow. It opens where you left it, at the size you left it. When another character logs in while it's open, it moves to that character's spot and size.

The settings window has a font and font size of its own, Ashita's font at 18 px to start. The fonts are Ashita, Segoe UI, Arial, Tahoma, Verdana, Calibri and Consolas, and the size goes from 12 to 24 px. They're loaded once when cadence loads. At a bigger size the window's layout grows with the text, so its sections may stack into one column and scroll. A font that draws wider than Ashita's does the same. Consolas at 18 px is as wide as Ashita's font at 20, so at the default 920x680 its sections stack into one column and the window scrolls. At a smaller size the layout stays as it is at 18 px. The smallest the window can go grows with the font too, and always has room for every tab's name. If the font's file is missing or won't load, the window uses Ashita's font at your size, and a note under Font size on the Window tab says so.

## Settings

Everything below is in the settings window (`/cadence`). Every setting there has a (?) you can hover for a short explanation. Ctrl+click a slider to type a value. While a timer is off, its settings are drawn faint, and they still work.

### Timers tab

| Option | What it does |
|---|---|
| Your TP | On by default. Shows your TP under the auto attack bar. It turns the color you pick once you're at 1000. |
| Rounds to 1000 | On by default. Shows about how many rounds until 1000 TP, next to your TP. TP from being hit and from Regain counts too. |
| Numbers only | Hides a timer's bar and shows just its numbers. The enemy timer has its own on the Enemy tab. |
| Ready mark | A small mark on the bar where the almost ready color starts. The enemy timer has its own on the Enemy tab. |
| Almost ready | On by default. The auto attack bar changes color just before your next attack, so you can line up a weapon skill. Almost ready at sets how early, 0.5 seconds by default. |
| Range / facing | On by default. While you're engaged, the auto attack bar says "too far" or "not facing" and dims as soon as you step out of reach or turn away from the monster you're fighting. cadence works it out from where you both stand. Once the bar is full, the server's own message wins until your next attack. |
| Why it stopped | On by default. While a spell, ranged attack or item holds your auto attack, the bar dims and says "casting", "ranged" or "item" instead of the seconds. Sleep, stun and the like do the same with "asleep", "stunned", "petrified", "terrified" or "penalty". It counts again once that ends. |
| Time until full | On by default. Shows "full in 28s" on the resting timer, worked out from how much each tick restores. |
| Full times | Adds a line under the resting bar that says when your HP and your MP will each be full. |
| Hide once full | Hides the resting timer once your HP and MP are full. |
| Flash on each tick | On by default. The resting timer flashes when a tick lands. You can pick its color, and Flash length sets how long it lasts. |
| Why it can't heal | On by default. While disease, plague or a curse keeps your ticks from healing you, the resting bar dims and says "diseased", "plagued" or "cursed" instead of the seconds. The gains, time until full and full times hide while it's on, and come back once your ticks heal you again. At full HP and MP it still says "full". |
| Sound | Off by default. Plays a sound once resting fills your HP and MP. Tick the box in front of the list to turn it on, and pick a sound in the list. Two sounds come with cadence, FF VII Save and FF IX Moogle, and FF VII Save is picked to start. To add your own, put .mp3 or .wav files in `config\addons\cadence\sounds\`. cadence makes that folder when it loads. The list shows cadence's sounds first, then yours. If one of yours has the same name as one of cadence's, cadence's plays and yours is left out of the list. |
| Refresh | Looks in the sounds folder again, so a file you just put there shows up in the list. cadence also looks each time the settings window opens. |
| Volume | How loud the sound plays, from 0 to 100. It's 100 by default. |
| Play | Plays the sound now, so you can hear it. It works with the box off too. If the file won't open or play, a note under Play says so. Chat says so too when you turn Sound on, pick the file while Sound is on, or press Play. |
| Hide during events | On by default. Hides the timers during cutscenes and NPC conversations, the same way XIUI's "Hide During Events" does. The settings window hides too and comes back when the event ends. Shop windows, the auction house and fishing aren't events, so nothing hides while they're open. Map sellers and conquest guards sell through a conversation, so cadence hides there. |
| Hide on the map | On by default. Hides the timers and the settings window while any map view is open, like XIUI does. The widescan list doesn't count as a map. |
| Hide with the game UI | On by default. Hides the timers and the settings window while you've hidden the game's interface (Scroll Lock by default), like XIUI does. |

### Enemy tab

| Option | What it does |
|---|---|
| Follows | Which monster the enemy attack timer follows. My target first follows your target, and whoever is hitting you when your target isn't fighting. My target only and Whoever hits me stick to just one of those. |
| Keep the last monster | On by default. With Follows on My target first or My target only, the timer stays on its monster while you target a party member, an NPC or nothing. That way it doesn't go away each time you cure someone. It lets go once that monster dies, stops fighting or goes 10 seconds without an attack, TP move or spell. A monster that attacks slower than that gets one and a half times its own delay. Targeting another monster switches to it, the same as with this off. It's greyed out with Whoever hits me. |
| Attach under auto attack | Puts the enemy attack timer right under your auto attack timer as a slim strip that moves with it. It's as wide as that timer, with smaller text and a thinner bar. With the auto attack timer turned off, it sits at its own spot, and you can move it there with Shift. |
| Slow and haste | On by default. Shows "slow", "elegy", "haste" or "hundred fists" after the attack speed while one is on the monster. The timer counts them either way. |
| TP move / casting | On by default. While the monster readies a TP move or casts a spell, the timer says "TP move" or "casting" instead of the seconds. |
| On you | On by default. The timer's name and the stripe down its left side turn the color you pick when the monster's last attack was on you. With Whoever hits me, the last attack is always on you, so it's greyed out. It's also greyed out when the timer's name and the accent stripe are both hidden, since there's nothing left to color. |

### Look tab

| Option | What it does |
|---|---|
| Preset | Sets the colors, card, text shadow and corner roundness in one click, and cadence's chat colors too. It shows the look you have. You can still change any of them after. Once you do, it says Custom and names the last preset you picked, like Custom (from Phoenix). Pick that preset again to put its look back, and Undo brings your changes back. With Window matches the look on, the settings window takes the preset's colors, corners and spacing too. Ember is warm browns and orange, with gold for almost ready. Its enemy bar is ash grey and turns red when the monster is ready. Colorblind safe uses Okabe and Ito's colorblind palette. Filling bars are blue, almost ready is vermillion, and ready or full is yellow. Each step differs in brightness as well as color. The enemy bar is grey so its warnings stand out. |
| Undo | At the right end of the PRESET heading. Puts back the look you had before your last preset or Reset look, along with the settings window's look if they changed it. For Reset look that includes sizes, labels and the settings window's font. It goes back one step. It's cleared when the addon reloads, another character logs in or you load a profile. |
| Reset look | Next to Undo. Puts sizes, colors, the card, corner roundness, text shadow and outline, labels, font, Numbers only, Ready mark, Drain instead of fill and the chat colors back to default. The settings window goes back to the Phoenix colors, corners and spacing and to Ashita's font at 18 px too, even with Window matches the look off. Presets never change the settings window's font. Positions, the lock and the other timer options stay as they are. |
| Window matches the look | On by default. Picking a preset also sets the settings window's colors, corner roundness and spacing, the ones on the Window and Window colors tabs, and Undo takes them back too. While it's on, the Preset list counts the window too, so it says Custom if the window doesn't match. Turn it off and presets leave the window as it is. Turning it on or off changes nothing by itself. The next preset you pick does. The timers on screen are the same either way. |
| Detail size | How big the small text is, like the delay next to AUTO ATTACK, the gains next to RESTING and the lines under the bars. At auto it's a little smaller than the numbers and grows with Text size. Small text bigger than the numbers makes its row taller. |
| Corner roundness | The timers' corners, from square (the Phoenix site look) up to fully rounded bars. |
| Show labels | On by default. Shows each timer's name, like AUTO ATTACK. It sits at the right end of the LABELS heading. Untick the box in front of a label to hide just that timer's name. Its seconds and small text still show. The box in front of the Enemy label hides the timer's own name, not the monster's. Enemy name on the Enemy tab is for the monster. |
| Label size | How big the timer names are. At auto they're a little smaller than the numbers and grow with Text size. Set a size and they stay at it, with Scale on top. A name bigger than the numbers makes its row taller. |
| Labels | Type your own name for each timer, like AA. Leave the box empty for the default. A label keeps only the characters on an English keyboard. |
| Text outline | A dark edge all the way around the text, in a color you pick. It keeps the text easy to read on snow, sand and other bright ground. It works with or without the text shadow, and gets thicker around big text. |
| Font | The font the timers use. Ashita's own pixel font, or any font cadence found. |
| Drain instead of fill | Bars start full and empty out. A bar that's ready fills back up in its ready color. |
| Share one spot | You can't be engaged and resting at once, so both timers can use the same place on screen. |
| One layout for all characters | Every character uses the same setup. Each character's own layout is kept, and changes made while it's on don't touch it. With two characters logged in at once, the last change saved wins. When you turn it off, this character keeps the shared layout and the others go back to their own. Job links stay with each character either way. |
| Peek with Shift | On by default. While the settings window is open, hold Shift and it goes see-through. Clicks pass through it too, so you can see and drag a timer that's under it. A click on an empty spot under it goes to the game. Shift and drag doesn't move the window while it's see-through. It stays solid while you type in one of its boxes or in the game's chat line, drag a slider, or have a dropdown or color picker open, so capital letters still work. |

The Font list has Ashita's own pixel font and the fonts cadence finds in Windows. Those are Segoe UI Semibold (the default), Tahoma Bold, Segoe UI Bold, Segoe UI, Verdana Bold, Arial Bold, Calibri Bold, Trebuchet MS Bold, Bahnschrift, Consolas Bold and Georgia Bold. Any .ttf or .otf you put in `config\addons\cadence\fonts\` shows up there too. Fonts are loaded when cadence loads, the same way XIUI does it. A new file shows up after `/addon reload cadence`. On Linux and Steam Deck the list is usually just Tahoma Bold and Ashita's font.

### Window tab

| Option | What it does |
|---|---|
| Font | The settings window's own font. Ashita's font is the default. The others are Segoe UI, Arial, Tahoma, Verdana, Calibri and Consolas, from the Windows fonts folder. A wide one like Consolas stacks the sections into one column at 920x680, so the window scrolls. If one is missing or won't load, the window stays in Ashita's font and a note under Font size says so. Presets never change it. The timers have their own Font on the Look tab. |
| Font size | How big the settings window's text is, from 12 to 24 px, 18 by default. The window's layout grows with a bigger font, so its sections may stack into one column. The slider stays the same width while you drag it. Presets never change it. |
| Corner roundness | How round the corners of the settings window and its boxes are, from 0, which is square, to 12 px. With Window matches the look on, a preset sets it. |
| Spacing | The space between the settings window's rows, from 2 to 14 px. With Window matches the look on, a preset sets it. |
| Tag brackets, Tag word and Replies | Under CHAT, the colors of the lines cadence prints in chat. Tag brackets and Tag word color the [cadence] at the start of each line, and Replies the answer after it. Each list has the game's own chat colors, the ones checkmate offers. By default they're Dark orchid, Cyan and Cream, the same ones Ashita's chat library uses, so nothing changes until you pick one. A preset sets all three, even with Window matches the look off, and Reset look puts them back. The swatch in front of each list only comes close to the shade the game shows. |
| Print a sample | Prints a line in chat in your chat colors, so you can see the real shades. |

### Window colors tab

Every color of the settings window, as rows of swatches under four headings. Each row is one part of the window, and each swatch is one of its colors, like Buttons normally, under the mouse and pressed. Point at a swatch to see which color it is, and click it to pick a new one. While Window matches the look is on, picking a preset sets all of them, and a color you change makes the Preset list say Custom. Reset look puts them back to the Phoenix colors.

| Row | Its swatches, in order |
|---|---|
| Text | Most of the window's text, then the faded text, like the subtitle and the (?) marks. |
| Headings | The section headings, then the line under each one. |
| Notes | The short notes some sections show, like when a timer is off. |
| Messages | What the Profiles tab says after something works, then when something doesn't. The note about a font that won't load takes the second color too. |
| Text boxes | The highlight behind text you select in a text box, then the text cursor. |
| Window | The window's background, then the line around it. |
| Title bar | The title bar while you're using the window, then while you're using another one. |
| Resize corner | The corner you drag to resize the window, normally, under the mouse and while you drag it. |
| Resize edges | The window's edges under the mouse, then while you drag one. |
| Scrollbar | The scrollbar's track, then the bar normally, under the mouse and while you drag it. |
| Boxes | Checkboxes, text boxes, sliders and dropdowns normally, under the mouse and while you click one. |
| Check marks | The tick in a checkbox. It also outlines a swatch while you drag a color onto it. |
| Slider handles | The handle on a slider, normally and while you drag it. |
| Buttons | The buttons normally, under the mouse and while you press one. A pressed OFF chip takes the pressed color too. |
| ON chips | A timer's ON chip, then its words. Under the mouse, an ON chip lights up a little toward Resize edges, hovered, and an OFF chip shows the ON chip color faint. |
| Dropdowns | An open dropdown and the tips the (?) marks show, then the row you have, the row under the mouse and the row you click. |
| Tabs | The tabs normally and under the mouse, then the tab you're on and the line over it. |
| Unfocused tabs | The tabs normally, the tab you're on and the line over it, while you're using another window. |

### Profiles tab

A profile is a named copy of every cadence setting, the timers' spots included. It leaves out where the settings window sits and its size, since those belong to your screen. It leaves out your job links too. Every character shares your profiles. With One layout for all characters on, a profile you load goes into the shared layout. Undo can't take a load back, so save your settings as a profile first if you want to keep them.

The profiles live in `config\addons\cadence\profiles.json`. cadence reads it again each time the settings window opens and before each change, so two game windows don't undo each other's work. If the file can't be read, cadence never writes over it, and the Profiles tab and the profile commands say where it is so you can fix or remove it. A profile with a setting missing loads with that setting at its default, and it gets the same settings check as your own settings.

| Option | What it does |
|---|---|
| The list | Your profiles in alphabetical order. Pick one to use the buttons on it. Picking one puts its name in the Name box. |
| Name | Type a name here for Save as new or Rename. A name can be up to 32 letters, numbers and symbols from an English keyboard. Capital letters don't matter, so "solo blm" and "Solo BLM" are the same profile. A profile can't be called None or (none), since job links use those to mean no link. |
| Save as new | Saves your settings as a new profile with the name in the box, and picks it. A name another profile has is refused. |
| Overwrite | Saves your settings over the profile you picked. |
| Load | Loads the profile you picked. |
| Rename | Gives the profile you picked the name in the box. A change of capital letters alone is fine. |
| Delete | Deletes the profile you picked. It can't be brought back. |
| JOB LINKS | A list for each main job, WAR to PUP, two to a line beside the profiles. Pick a profile and it loads each time you change to that job and zone. (none) loads nothing. A link to a profile that's gone, like one another character deleted, shows (gone) in front of its name. |

What a button did shows under the buttons, in the done or the problem message color from the Window colors tab.

Jobs change in your Mog House, so cadence reads your main job each time you zone. When it's a new job with a link, its profile loads, the same as Load, and cadence says so in chat. If that profile is gone, cadence says that instead. Loading cadence or logging in only notes your job. Each character has its own job links, kept in its own settings file, even while One layout for all characters is on. Rename moves this character's links to the new name, and Delete clears them. Other characters' links to a profile you rename or delete show (gone). `/cadence reset all` clears your links.

## How the auto attack timer works

Your first attack comes 2.8 to 3.2 seconds after you engage. The bar counts to the soonest, 2.8 seconds. After that, every attack adds your weapon delay to a timer that runs down in 0.4 second server ticks. Because of those ticks a single attack can come up to 0.4 seconds early or late, but they average out to your exact delay.

cadence works out your delay from your weapons, job traits (Dual Wield and Martial Arts) and the haste buffs you can see, the same way the server does. Elegy and Slow on you make your attacks slower, and cadence counts both. Gear haste and the exact strength of March, Slow or Elegy can't be seen from the client. So after a few attacks, cadence switches to the delay it measured from your real attacks. The small number next to the label shows the delay in use, with "est." while it's still the estimate.

What cadence measured stays through zoning. It's kept for each mix of weapons, jobs, levels and haste buffs. When Haste wears off and lands again, the bar goes straight back to the delay it learned with Haste on. March, Slow and Elegy can be stronger or weaker each time, so each new one is measured again. If the same one stays on between fights, the next fight starts on what was learned with it. Armor isn't part of the mix, so after an armor change the old delay stays until new attacks replace it. Logging in on another character starts over.

Job abilities and weapon skills hold the timer for 2 seconds. Spells, items and ranged attacks hold it while they run. Then it waits 2 seconds more after a spell, 0.8 seconds after a ranged attack and 0.4 seconds after an item.

Sleep, Lullaby, stun, petrification, terror and a penalty stop the timer. The bar stops where it is and carries on from the same spot once they wear off, the way the server's timer does. cadence leaves any gap they interrupted out of what it learns. While a spell, item or ranged attack runs, or one of those effects is on you, the bar dims and says why in place of the seconds, like "casting" or "asleep".

If cadence loads while you're already fighting, it can't know when your next attack is due. It shows "--" until that attack lands.

While you're engaged, the bar says "too far" or "not facing" and dims as soon as you step out of reach or turn away from the monster you're fighting. The server makes the same check before each attack. cadence checks facing first, then range. You face a monster while it's less than 45 degrees to either side of the way you face. Your reach is 2 yalms plus your size and the monster's, height included.

The monster you're fighting is the one your attacks go to, even while you have another one targeted. The server tells your game when that changes, like after /attack on another monster. /assist mid-fight looks the same to cadence, so after one it checks the monster you assisted on until your next attack lands.

Your game and the server see where everyone stands a moment apart. So "too far" or "not facing" only goes away once you're a little way back in, or as soon as an attack lands. If the bar fills and you still don't attack, the server's own message says why and wins over what cadence worked out. The server says it again each time an attack comes due, until you can attack.

## How the resting timer works

Resting ticks every 10 seconds from the moment you sit, but the first tick restores nothing. The server only runs these ticks on its 3 second effect check, so each one lands up to 3.2 seconds after its 10 second mark. The gaps between ticks end up going 9, 9, 12, 9, 9, 12.

cadence counts down about 21 seconds to your first tick. After that it watches your HP, MP and TP for each real tick and predicts the next one from that pattern. Once it has seen a few ticks, it usually lands within about 0.3 seconds of the real one. A flat 10 second countdown is often 1 to 2 seconds off.

When you're at full HP and MP under Signet, ticks don't change anything, so there's nothing to watch. cadence keeps following the pattern and shows "full".

Disease, plague and the curse that stops healing make each tick heal nothing, but the ticks still come on time. cadence keeps following them, so the timer is still in step when the effect wears off.

With Sound on, your sound plays once each time resting fills your HP and MP, the moment the timer turns "full". It plays even when the timer isn't on screen, like with Hide once full, `/cadence hide`, the map or a cutscene. It needs the resting timer turned on. Sitting down already full plays nothing. After it plays, it waits until you stand up and start resting again, or until your HP or MP drops and fills again while you're resting. The file only opens while Sound is on, or when you press Play, and then it stays open so each play starts right away. It closes when you pick another one, turn Sound off or unload cadence. If you never turn Sound on or press Play, cadence never opens a sound file.

## How the enemy attack timer works

Monsters time their attacks with the same server code as players. The first attack comes 2.8 seconds after a monster engages. After that, every attack adds the monster's delay to a timer that runs down in 0.4 second ticks.

Your game can't see a monster's delay. cadence starts at 4.0 seconds, which is what most monsters use, and learns the real one from the gaps between its attacks. The small text shows it, with "est." until three clean gaps have been seen. Monsters whose delay isn't a whole number of ticks, like quadav and trolls, attack on gaps that go back and forth a little, such as 4.4 and 4.8 seconds. cadence shows their average.

Once cadence learns the speed of the monster the timer follows, it remembers it by that monster's name until you reload cadence or log in on another character. The next one with that name in the same zone starts from that speed instead of 4.0 seconds. It still says "est." until its own attacks show it.

TP moves and spells pause the timer while they run. It says "TP move" or "casting" in place of the seconds, and picks up about 2 seconds after they finish. cadence can't see a monster's TP, so it can't warn you that a TP move is about to replace an attack. It also can't see sleep, stun or a monster chasing you. When the bar runs out it says "ready". Once a whole delay goes by with no attack, it shows "--" until the next one.

cadence keeps a clock for every monster attacking within about 30 yalms, so switching targets shows the new one already in step.

Slow, Elegy and Haste change how fast a monster attacks. Slow and Elegy are separate effects, so they add up. Haste cancels a Slow but not an Elegy. cadence sees them land on a monster from anyone within about 30 yalms. It also sees your own Slow or Elegy wear off.

The server sets a monster's next attack when it attacks. An effect that lands mid-attack changes the attack after it, and the timer does the same. It starts from a guess at how strong the effect is, then learns the real speed from the monster's attacks. A monster's gaps with no effects and its gaps with effects are kept apart. When a Slow wears off, the timer goes straight back to the speed it had learned.

Hojo, Carnage Elegy, Haste and Leviathan's Slowga are always the same strength. Once the monster's own speed is learned, the slowed one is known right away. Slow, Slow II and Battlefield Elegy depend on the caster, so they say "est." until a few attacks show them. A monster's Hundred Fists makes it attack at a quarter of its delay while it lasts.

Only whoever cast an effect is told it wore off. Someone else's Slow shows "slow?" once it might have been half resisted, and comes off once it can't still be on. A few blue magic spells and Titan's Rock Throw slow a monster without saying so. The timer only catches up with those from the monster's attacks.

## How the TP line works

The line under the auto attack bar shows your TP, and about how many rounds it takes to reach 1000. Your TP turns its own color once you're at 1000. It's only a display, and nothing in cadence acts on it.

Phoenix gives TP the way it worked before Seekers of Adoulin. Every hit that lands gives the same amount, set by your weapon's delay and your Store TP. A Samurai's Zanshin hit is the one exception, since Ikishoten merits add to it. Misses, parries, hits on shadows and hits for 0 damage give none. Haste doesn't change it. Two weapons count as their average delay cut by Dual Wield. Fists count as half their delay after Martial Arts. Bare hands only fight with both fists on a job with hand-to-hand skill and with nothing in the sub slot. Otherwise it's one attack a round, as a 480 delay weapon.

cadence starts from the TP your weapon and Samurai's Store TP trait give. Store TP gear can't be seen from the client, so it then checks that against your own TP. Right after one of your rounds, your TP goes up by the TP per hit for each hit that landed. Two rounds in a row that agree lock the number in, and so does a first one that matches the starting number. New weapons, a new job or a new level start it over.

A round doesn't count when something else moves your TP at the same time. That's a monster hitting you, one of your own abilities, weapon skills, spells, items or ranged attacks, a counter, Regain, Meikyo Shisui, or getting to 3000. A monster's spikes give you no TP, so they don't get in the way. On a Samurai at 75 or higher, a round of one attack that isn't a plain hit doesn't count either, since Zanshin can follow it. When TP goes up with nothing behind it, like during Meditate, rounds stop counting for 6 seconds.

Rounds to 1000 takes the hits you still need and divides by how many of your hits have been landing lately, so it goes up when you're missing a lot. TP your own hits don't explain counts too. That's a monster hitting you or countering you, its TP moves and spells, and Regain. From one of your rounds to the next, cadence adds up how much more your TP went up than your hits gave, and each round moves its average a third of the way toward that. So the count comes down over a few rounds once a monster starts hitting you, and goes back up over a few once it turns to someone else or your shadows start taking its hits. Each fight starts it over. Your TP itself is read every frame, so the count also drops the moment TP lands.

A stretch between two of your rounds doesn't count when one of your own abilities, weapon skills, spells, items or ranged attacks is in it, or when your TP went down or reached 3000. It also doesn't count when the second round came more than one and a half times your delay plus 0.4 seconds after the first, like after casting or walking back into reach. Nothing that starts in the 24 seconds after you use Meditate counts, since its TP comes with no buff to show it. Under Meikyo Shisui your hits give no TP, so being hit still counts in full. Until your TP per hit is locked in, a change that came with your own hits is left out.

## What cadence reads

cadence never sends anything to the server and never hides anything the server sends. It never writes to game memory and never sends commands to the game.

Besides Ashita's normal per-character settings file, cadence writes two files of its own. `config\addons\cadence\shared_layout.json` is written while "One layout for all characters" is on and deleted when you turn it off. While it's on, your changes go only to that file, except your job links, which stay in your own. `config\addons\cadence\profiles.json` is written when you save, overwrite, rename or delete a profile. cadence also makes the folder `config\addons\cadence\sounds\` when it loads and each time it looks for sounds, if it isn't there.

| Source | What it's used for |
|---|---|
| Your character's status in memory | Knowing when you're engaged or resting. |
| The game's "event running" flag in memory (the same one XIUI reads) | Hiding during cutscenes and NPC conversations. If a game update stops cadence finding it, your event status is used instead. |
| Whether the game's interface is hidden, and the name of the window that has focus, in memory (found the same way XIUI finds them) | Hiding while you've hidden the interface or while a map is open. If a game update stops cadence finding them, those options are greyed out. |
| Packet 0x028 (actions) | Your melee rounds, abilities, weapon skills, spells, items and ranged attacks, which of your hits landed, and whether an ability of yours was Meditate. With the enemy attack timer on, monsters' attack rounds, TP moves and spells, and Slow, Elegy, Haste and Hundred Fists landing on monsters from anyone, or Dispel and the like taking them off. With the TP line on, whether a monster's action hit you. |
| Your target, and for what's near you whether it's a monster, its server id, its status and its name, in memory | Picking which monster the enemy attack timer follows, and spotting when it engages or dies. The followed monster's name shows on the timer, and its speed is remembered by that name and its zone. The zone is part of its server id. When you engage, "too far" and "not facing" start out checking your target. |
| Where you and the monster you're fighting stand, which way you face and how big each of you is, in memory | "too far" and "not facing" on the auto attack timer before your attack is due. |
| Packet 0x029 (battle messages) | Messages saying an attack can't happen, like "out of range". With the enemy attack timer on, your own Slow or Elegy wearing off a monster, and a monster being defeated. |
| Packet 0x058 (assist) | Which monster your attacks moved to, so "too far" and "not facing" check that one. The server sends it when you engage, when you switch monsters mid-fight and when you /assist. |
| Packet 0x0DF (HP, MP and TP) | Spotting each resting tick, how much TP each of your rounds gave, and how much more came in from anything else between your rounds. One comes for each party member. Only yours is read past whose it is. |
| Your server id, entity index and TP from the party list in memory | Your server id is read once when cadence loads, to pick out your own packets. After that 0x00A gives it. Your entity index finds where you stand. Your TP is the TP line. |
| Packet 0x00A (zoning) | Your server id, resetting the timers when you change zones, and reading your main job again for job links. The delay, TP per hit and monster speeds cadence learned stay. |
| Your main job in memory, read once after each zone | Loading the profile linked to a new main job. |
| Your equipment, job, level, max HP and MP and buffs in memory | Working out your weapon delay and TP per hit, seeing March, Slow or Elegy wear off, skipping rounds under Regain or Meikyo Shisui, spotting when you're full while resting, and seeing disease, plague or the curse that keeps resting ticks from healing you. |
| Weapon delay and skill from the game's item data | The starting delay and TP per hit estimates. |
| Whether Shift is held (checked each frame a timer has something to show or the settings window is open) | Letting you drag the timers, and Peek with Shift. |
| Whether the game's chat line is open (checked whenever Shift is held) | Making Shift do nothing to the timers and the settings window while you type in chat. |
| The commands you type | Picking out /cadence and /cad. cadence answers those two itself, so the game never gets them. Every other command goes on as usual. |
| `config\addons\cadence\shared_layout.json`, read on load and each time you log in | Whether One layout for all characters is on, and the layout it shares. |
| `config\addons\cadence\profiles.json`, read when the settings window opens, before each profile command or button, for `/cadence joblink <job> <profile>` and `/cadence help profiles`, and after a zone when your main job changed and has a link | Your saved profiles. It's written only when you save, overwrite, rename or delete one. |
| The font files in the Windows fonts folder and in `config\addons\cadence\fonts\`, read once on load | The Font list, and the settings window's own font. |
| The file names in cadence's own `sounds\` folder and in `config\addons\cadence\sounds\`, read when the settings window opens, when you press Refresh and for `/cadence resting soundfile` | The Sound list. Only .mp3 and .wav files show up. |
| The sound file you picked, opened through Windows (MCI in winmm.dll) while Sound is on or when you press Play | Playing your sound once resting fills your HP and MP, and when you press Play. cadence never changes the file. |

## Files

The `cadence` folder you install holds these.

- `cadence.lua` connects everything to Ashita's events.
- `core/` holds the timing and math. That's `attack.lua`, `reach.lua`, `resting.lua`, `enemy.lua`, `monster_effects.lua`, `tp.lua` and `delay.lua`, plus `shared_layout.lua` for one layout across characters. `packets.lua` and `player.lua` read packets and memory.
- `ui/` holds the drawing. That's `hud.lua` for the timers, `settings_window.lua` for the settings window, `window_font.lua` for the settings window's fonts, `chat_colors.lua` for the chat colors and the lines cadence prints, `sound.lua` for the resting sound, `profiles.lua` for saved profiles and job links, `theme.lua` for the Phoenix colors, the settings window's palette for each preset and the window colors a palette spreads over, grouped the way the Window colors tab shows them, `presets.lua` for the preset looks and `defaults.lua` for the default settings, the slider ranges and the settings check.
- `sounds/` holds the two sounds that come with cadence, `FF VII Save.mp3` and `FF IX Moogle.mp3`.
- `LICENSE` is the GNU General Public License v3.0.

## License

cadence is released under the GNU General Public License v3.0. The full text is in [LICENSE](LICENSE).

The two sounds in `cadence/sounds/` are from Final Fantasy VII and Final Fantasy IX. They belong to Square Enix and aren't covered by the GPL.
