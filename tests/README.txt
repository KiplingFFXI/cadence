cadence tests
=============

These run cadence's real Lua outside the game. A mock of Ashita (mock_ashita.lua) stands in for the
game. Each test feeds it packets, frames and commands, then checks what cadence drew, saved or
printed. Nothing here is loaded by the addon or copied into the game.


Setup (once)
------------

You need Python 3.12. Run these from this folder.

  python -m venv .venv
  .venv\Scripts\python -m pip install -r requirements.txt

The tests read one file from Ashita's libs, json.lua, from C:/Games/PhoenixXI/addons/libs. Settings
and imgui are mocked in mock_ashita.lua. Set ASHITA_LIBS to use a different Ashita install.


Running
-------

  Double-click run_tests.bat. It sets up .venv the first time, runs every test and keeps the window
  open so you can read the result. You can also run them from a terminal.

  .venv\Scripts\python run.py                   every test_*.lua
  .venv\Scripts\python run.py test_window.lua   just the ones named

Each file prints its checks. A file fails when it errors or reports "N FAILED". The last line
says how many files passed.

The settings files the addon writes during a run go in a new folder in %TEMP%, which is deleted
when the run ends. Two runs at once each get their own.

The fit gate checks that every tab of the settings window fits at 920x680 with no outer scrollbar. Pages scroll
below fixed navigation. Each tab runs in every preset, with the timers showing, hidden, and hidden with two of them off. Then it checks that
nothing on any tab runs into anything else, in every window font at 18 px and in Ashita's at 12, 20,
21 and 24. Run it after any change to the window, its spacing, a preset or a window font. See
preview/README.txt.

  .venv\Scripts\python preview\fit_gate.py

The frame and HUD efficiency checks keep their allocation limits alongside the correctness checks. They
measure the mock's controlled paths, not game-client frame time. Source-parity and tooling checks are listed
in ..\tools\README.txt. A passing offline suite does not replace in-game load, zone, gear and recovery checks.

The release tools in ..\tools have a test of their own, which run.py doesn't run. It needs Git Bash
for the draft release job's steps and skips them when Git Bash isn't there. See ..\tools\README.txt.

  .venv\Scripts\python test_release.py


What's here
-----------

  run.py                  the test runner
  mock_ashita.lua         the stand-in for Ashita and the game

  test_api_bar_caps.lua   prints the bar draw calls and the corner rounding ImGui gives them (a table,
                          not pass or fail)
  test_api_shared_spot.lua  the shared spot, with ImGui's window placement working like the real one
  test_bar_options.lua    numbers only, draining bars, the ready mark, your own labels, Label size,
                          Detail size, the text outline, the outline Shift draws around a timer, and
                          resizing a timer with Shift + drag
  test_cant_heal.lua      the resting bar under disease, plague and the curse that stops healing, with
                          its word, its dim, the lines it hides, the box, its command and tip, and
                          staying in step with the ticks through the effect and after it wears off
  test_chat_colors.lua    cadence's chat colors. The palette, every line printed in your colors and the
                          very same line as Ashita's at the defaults, the colors each preset sets, Undo
                          and Reset look, the settings check, the CHAT section of the Window section with its
                          lists fitting the longest name and opening at yours and Print a sample, the
                          chatcolor command with what it says back, and /cadence help chatcolors
  test_colorblind.lua     every preset's color changes, checked the way colorblind players see them
  test_commands.lua       a command for every box and dropdown in the settings window, what each one
                          says back, a wrong word's own line, Undo, resets and /cadence help
  test_disabled_pause.lua  sleep, stun, petrification, terror and the others stopping the auto attack bar
  test_docs.lua           short README.md links the full docs\GUIDE.md and both directions resolve;
                          every local link and heading anchor works, the guide keeps command families,
                          all six tabs and timing sections, and safe install/update instructions.
                          README, guide and CHANGELOG.md have no words about tests or how cadence is
                          made, no personal paths, the public author and sound licensing stay intact,
                          Phoenix approval and sound-folder behavior stay documented, and the
                          published changelog is unchanged. Runtime comments, tips, help and chat
                          stay free of test prose, every test file is named here, and
                          ..\tools\README.txt has no staff steps.
  test_efficiency.lua     Ashita's party, player and inventory objects fetched once, a party member's
                          0x0DF read only as far as whose it is, and no garbage from the settings window,
                          even with a Custom look, a chat color list open, profiles in the Profiles tab's
                          list with a message under its buttons, a job linked to a profile that's gone,
                          at 24 px with a note about a font that didn't load, or with a resting sound
                          picked, its list open or a note about a sound that won't play
  test_frame_inputs.lua   TP-time input polling, immediate attack-packet refresh and zone invalidation
  test_hud_efficiency.lua steady-frame allocations for separate timers and the attached enemy strip
  test_player_inputs.lua each equipped weapon slot read once, including shields and missing resources
  test_tp_lifecycle.lua  character changes drop pending samples and zone changes clear fight evidence
  test_enemy.lua          the enemy attack timer's clocks on their own, then the whole addon with
                          monsters attacking, following, the attached strip, death and zoning
  test_enemy_effects.lua  Slow, Elegy, Haste and Hundred Fists on a monster, and the tag they show
  test_events.lua         hiding during events
  test_events_fallback.lua  the patterns not found, with the event status taking over and the game UI
                          and map options greyed out
  test_hide_and_resting.lua  /cadence hide and show, HP and MP full times, and hiding once full
  test_holds_and_fonts.lua  "TP move" and "casting" on the enemy timer, and the Font list, which fits
                          its longest name
  test_info.lua           /cadence info, the delay out of a fight matching what an engage starts on,
                          and what it says as the delay, TP per hit, TP from being hit and resting
                          pattern get learned
  test_integration.lua    the whole addon through load, packets, frames and commands, and logging in
                          on another character
  test_job_links.lua      job links. The setting and its check, profiles leaving them out, Rename and
                          Delete taking them along, your job read once after zoning and loading the
                          linked profile, even with nothing on screen, a profile that's gone or a file
                          that can't be read, each character's own links, the JOB LINKS section of the
                          Profiles tab with its lists, /cadence joblink, /cadence help profiles, reset
                          all, and links staying in each character's own file with One layout for all
                          characters on. An open list starts at the profile linked. A file that can't be
                          read shows each link's plain name. profiles.json is read at each time the
                          README names, and only then
  test_keep_last.lua      the enemy timer staying on its monster while you target a party member, an
                          NPC or nothing, and letting go once that monster dies, stops fighting or
                          goes quiet
  test_learned_delay.lua  the auto attack delay kept for each key through buff changes and zoning,
                          the 16 keys kept, starting over on another character, and a March that
                          wears off between fights
  test_timing_readouts.lua  TP goals, hits, resting counts, uncertainty and report controls
  test_goal_hud.lua      stable goal and TP-time rows, preview cues and passive-full wording
  test_layout_guides.lua  guide snapping, free drag and one undo snapshot per gesture
  test_workflow_controls.lua  real commands, preview isolation, partial goals and undo
  test_settings_details.lua  preview controls, bounded details and goal sanitation
  test_speed_details.lua   shared speed arithmetic, signed bonuses, caps and Hundred Fists weapons
  test_resting_actions.lua  direct-change exclusions, passive timing, caps and packet ordering
  test_recovery_actions.lua  actual addon cure/MP recovery hooks and reordered action packets
  test_layout_lifecycle.lua  interrupted drags across character changes and Reset all
  test_goals_relearn.lua  recovery targets, guarded TP ETA and selective relearning
  test_diagnostics.lua   bounded timing capture, sparse game-state reports and exclusion of unrelated chat
  test_tp_context.lua    successful-hit goals and separate target/set versus TP-per-hit learning
  test_speed_modifiers.lua  signed haste, delay, passive recovery and generated coverage
  test_modifiers.lua     Phoenix modifier rules, conditional gear, negative Store TP, food and augments
  test_stat_state.lua    passive packet and memory observations, uncertainty and equipment transitions
  test_stat_integration.lua  normal observations through the whole addon into TP and resting predictions
  test_tp_modifiers.lua  TP rounding boundaries, delay modifiers and learned-gain invalidation
  test_resting_model.lua  modeled recovery, observed gains, capped ticks and phase preservation
  test_next_gains.lua    optional next-tick display, estimates and commands
  test_mock.lua           the mock itself. Its font size and frame height, chat lines with their color
                          codes taken out (MOCK.printed) or kept (MOCK.printed_raw), and a command split
                          into words the way Ashita splits it, with quotes keeping words together
  test_monster_speeds.lua  the enemy timer remembering each monster's speed by zone and name, the next
                          one with that name starting from it with "est.", its own first gap taking
                          over, the 64 name cap, a Slow on it when it dies, the timer off, and
                          starting over on another character
  test_on_screen.lua      timers in a small game window drawn just inside it, their saved spots left
                          alone unless you drag them, and Reset positions on a short screen
  test_on_you.lua         the On you mark on the enemy timer's name and stripe, greyed out while
                          following whoever hits you
  test_one_layout.lua     one layout for all characters across two characters, with Ashita writing
                          each one's file the way it does in game, so each keeps their own layout
  test_options.lua        time until full, presets, one layout for all characters and the timer
                          options through the whole addon
  test_peek.lua           holding Shift to see through the settings window, staying solid while you
                          type, drag a slider or have a dropdown open, the Peek with Shift box, and
                          the timers ignoring Shift while you type in chat
  test_presets.lua        every preset sets every color, what Colorblind safe and Ember pick, the
                          Preset list showing the look you have or Custom with the preset it came
                          from, picking that preset again, the list's width, and Undo
  test_mint_lavender.lua  the Mint and Lavender timer, window and chat palettes, all eight skins,
                          custom looks and keeping independent window colors
  test_profiles.lua       profiles. Saving, loading, renaming and deleting them, what profiles.json holds
                          and leaves out, a profile with settings missing or wrong, a broken file and one
                          that can't be written, and None and (none) refused as names. The Profiles tab
                          with its list, name box, greyed out buttons and the message each button
                          leaves, in the done or problem color and never with a period right after a
                          quoted name. The profile commands with what each says back, names in any case
                          and in quotes, One layout for all characters, reset all, and /cadence help
                          profiles
  test_reach.lua          "too far" and "not facing" from where you and your target stand, checked
                          against the server's own facing and range math, then through the addon,
                          switching monsters mid-fight too
  test_reason.lua         "too far" and "not facing" from the server's messages, in place of "ready"
  test_regress_ranged_para.lua  a paralyzed ranged attack and a paralyzed item, whose packets come in
                          opposite orders
  test_regress_sleep2.lua  Sleep II and Lullaby stopping the auto attack bar
  test_regress_ui_paths.lua  settings window paths the integration test doesn't reach
  test_release.py         the release tools. The zip with and without the sounds holding just the files
                          it should, each the same as the project's, bump_version.py changing
                          cadence.lua and CHANGELOG.md and nothing else, and the draft release job's
                          steps run with stand-ins for git and gh
  test_resting_sim.lua    a simulation of the server's resting ticks, printing how close the resting
                          timer's predictions land (a table, not pass or fail)
  test_resting_sound.lua  the resting sound, with a stand-in for winmm that keeps each MCI command and
                          plays nothing. The two sounds that come with cadence and their sizes, the
                          sound off with FF VII Save.mp3 picked by default, your sounds folder made on
                          load, both folders read only when the window opens, on Refresh and for soundfile,
                          cadence's sounds listed first and then yours, each part in order, yours left
                          out when it has the same name as one of cadence's, cadence's played from its
                          own folder found from addon.path, a sound of cadence's or its whole folder
                          gone, nothing sent to MCI until the sound is on or you press Play, the file
                          opened once and closed on a new pick, turning the sound off, unload, reset all
                          or another character, one play each time resting fills HP and MP and none with
                          the timer or sound off, while standing or when you sit down full, playing while
                          the timer is hidden, the volume as MCI takes it, a file that won't open or play
                          with its note and one chat line, no winmm, the commands, the Sound rows and how
                          wide the list grows, the settings check, profiles and presets
  test_resting_sound_load.lua  loading with the resting sound on. Its file opens on load, and one that
                          won't open says nothing in chat until you turn the sound on again
  test_resting_sound_reload.lua  loading cadence or zoning while you're resting. A vitals packet at
                          full before cadence knows your HP and MP doesn't play the sound, and a real
                          fill after does
  test_run_folder.lua     each run of the tests writing into its own temp folder
  test_setting_commands.lua  a command for every slider, color and label in the settings window. Each
                          slider and its command setting the same thing over the same range, each
                          number command through its range and past both ends, with decimal places and
                          auto, a whole number written like 300.0 taken as the README says, every timer
                          color by its word, each timer's own label with Shift-JIS and auto-translate
                          taken out, what each one says back, and /cadence help attack, resting, enemy,
                          look and colors
  test_settings_check.lua  the settings check on load, on login, after the shared layout and before
                          each save, the defaults and every preset coming through unchanged, and the
                          window's sliders reading the same ranges
  test_settings_defaults.lua  a settings file with a section or color missing never shares tables
                          with the defaults
  test_settings_help.lua  a (?) on every setting, what the tips say, no tip with a mark ImGui could
                          wrap onto the start of a line, and the window opening where you left it at
                          the size you left it
  test_settings_tidy.lua  the settings window's greyed out sliders, a timer that's off drawn faint,
                          Show them, Undo and Reset look on the PRESET heading, Drain instead of fill
                          on the Appearance tab, a color dropped on a swatch saving, and what chat says
  test_show_label.lua     the box in front of each label that hides just that timer's name, with its
                          seconds and small text left, and Show labels still hiding all three from its
                          spot at the right end of the LABELS heading
  test_slider_during_event.lua  an event that starts while you drag a slider, with the mouse coming
                          up during it or after it, and the save after
  test_tp.lua             which hits give TP, learning TP per hit, what keeps a round from
                          counting, rounds to 1000 with TP from being hit counted in, and the TP
                          line under the bar
  test_ui_hide.lua        hiding with the game UI and on the map, and how those addresses are found
  test_ui_hide_map_only.lua  only the map's pattern missing, so only that option is greyed out
  test_units.lua          packets, delay and the auto attack timer on their own
  test_why_stopped.lua    the auto attack bar dimmed with "casting", "asleep" and the others while it's
                          stopped, and "--" until the first attack when cadence loads mid-fight
  test_window.lua         the resizable two-column settings window, the AUTO ATTACK name and the
                          commands that turn each timer on or off
  test_window_font.lua    the settings window's font and font size. The fonts loaded once on the load
                          event, Segoe UI loaded once for the timers and the window both, the window
                          drawn in yours at your size, Ashita's font and a note on the Window section when
                          one didn't load, the layout growing with a bigger or wider font but not
                          shrinking, the width measured only when the font or size changes, the
                          smallest size and two columns at each size, the tab padding, the window
                          moving to another character's spot, presets leaving the font, Reset look and
                          Undo, and the settings check
  test_window_tabs.lua    the Window and Window colors sections in Appearance. The font list, Font size keeping its width,
                          the corners and spacing reaching the window, every window color as one swatch
                          in its row and lined up, each swatch naming its color, each row's tip, the
                          windowfont, windowfontsize, windowcorners, windowspacing and windowcolor
                          commands with what each says back, /cadence help window and windowcolors, and
                          the Appearance tab's Corner roundness tip saying it's for the timers.
                          The chat colors on the Window section are in test_chat_colors.lua
  test_window_look.lua    the settings window's look. Each preset's palette spread over every window
                          color in your settings, the window drawn from them, Phoenix's own window
                          colors, chips and row spacing, Undo and Reset look, Window matches the
                          look and its command, the settings check, and every palette's text easy to
                          read on its slider handles, dropdown rows and pressed buttons, with its done and
                          problem messages readable and apart

  render.py               draws the timers to PNGs in out/, from one of these shots_*.lua scripts
                            .venv\Scripts\python render.py shots_presets.lua   every preset
                            .venv\Scripts\python render.py shots_label.lua     the AUTO ATTACK label at three widths
                            .venv\Scripts\python render.py shots_enemy.lua     the enemy bar, on its own and attached
                            .venv\Scripts\python render.py shots_tp.lua        the TP line in each look, below and at 1000
                            .venv\Scripts\python render.py shots_bar_options.lua  numbers only, draining bars, the ready mark and the resting line
                            .venv\Scripts\python render.py shots_colorblind.lua   the Colorblind safe look
                          The timers go on a plain dark background. To draw them over a game
                          screenshot, set CADENCE_BACKDROP to its path first.
  colorblind_sheet.py     shows those shots the way colorblind players see them, in out/colorblind_sheet.png
  preview/                draws the real settings window with real Dear ImGui 1.92.3 (the version
                          Ashita uses), and holds the fit gate, fit_gate.py. See preview/README.txt.

Live modifier and timing checks
------------------------------

The offline checks and rendered previews do not verify the installed client. After
loading the addon yourself, enable /cadence record on and save /cadence report after
each case. /cadence info details explains the model and remaining unknown inputs.
Use items and conditions available to your character; source rows are not proof of
Phoenix acquisition. Do not use automatic commands or packet injection.

- Compare the starting delay and clean observed rounds with positive haste gear,
  negative haste gear, a percentage delay item and a conditional flat-delay item.
  Source examples: Walahra Turban, Hecatomb Harness, Sword Strap, Primate Staff.
  Flat delay and haste must leave TP per hit alone; DELAYP may change it.
- Swap speed gear between rounds, then swap an unrelated piece. Only the relevant
  swap should invalidate learned timing. Repeat with a conditional bonus turning
  on and off, an augment, a set and an activated item when available.
- Recast March, Slow or Elegy without losing its icon. The delay must relearn even
  if the buff count is unchanged. Stack two March icons and remove one.
- Change target and accuracy or extra-attack equipment. Recent hit-rate evidence
  must restart without losing valid TP per hit. Check goals 1000, 2000 and 3000,
  Successful hits and the goal color; compare hits against the separate rounds.
- Rest with hHP/hMP gear and food, then with Regen/Refresh gear such as Dalmatica.
  Compare next gains, the 9/9/12 phase, separate three-second recovery, ticks to full
  and both HP/MP full times. Include a capped stat, cure, gear swap and interruption.
  If an available effect drains HP/MP, check the penalty and whether /heal stops.
- Load while BLU is already set. Check source and spell IDs in the local report,
  then change spells and jobs and zone. An unavailable/invalid buffer must report
  unknown, never silently assume a trait. Confirm Assault context when available.
- Follow an attacker whose interval exceeds ten seconds, including Slow/Elegy and
  a long spell/TP move. The timer must retain it through the expected attack/hold.
- Save a report with recording off and on. Confirm no outgoing behavior, no raw
  packets or chat in the report, and only the latest 256 relevant recorded events.

Keep client version, source ref, actual items/conditions and observation timestamps
with each result. A successful source or mocked check is not a live gameplay result.

Live goal and layout checks
--------------------------

- In Preview, select each timer and each sample state. Pause, change the look and
  resume. Closing settings should remove samples without changing live countdowns,
  vitals, learned samples or the full-resting sound.
- Enable Alignment guides, unlock a timer and Shift-drag or resize it. Check screen
  edges, centers and another timer within six pixels. Undo should restore the entire
  previous gesture. Load a profile and Undo it, including custom goals and colors.
- Set an MP percentage goal, an absolute HP goal and a combined goal. Compare the
  displayed goal with your current maximum after a max-HP/MP gear swap. Reaching a
  partial goal must not play the full-resting sound or say both stats are full.
- Enable Time to TP goal and collect clean rounds. Confirm the estimate disappears
  while out of reach, unable to attack, overdue, holding, relearning or changing speed
  gear. Confirm the selected TP goal still reports successful hits and rounds apart.
- Use each relearn button in Details. It should clear only the chosen observations,
  leave the current countdown/holds intact and report uncertainty until new evidence.
- Open Details while fighting and resting. Check sample/rejection counts, known and
  unknown contributions and scheduled versus next-interval delay against the report.

- During live recovery checks, receive repeated cures both three and five seconds apart.
  They must not become Regen. Repeat with MP restoration and with a heal landing near
  a resting tick. Real three-second Regen/Refresh should still become observed.
- On BLU, change a spell that grants DEX without changing a trait. Recent hit/round
  evidence should restart while valid TP per hit remains. Details should show the
  set spell names, relevant trait tiers and confirmed/provisional status.
- Inspect Speed in Details with haste, slow gear and capped bonuses. Check raw and
  applied totals, the final delay limit and Hundred Fists with fists, a staff and a club.
- Interrupt a Shift drag by logging into another character. Undo must never restore
  the previous character's layout. Repeat with Reset all during an unfinished gesture.

Checkmate timing and usability ports
-----------------------------------

test_safe_saves.lua covers open/write/close/replace failures, unreadable existing files,
Undo delete collisions, character-owned job links, shared-layout rollback and commands.
test_stat_state.lua checks unchanged model reuse without skipping polls, plus immediate
vitals, weather, party, gear and own-cast context invalidation. Speed details includes
the Phoenix 0.93 haste cap before DELAYP and the separate final 20% weapon floor.
test_stat_cache_expiry.lua covers expiry with unavailable buffs and same-icon replacements.
test_packet_boundaries.lua rejects incomplete records before any earlier result is used.
test_enemy_controls.lua checks disappearance, reused IDs, controls and clean resumption.
test_effect_snapshots.lua checks supported cast inputs and uncertain duration evidence.
test_ui_discovery.lua and test_timer_hover.lua cover search, navigation, copy and tips.

Manual client checks still needed:
- Narrow the window, search for settings, expand/collapse groups and scroll. Navigation
  must stay reachable. Search Details and compare Copy shown with complete Copy all.
- Hover each live timer without Shift. Tips must not capture game clicks. Holding Shift,
  dragging or interacting with settings must suppress them. Try /cadence tips off/on.
- Delete a profile, choose a new job link, then Undo delete. The new link must remain.
  Undo must not overwrite a same-name profile saved by another game window.
- Follow an enemy with Slow, let it leave sight and return. Its old effects must be gone.
  Observe Sleep, Stun, Petrification and Terror landing/removing. The hold must never
  learn that blocked gap or guess a new attack time from estimated expiry. Bind alone
  must not stop its attack timer. Check a damaging attack wakes observed Sleep.
- Cast a supported effect in duration gear, swap gear, then inspect its Details entry.
  It must keep the inputs from landing, with missing caster inputs/resists uncertain.

Source/tool commands and their scope are documented in tools/README.txt. Passing these
checks does not confirm hosted CI, release publication, reload or live client behavior.

Cadence 1.2.0 settings workflow
-----------------------------

test_history_efficiency.lua checks Undo snapshot allocations, no-op changes and isolated saved values.
test_settings_history.lua covers the eight-entry settings history, in-place restoration,
owner changes and scoped resets that preserve timer positions, custom labels and choices
outside the selected section.
test_starter_layouts.lua checks Minimal, Melee / TP, Resting and Enemy tracking, preview
isolation, layout-owned readouts and preservation of positions, styling and goals.
test_profile_workflow.lua checks Using/Modified baselines, partial older profiles,
layout baselines and guarded Undo overwrite, including failed writes and newer saves.
test_search_navigation.lua checks match counts, Previous/Next wraparound, duplicate marks,
query changes and a selected match disappearing.
test_tab_visibility.lua checks saved tab choices, mandatory Appearance, hidden-tab jumps,
search revealing hidden matches and cached navigation after visibility changes.
test_settings_workflow_ui.lua checks the inline sample, layout preview/apply actions,
Undo and reset actions, compact readouts, Enabled only, contextual Details, independent
window color folds and profile status in the toolbar.
test_inline_preview.lua checks sample clipping, ready-state fill with draining bars,
readout choices and preservation of saved settings.
test_ui_pending_saves.lua checks unfinished edits when closing settings, unloading,
switching characters or changing shared-layout mode, plus failed-save retries across
character changes without carrying over character-owned tabs, links or Undo history.
test_resting_frame_forecast.lua checks one recovery forecast per frame, partial HP/MP estimates,
full recovery and the display toggles that need forecast values.
test_core_efficiency.lua checks recovery and TP query allocations, independent returned estimates
and repeated client-stat reads, including unavailable methods.
test_resting_hp_only.lua checks that duplicate vitals and Regen-only updates cannot
restart HP-only resting ticks, while real recovery and full/blocked schedules still work.
test_resting_independent_full.lua keeps a valid HP or MP full time when the other
stat is unknown, without claiming a combined full time before both can be estimated.
test_resting_max_vitals.lua checks HP and MP maximum changes after Weakness ends without
another vitals packet, preserving tick timing and restoring forecasts, goals and sound readiness.
test_resting_boundaries.lua checks capped Refresh, drains at zero MP and estimated timing before an observed tick.
test_resting_held.lua keeps recovery through duplicate vitals when a blocking effect wears off.
test_resting_hidden_buffs.lua keeps blocking effects current with the timer disabled or hidden at full.

test_native_packet_events.lua sends userdata events like Ashita's through packet readers
and the addon callbacks. It covers HP-only recovery and full times, attack observations,
and rejected incomplete updates. Table fixtures alone cannot catch native event guards.

test_vertical_resize.lua checks whole-timer height changes, unchanged widths and bar settings,
text-only resizing, attached strips, bounds, alignment and one Undo step per gesture.

test_height_settings.lua checks default and saved heights, height commands and sliders,
profiles, shared layouts and reset/Undo behavior. test_inline_preview.lua also checks that
sample text and spacing follow each timer's height while its width stays unchanged.
test_edit_transactions.lua checks separate Undo steps for a held edit followed by a command,
completion after a control disappears, keyboard-edit holds and repeated sharing commands.
test_profile_status_cache.lua checks edited-profile allocation, independent character status,
refreshes, failed writes, corrupt files and saved-profile recovery.
test_ui_cleanup.lua checks inactive-edit completion, blank searches and timer-preview styling.
test_ui_history_integration.lua checks commands and held edits through the addon,
scoped resets, layout previews, profile baselines and overwrite recovery, character-owned
tab choices, shared layouts, job-link table identity and saves.

Manual client checks still needed:
- Apply Mint and Lavender with Window matches the look both on and off. Check timer
  countdowns, TP goals, resting full states, enemy warnings and chat samples. Try all
  eight skins against the game scene you normally use.
- Make several settings edits, including a held slider and one Shift-drag gesture.
  Use Undo repeatedly and confirm each action is one step, up to the latest eight.
  Undo must not cross character changes or Reset all. Reset each section and confirm
  its stated scope, then Undo it.
- While sharing a layout, check a failed save followed by a character change. The
  shared edit should stay visible and save when retried; the new character should
  keep their own hidden tabs and job links, with no previous-character Undo history.
- Save a profile, change a readout and check Using changes to Modified. Load it,
  overwrite it and Undo overwrite. A newer same-name save from another game window
  must prevent recovery from replacing it; live settings remain unchanged.
- Preview each starter layout before applying it. Samples must not change live timers,
  learned observations or sounds. Applying a layout must preserve positions, colors,
  fonts, labels, goals, sound choices and enemy following/attachment.
- In Appearance, try each embedded sample state and hide the sample. Fold window
  color groups separately. Hide optional tabs, restore them all, then hide Details
  and reach it from a readout. Appearance must always remain available.
- Search for a setting with several matches. Step backward and forward, cross the
  first and last match, reveal a hidden matching tab, then clear the search. Confirm
  previous fold choices return. Try the same at narrow and wide window sizes.
- Turn on Enabled only for a readout group, then search for an unchecked readout.
  It must remain discoverable without changing its setting. On a narrow window,
  expand Options and open its Details link; Clear should restore all Details groups.

Use /cadence help ui for the layout, search, tabs, Undo and reset commands. These
checks describe expected behavior; they do not claim a live-client validation result.
