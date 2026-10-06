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

The fit gate checks that every tab of the settings window fits at 920x680 with no scrollbar, in
every preset, with the timers showing, hidden, and hidden with two of them off. Then it checks that
nothing on any tab runs into anything else, in every window font at 18 px and in Ashita's at 12, 20,
21 and 24. Run it after any change to the window, its spacing, a preset or a window font. See
preview/README.txt.

  .venv\Scripts\python preview\fit_gate.py

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
                          and Reset look, the settings check, the CHAT section of the Window tab with its
                          lists fitting the longest name and opening at yours and Print a sample, the
                          chatcolor command with what it says back, and /cadence help chatcolors
  test_colorblind.lua     every preset's color changes, checked the way colorblind players see them
  test_commands.lua       a command for every box and dropdown in the settings window, what each one
                          says back, a wrong word's own line, undo, the three resets and /cadence help
  test_disabled_pause.lua  sleep, stun, petrification, terror and the others stopping the auto attack bar
  test_docs.lua           the docs ready for release. README.md and CHANGELOG.md with no words about
                          tests or how cadence is made, Installing and addon.link pointing at the repo
                          on GitHub, the Phoenix note saying staff approved cadence, nothing about
                          pre-releases or waiting on staff, the sounds folder line, a CHANGELOG.md that
                          covers what cadence does, no test words in the addon's comments, tips, help or
                          chat lines, every test file named here, and no staff steps left in
                          ..\tools\README.txt
  test_efficiency.lua     Ashita's party, player and inventory objects fetched once, a party member's
                          0x0DF read only as far as whose it is, and no garbage from the settings window,
                          even with a Custom look, a chat color list open, profiles in the Profiles tab's
                          list with a message under its buttons, a job linked to a profile that's gone,
                          at 24 px with a note about a font that didn't load, or with a resting sound
                          picked, its list open or a note about a sound that won't play
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
                          on the Look tab, a color dropped on a swatch saving, and what chat says
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
                          drawn in yours at your size, Ashita's font and a note on the Window tab when
                          one didn't load, the layout growing with a bigger or wider font but not
                          shrinking, the width measured only when the font or size changes, the
                          smallest size and two columns at each size, the tab padding, the window
                          moving to another character's spot, presets leaving the font, Reset look and
                          Undo, and the settings check
  test_window_tabs.lua    the Window and Window colors tabs. The font list, Font size keeping its width,
                          the corners and spacing reaching the window, every window color as one swatch
                          in its row and lined up, each swatch naming its color, each row's tip, the
                          windowfont, windowfontsize, windowcorners, windowspacing and windowcolor
                          commands with what each says back, /cadence help window and windowcolors, and
                          the Look tab's Corner roundness tip saying it's for the timers.
                          The chat colors on the Window tab are in test_chat_colors.lua
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
