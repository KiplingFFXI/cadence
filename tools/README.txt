cadence release tools
=====================

These get a new version of cadence ready to release. build_release.py builds the zip players download,
bump_version.py sets a new version, and a job on GitHub drafts the release. None of it is part of the addon, so
don't copy it into the game.

You need Python 3.12 on PATH. Neither script needs anything from pip. Run them from the project folder.


Building the zip
----------------

  python tools\build_release.py

It writes dist\cadence-<version>.zip and prints its SHA-256. The version comes from addon.version in
cadence\cadence.lua. --out FOLDER writes the zip somewhere else.

The zip holds the cadence\ addon folder, with cadence.lua at cadence\cadence.lua, so it unzips straight into
Ashita's addons folder. The builder accepts only its explicit runtime list and the two bundled sounds. It
also puts LICENSE from the project folder in there as cadence\LICENSE. Extra, missing or linked files stop the
build, as do private paths, character-specific settings paths or credential markers in text. Nothing from
tests\ or tools\ goes in. Keep local reports and screenshots outside the addon folder. When you add runtime
files, update tools\build_release.py and the expected list in tests\test_release.py.

README.md, CHANGELOG.md and docs\GUIDE.md are checked for the same private paths and credential markers when
present. They stay on GitHub and are not packed into the addon zip. Linked documents stop the build too.

Matching text produces a matching zip and SHA-256 with LF, CRLF or mixed line endings, even when timestamps
differ. Text in the archive uses LF; source files and bundled sound bytes stay unchanged. The builder validates
a temporary archive before replacing a previous zip, so a failed build leaves the previous archive intact.


The sounds
----------

By default the zip carries the two sounds that come with cadence, cadence\sounds\FF VII Save.mp3 and
cadence\sounds\FF IX Moogle.mp3. They're from Final Fantasy VII and Final Fantasy IX. They belong to Square Enix,
so the GPL doesn't cover them.

  python tools\build_release.py --no-sounds

That builds the zip without the sounds folder. cadence still works without it. The Sound list then shows only
the player's own files from config\addons\cadence\sounds\, and turning the sound on with FF VII Save.mp3 still
picked says it won't play. README.md still says two sounds come with cadence, so change it before you release a
zip like that.

The job on GitHub always builds the zip with the sounds. To release one without them, build it on your PC with
--no-sounds and swap it for the zip on the draft before you publish it.


A new version
-------------

  python tools\bump_version.py "First line of the section." [BULLETS_FILE]

It adds one to the last number of addon.version in cadence\cadence.lua, so 1.0.0 becomes 1.0.1. Then it puts a
section for that version at the top of CHANGELOG.md, with your line under the heading. If you name a file, its
lines go under that as they are, so write them as bullets like "- The resting timer ...". Blank lines in the file
are left out. It prints the new version.

Those are the only two places the version is written down. The settings window and /cadence info read it from
cadence.lua. To go to 1.3.0 or 2.0.0 instead, change addon.version and add the CHANGELOG.md section yourself.

Move completed Unreleased notes under the new version heading. The version helper prepares both files before
replacing either and rolls back if the second replacement fails. If rollback is blocked too, its error names
the temporary copy of the original file so it can be recovered.

That section becomes the release notes, so include every change since the last published version. If a version
was prepared but never published, fold its notes into the version you will release. Keep published sections
unchanged. Read the final section before you push; the draft does not collect notes from older headings.


The draft release
-----------------

.github\workflows\draft-release.yml runs on GitHub when either of these gets there.

- A push to main that changes addon.version in cadence\cadence.lua.
- A tag like v1.0.1. It has to match addon.version in cadence.lua at the commit it's on. If it doesn't, the job
  stops with an error and drafts nothing.

It first runs the read-only Verify job, then builds the zip and makes a draft release called cadence <version>
for the tag v<version>, with
cadence-<version>.zip attached and that version's CHANGELOG.md section as its notes. Only you and anyone else with
write access to the repo can see a draft. The job stops with an error if CHANGELOG.md has no section for that
version.

If that version already has a release, draft or published, it does nothing. So pushing main and its tag together
drafts it once, and the tag GitHub makes when you publish a draft doesn't draft it again.

The job names the branch main, so the repo's branch has to be called main. It asks for its own write access in
its file, so there's no repo setting to change.


Publishing the release
----------------------

On the repo's Releases page, click the pencil on the draft, read over the notes and click Publish release. Leave
Set as the latest release ticked. If the tag isn't there yet, GitHub makes v<version> on the commit the zip was
built from.


Running the job by hand
-----------------------

On GitHub, open the repo's Actions tab, pick Draft release on the left, click Run workflow, leave the branch on
main and click the green Run workflow button. It drafts the version that's on main, unless that version already
has a release.


Checking the tools
------------------

  tests\.venv\Scripts\python tests\test_release.py

It builds the zip with and without the sounds and checks every file in each, bumps the version on a copy of the
project, and runs the job's steps in Git Bash with stand-ins for git and gh. It never changes the project or
reaches GitHub. See tests\README.txt for setting up tests\.venv.


Modifier data
-------------

  python tools\generate_modifiers.py --server ..\Phoenix
  python tools\generate_modifiers.py --server ..\Phoenix --check

The generator reads Phoenix git objects at the commit named by REF and writes
cadence\data\phoenix_modifiers.lua. It does not fetch, check out, or change the server.
The output includes source hashes and a TOAU level-75 profile. Later-era data stays
separate from eligible traits and item rules. Level eligibility alone is not proof
that an item is obtainable on Phoenix. Review source and configuration changes before
changing REF. --check verifies that the checked-in data matches that source.

The model uses known bonuses as a prior. Observed TP and uncapped resting gains replace
the prior; never add equipment or food a second time to a gain already observed. A
missing item, augment format, conditional state, food identity or effect power stays
unknown. Normal packets can fill those gaps. Never request packets or use client calls
that perform game actions to fill them.

The coverage table in phoenix_modifiers.lua inventories every tracked modifier: fixed
item rows, negative values, latents, augments, food, activated items and set rules. The
tracked domains include signed gear/magic/ability haste, flat DELAY in milliseconds,
DELAYP in percent, Dual Wield, Martial Arts, resting gains, Regen/Refresh and their
down modifiers. Accuracy and extra-attack changes invalidate recent hit-rate history.
Flat DELAY affects attack timing only; DELAYP also changes TP per hit. Regen/Refresh
are separate three-second passes, not additions to the resting-tick gain. An unknown
condition is reported by source and affected field rather than silently treated as zero.


Source parity and automated checks
----------------------------------

  tests\.venv\Scripts\python -m pip install -r tools\requirements.txt
  tests\.venv\Scripts\python tools\check_source.py --server ..\Phoenix
  tests\.venv\Scripts\python -m unittest discover -s tools\tests -p "test_*.py"
  tests\.venv\Scripts\python tools\generate_effects.py --server ..\Phoenix --check

check_source.py reads the reviewed Git revision without checking it out. It compares TP and resting gains with
Phoenix's own Lua, and attack delays with an independent reference tied to the reviewed C++ function. The delay
comparison allows up to three milliseconds for the C++ float and Lua double truncations. It covers signed slow,
Haste caps, Dual Wield, Martial Arts, Hundred Fists, and flat and percentage delay changes.

The selected Phoenix profile uses DELAY_REDUCTION_CAP = 0.93. The pinned default is 0.80. Neither proves what a
running server loaded. Relevant helpers and init-listed module rules are guarded in source_guards.json. Changed,
new or removed timing rules stop the check and list the paths that need review. The list includes loaded modules
whose own era gates may make them inactive. The generators check these guards before writing their output.
The guard also checks module load order and keeps code tokens separate, so a changed identifier or operator
cannot disappear when whitespace and comments are ignored.

To review a later revision without updating anything, add --ref <revision> to check_source.py. Do not refresh the
expected hashes just to make a failure disappear. Read the changed rules, update the calculations or recorded
limits, then update the guarded snapshot and the fixture cases together. REF, source_guards.json and Verify's
Phoenix revision must agree when the reviewed pin changes.

Verify runs tool tests, source checks, both generated-data checks, the offline addon suite and release checks
on Windows. Draft release depends on it. Tests use pinned Ashita libraries and pinned Phoenix source. There is
no scheduled refresh, automatic source update, commit or push job. UI fit checks remain a local preview gate;
passing CI does not establish in-game behavior.

The tool fixtures deliberately change source formulas, addon formulas, module lists and packaging inputs to
confirm that the checks fail. On Windows, native file-store tests also use the real replacement call and a
locked temporary destination. Other systems skip those two native checks. CADENCE_SOURCE_REPO selects a local
Phoenix Git repository for source fixtures; ASHITA_LIBS selects its json.lua for the native save tests.


Release readiness
-----------------

Run the complete addon suite, tool tests, source and generated-data checks, release workflow fixtures and
preview fit gate from tests\README.txt before making an archive. Keep the current version heading in the
changelog aligned with addon.version. Build with sounds and with --no-sounds into separate folders; both
variants use the same filename. Rebuilding unchanged files must produce the same SHA-256.

In game, confirm load/unload, character and zone changes, equipment and food changes, BLU spell updates,
interrupted resting, disabling effects, settings edits and profile failures. Offline checks and previews
cannot establish these live results. Keep the live result separate from the offline report. Nothing in the
local tools publishes a release or sends game commands.
