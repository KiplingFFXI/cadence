-- The short README links the full guide. Both and CHANGELOG.md stay ready for players, with complete
-- instructions, working local links, no private paths and no text about how cadence is made.
-- No comment, tip, help line or chat line in the addon talks about tests. tests\README.txt names every test.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local ROOT = ADDON_DIR .. '/..';
local REPO = 'https://github.com/KiplingFFXI/cadence';
local FOLDER = MOCK_INSTALL_PATH .. '\\config\\addons\\cadence\\sounds\\';

local function read(path)
    local file = assert(io.open(path, 'rb'));
    local text = file:read('*a');
    file:close();
    return (text:gsub('\r\n', '\n'));
end

-- The files in `folder` that match `mask`. With `deep`, the ones in its folders too, by their full paths.
local function files_in(folder, mask, deep)
    local found = {};
    local list = io.popen(('dir /b %s "%s\\%s" 2>nul'):format(deep and '/s' or '', (folder:gsub('/', '\\')), mask));
    for line in list:lines() do
        found[#found + 1] = line;
    end
    list:close();
    return found;
end

-- The words in `text` from `words`, each a Lua pattern run on the text in lowercase.
local function found_words(text, words)
    local lower, found = text:lower(), {};
    for _, word in ipairs(words) do
        local at = lower:find(word);
        if (at ~= nil) then
            found[#found + 1] = ('%s in "...%s..."'):format(word, text:sub(math.max(1, at - 30), at + 30));
        end
    end
    return table.concat(found, ' | ');
end

-- Words about tests, mocks and development tools. Preview is also a player-facing tab.
local TESTING = {
    '%f[%a]tests?%f[%A]', '%f[%a]tested%f[%A]', '%f[%a]testing%f[%A]', '%f[%a]mock', 'preview tool', 'mutation',
    'mutant', 'harness', 'offline', 'fixture', 'fit gate', 'selftest', 'lupa', 'checked in game', 'in game yet',
};
-- Those and words about how cadence is made. Players never need them. A comment can say a function builds
-- a table, so only text players read is held to these.
local MAKING = { '%f[%a]workers?%f[%A]', '%f[%a]review', '%f[%a]build', '%f[%a]built%f[%A]', 'workflow' };
for _, word in ipairs(TESTING) do
    MAKING[#MAKING + 1] = word;
end
-- Paths and tools from outside the addon folder.
local OUTSIDE = { 'tests[/\\]', 'tools[/\\]', '%.github', 'build_release', 'bump_version', 'fit_gate', 'run%.py' };
local PRIVATE = { '[a-z]:/+users/+', '/home/+', '/users/+', '/%.claude/', '/%.codex/',
    'config/+addons/+cadence/+[^%s/]+_%d+/' };

local readme = read(ROOT .. '/README.md'):gsub('\r\n', '\n');
local guide = read(ROOT .. '/docs/GUIDE.md'):gsub('\r\n', '\n');
local changelog = read(ROOT .. '/CHANGELOG.md'):gsub('\r\n', '\n');
local public_docs = { ['README.md'] = readme, ['docs/GUIDE.md'] = guide, ['CHANGELOG.md'] = changelog };

-- The public documents ---------------------------------------------------------------------------------------
for name, text in pairs(public_docs) do
    local words = found_words(text, MAKING);
    check(name .. ' has no words about tests or how cadence is made', words == '', words);
    words = found_words(text, OUTSIDE);
    check(name .. ' names nothing from outside the addon folder', words == '', words);
    words = found_words(text:gsub('\\', '/'), PRIVATE);
    check(name .. ' has no personal or character-specific paths', words == '', words);
end

local files = guide:match('\n## Files\n(.-)\n## ') or '';
check('The guide\'s Files section only lists the addon\'s own files', files:find('`cadence.lua`', 1, true)
    and files:find('`sounds/`', 1, true) and found_words(files, OUTSIDE) == '', files);

local installing = guide:match('\n## Installing\n(.-)\n## ') or '';
local first_step = installing:match('\n1%. ([^\n]*)') or '';
check('step 1 of Installing points at the Releases page on GitHub', first_step:find(REPO .. '/releases', 1, true),
    first_step);

local note = guide:match('\n> ([^\n]*)') or '';
check('the Phoenix note says staff approved cadence',
    note:find('**Phoenix staff approved cadence, so you can use it on Phoenix.**', 1, true), note);
check('it says the resting sound plays when you press Play too', note:find('or when you press Play', 1, true), note);
for name, text in pairs(public_docs) do
    local waiting = found_words(text, { 'pre%-release', 'rule 9', 'waiting on staff', 'waiting for staff' });
    check(name .. ' says nothing about pre-releases or waiting on staff', waiting == '', waiting);
end

check('the License section says the two sounds belong to Square Enix', guide:find('\n## License\n.-They belong '
    .. 'to Square Enix and aren\'t covered by the GPL%.'));
-- Public documents are outside the release zip, so a file in it says this too.
check('so does sound.lua, which is in the zip', read(ADDON_DIR .. '/ui/sound.lua'):find('They belong to Square\n'
    .. '    Enix, and the GPL doesn\'t cover them.', 1, true));
-- An open sound file can't be deleted, and new files only run after a load.
local update = guide:match('\nTo update, ([^\n]*)') or '';
check('To update starts with unloading cadence and ends with loading it', update:find('^type `/addon unload cadence` '
    .. 'first, or close the game%.') and update:find('type `/addon load cadence`%.'), update);

-- The overview stays short, while the guide keeps all command, settings and timing sections.
local words = 0;
for _ in readme:gmatch('%S+') do words = words + 1; end
check('README stays a short overview', words <= 800 and not readme:find('\n## Commands\n'), words);
check('README links the guide, latest release and changelog',
    readme:find('](docs/GUIDE.md)', 1, true) and readme:find(REPO .. '/releases/latest', 1, true)
    and readme:find('](CHANGELOG.md)', 1, true));
check('the guide links back to the overview and release changes',
    guide:find('](../README.md)', 1, true) and guide:find('](../CHANGELOG.md)', 1, true));
check('README keeps staff approval, the author and the display-only boundary',
    readme:find('Phoenix staff approved cadence', 1, true) and readme:find('Author: **Kipling**', 1, true)
    and readme:find('never writes to game memory', 1, true));
check('README keeps the sound ownership and separate license',
    readme:find('Square Enix', 1, true) and readme:find('not covered by the GPL', 1, true));
local short_install = readme:match('\n## Install or update\n(.-)\n## ') or '';
local unload_at = short_install:find('/addon unload cadence', 1, true);
local replace_at = short_install:find('remove the old', 1, true);
local load_at = short_install:find('/addon load cadence', 1, true);
check('README puts unload before replacing the addon and loading it again',
    unload_at and replace_at and load_at and unload_at < replace_at and replace_at < load_at);
check('README keeps the configuration folder when updating',
    short_install:find('Leave `config\\addons\\cadence\\` in place when updating.', 1, true));

local function heading_anchors(text)
    local anchors, counts = {}, {};
    local fenced = false;
    for line in text:gmatch('[^\n]+') do
        if (line:match('^%s*```') or line:match('^%s*~~~')) then fenced = not fenced; end
        local heading = not fenced and line:match('^#+%s+(.+)');
        if (heading) then
            heading = heading:gsub('%s+#+%s*$', '');
            local base = heading:lower():gsub('[^%w%s_%-]', ''):gsub('%s', '-');
            local count = counts[base] or 0;
            anchors[base .. (count > 0 and ('-' .. count) or '')] = true;
            counts[base] = count + 1;
        end
    end
    return anchors;
end
local guide_anchors, missing_sections = heading_anchors(guide), {};
for _, anchor in ipairs({ 'features', 'installing', 'commands', 'moving-and-styling', 'settings',
    'timers-tab', 'enemy-tab', 'appearance-tab', 'preview-tab', 'details-tab', 'profiles-tab',
    'how-the-auto-attack-timer-works', 'how-the-resting-timer-works', 'how-the-enemy-attack-timer-works',
    'how-the-tp-line-works', 'what-cadence-reads', 'files', 'license' }) do
    if (not guide_anchors[anchor]) then missing_sections[#missing_sections + 1] = anchor; end
end
check('the guide retains all settings, timing, installation and file sections', #missing_sections == 0,
    table.concat(missing_sections, ', '));
local commands = guide:match('\n## Commands\n(.-)\n## ') or '';
local missing_commands = {};
for _, command in ipairs({ '/cadence attack <part>', '/cadence resting <part>', '/cadence enemy <part>',
    '/cadence resting goal', '/cadence preview auto', '/cadence layout preview', '/cadence details',
    '/cadence tab <name>', '/cadence guides', '/cadence relearn', '/cadence attack goal',
    '/cadence attack\\|resting\\|enemy <slider>', '/cadence resting soundfile', '/cadence resting playsound',
    '/cadence preset', '/cadence undo', '/cadence font', '/cadence windowfont', '/cadence color',
    '/cadence windowcolor', '/cadence chatcolor', '/cadence profile save', '/cadence profile overwrite',
    '/cadence profile undooverwrite', '/cadence profile load', '/cadence profile rename',
    '/cadence profile delete', '/cadence profile undo', '/cadence joblink', '/cadence resetsection',
    '/cadence reset all', '/cadence hide', '/cadence info details', '/cadence record', '/cadence report',
    '/cadence help', '/cad' }) do
    if (not commands:find(command, 1, true)) then missing_commands[#missing_commands + 1] = command; end
end
check('the guide retains the command families and short alias', #missing_commands == 0,
    table.concat(missing_commands, ', '));
check('the guide distinguishes overall height from bar thickness',
    guide:find('`height` (Height, 0.5 to 2.5 times normal)', 1, true)
    and guide:find('`barheight` (Bar height, 2 to 32)', 1, true)
    and guide:find("Bar height in settings still changes just the colored bar's thickness.", 1, true));

-- Check local destinations, including README links into the guide and its table of contents.
local function local_path(from, target)
    local parts = {};
    local parent = from:match('^(.*)/') or '';
    for part in (parent .. '/' .. target):gmatch('[^/]+') do
        if (part == '..') then
            if (#parts == 0) then return nil; end
            parts[#parts] = nil;
        elseif (part ~= '.') then
            parts[#parts + 1] = part;
        end
    end
    return table.concat(parts, '/');
end
local anchors_by_path, broken_links = {}, {};
for name, text in pairs(public_docs) do
    for target in text:gmatch('%b[]%(([^%s%)]+)%)') do
        if (not target:find('^%a[%w+%.%-]*:') and not target:find('^//')) then
            local path, anchor = target:match('^([^#]*)#?(.*)$');
            local resolved = path == '' and name or local_path(name, path);
            local body = resolved and public_docs[resolved];
            if (not body and resolved) then
                local file = io.open(ROOT .. '/' .. resolved, 'rb');
                if (file) then body = file:read('*a'); file:close(); end
            end
            if (not body) then
                broken_links[#broken_links + 1] = name .. ' -> ' .. target;
            elseif (anchor ~= '') then
                anchors_by_path[resolved] = anchors_by_path[resolved] or heading_anchors(body);
                if (not anchors_by_path[resolved][anchor]) then
                    broken_links[#broken_links + 1] = name .. ' -> ' .. target;
                end
            end
        end
    end
end
check('all public-document local links and heading anchors resolve', #broken_links == 0,
    table.concat(broken_links, ', '));

-- addon.link and the sounds folder, from the addon itself ------------------------------------------------------
local made = {};
ashita.fs.create_dir = function (path) table.insert(made, path); MOCK.fs[path] = true; return true; end
dofile(ADDON_DIR .. '/cadence.lua');
MOCK.fire('load');
check('addon.link is the repo on GitHub', addon.link == REPO, addon.link);
check('addon.author keeps the public author', addon.author == 'Kipling', addon.author);
check('cadence makes the sounds folder when it loads', made[1] == FOLDER, made[1]);
MOCK.fs[FOLDER], made = nil, {};
MOCK.fire('command', { command = '/cadence' });
MOCK.fire('command', { command = '/cadence' });
MOCK.fs[FOLDER] = nil;
MOCK.fire('command', { command = '/cadence resting soundfile bell' });
check('and again each time it looks for sounds, if it isn\'t there', made[1] == FOLDER and made[2] == FOLDER, #made);
check('The guide says both times', guide:find('makes the folder `config\\addons\\cadence\\sounds\\` when it loads and '
    .. 'each time it looks for sounds, if it isn\'t there.', 1, true));

-- CHANGELOG.md ------------------------------------------------------------------------------------------------
local headings = {};
for line in changelog:gmatch('[^\n]+') do
    if (line:find('^#')) then
        headings[#headings + 1] = line;
    end
end
check('CHANGELOG.md starts with the current version and keeps the first release, with no date',
    table.concat(headings, '|') == '# Changelog|## ' .. addon.version .. '|## 1.0.0', table.concat(headings, '|'));
check('the original release keeps its introduction', changelog:find('\n## 1%.0%.0\n\nFirst release%.\n'));
local original = (changelog:match('\n(## 1%.0%.0\n.*)') or ''):gsub('\r\n', '\n');
local a, b = 1, 0;
for i = 1, #original do
    a = (a + original:byte(i)) % 65521;
    b = (b + a) % 65521;
end
check('the published 1.0.0 section stays unchanged', #original == 5007 and b * 65536 + a == 2969819990);
local current = (changelog:match('\n## ' .. addon.version:gsub('%.', '%%.') .. '\n(.-)\n## ') or ''):lower();
local missing_current = {};
for _, words in ipairs({ 'store tp', 'food', 'dual wield', 'martial arts', 'clear mind', 'signet', 'regen', 'refresh',
    'gear haste and slow', 'percentage delay', 'hundred fists', 'blue magic', 'assault', '1000, 2000 or 3000',
    'successful hits', 'time to tp goal', 'next tick gains', 'ticks until full', 'recovery goals', 'details',
    'sleep, stun, petrification and terror', 'duration estimates', 'character and zone changes', 'mint and lavender',
    'previous and next match', 'starter layouts', 'preview', 'eight settings changes', 'undo overwrite', 'undo delete',
    'tab choices stay with each character', 'shift' }) do
    if (not current:find(words, 1, true)) then missing_current[#missing_current + 1] = words; end
end
check('the current release notes cover all changes since the published release', #missing_current == 0,
    table.concat(missing_current, ', '));
local log = original:lower();
local MISSING = {};
for _, words in ipairs({ 'auto attack timer', 'job abilities', 'casting', 'too far', 'your tp', 'resting timer',
    'flash on each tick', 'diseased', 'enemy attack timer', 'party member', 'slow, elegy, haste and hundred fists',
    '"tp move"', 'last attack was on you', 'by name and zone', 'slim strip', 'six presets', 'colorblind safe',
    'custom (from phoenix)', 'undo', 'text shadow or outline', '.ttf or .otf', 'shift and drag', 'lock the timers',
    'share one spot', 'cutscenes', '/cadence hide', '(?)', 'see through', 'window colors tab', '/cadence chatcolor',
    'a command for every setting', '/cad', '/cadence info', 'one layout', 'profile', 'main job',
    'checks your settings', 'once resting fills your hp and mp', 'ff vii save', 'ff ix moogle', '.mp3 or .wav' }) do
    if (not log:find(words, 1, true)) then
        MISSING[#MISSING + 1] = words;
    end
end
check('it covers what cadence does, the sound and its two sounds included', #MISSING == 0, table.concat(MISSING, ', '));

-- The addon's own text ------------------------------------------------------------------------------------------
-- The comments and the string literals in Lua source.
local function comments_and_strings(src)
    local comments, strings = {}, {};
    local i, n = 1, #src;
    while (i <= n) do
        local c = src:sub(i, i);
        local level = src:match('^%[(=*)%[', i);
        if (src:sub(i, i + 1) == '--') then
            local long = src:match('^%[(=*)%[', i + 2);
            local stop = long and select(2, src:find(']' .. long .. ']', i, true)) or (src:find('\n', i, true) or n);
            comments[#comments + 1] = src:sub(i, stop);
            i = stop + 1;
        elseif (c == '"' or c == '\'') then
            local j = i + 1;
            while (j <= n and src:sub(j, j) ~= c) do
                j = j + ((src:sub(j, j) == '\\') and 2 or 1);
            end
            strings[#strings + 1] = src:sub(i + 1, j - 1);
            i = j + 1;
        elseif (level ~= nil) then
            local _, stop = src:find(']' .. level .. ']', i, true);
            strings[#strings + 1] = src:sub(i, stop);
            i = stop + 1;
        else
            i = i + 1;
        end
    end
    return table.concat(comments, '\n'), table.concat(strings, '\n');
end

-- What players see can't sound unfinished either.
local SAID = { '%f[%a]debug', '%f[%a]beta%f[%A]', 'untested', 'experimental' };
local sources, comment_words, string_words, private_paths = files_in(ADDON_DIR, '*.lua', true), {}, {}, {};
for _, path in ipairs(sources) do
    local source = read(path);
    local comments, strings = comments_and_strings(source);
    local name = path:match('cadence\\(.*)$') or path;
    if (found_words(source:gsub('\\', '/'), PRIVATE) ~= '') then private_paths[#private_paths + 1] = name; end
    local words = found_words(comments, TESTING);
    if (words ~= '') then comment_words[#comment_words + 1] = name .. ': ' .. words; end
    -- Item names are source data, so names such as Taranis's Harness are not development prose.
    words = path:find('data\\phoenix_modifiers.lua', 1, true) and ''
        or (found_words(strings, MAKING) .. found_words(strings, SAID));
    if (words ~= '') then string_words[#string_words + 1] = name .. ': ' .. words; end
end
check('every .lua file in the addon is read', #sources >= 20 and table.concat(sources, '|'):find('ui\\sound.lua', 1, true),
    #sources);
check('no comment in the addon talks about tests, mocks or the preview', #comment_words == 0,
    table.concat(comment_words, ' || '));
check('no tip, help line or chat line talks about tests or how cadence is made', #string_words == 0,
    table.concat(string_words, ' || '));
check('no runtime file has personal or character-specific paths', #private_paths == 0,
    table.concat(private_paths, ', '));

-- The developer docs ------------------------------------------------------------------------------------------------
local tests_readme = read(ROOT .. '/tests/README.txt');
local unnamed, gone = {}, {};
for _, mask in ipairs({ 'test_*.lua', 'test_*.py', 'shots_*.lua' }) do
    for _, name in ipairs(files_in(ROOT .. '/tests', mask)) do
        if (not tests_readme:find(name, 1, true)) then
            unnamed[#unnamed + 1] = name;
        end
    end
end
for name in tests_readme:gmatch('%f[%w_](%a+_[%w_]+%.[lp][uy]a?)%f[^%w_.]') do
    if (name:find('^test_') or name:find('^shots_')) then
        local file = io.open(ROOT .. '/tests/' .. name, 'rb');
        if (file == nil) then gone[#gone + 1] = name; else file:close(); end
    end
end
check('tests\\README.txt names every test file', #unnamed == 0, table.concat(unnamed, ', '));
check('and every one it names is there', #gone == 0, table.concat(gone, ', '));

check('tools\\README.txt has no steps for sending a version to staff',
    not read(ROOT .. '/tools/README.txt'):lower():find('staff', 1, true));

table.insert(out, fails == 0 and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
