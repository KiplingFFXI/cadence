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
Ashita's addons folder. Only the addon's .lua files go in, plus the .mp3 and .wav files in cadence\sounds\. It
also puts LICENSE from the project folder in there as cadence\LICENSE, so every copy of the addon carries the
license. Nothing from tests\ or tools\ goes in. When you add a .lua file to the addon, add it to the list at the
top of tests\test_release.py too.


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
cadence.lua. To go to 1.1.0 or 2.0.0 instead, change addon.version and add the CHANGELOG.md section yourself.

That section becomes the release notes, so read it over and edit it before you push.


The draft release
-----------------

.github\workflows\draft-release.yml runs on GitHub when either of these gets there.

- A push to main that changes addon.version in cadence\cadence.lua.
- A tag like v1.0.1. It has to match addon.version in cadence.lua at the commit it's on. If it doesn't, the job
  stops with an error and drafts nothing.

It runs build_release.py and makes a draft release called cadence <version> for the tag v<version>, with
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
