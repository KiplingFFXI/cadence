-- Time until full with and without Regen, presets, one layout for all characters, and the timer
-- options through the whole addon.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and math.abs(a - b) <= (eps or 1e-6); end

addon.name = 'cadence';
local resting       = require('core.resting');
local presets       = require('ui.presets');
local defaults      = require('ui.defaults');
local theme         = require('ui.theme');
local shared_layout = require('core.shared_layout');

-- Time until full ------------------------------------------------------------------------------
do
    resting.reset();
    resting.on_vitals(-1, 500, 100, 0, 1000, 400);
    resting.start(0);
    check('no estimate before a tick', resting.until_full(5) == nil);
    resting.on_vitals(21.0, 510, 112, 0, 1000, 400);
    check('seen_at is the tick time', resting.seen_at() == 21.0, resting.seen_at());
    check('no estimate after only one tick', resting.until_full(21.0) == nil, tostring(resting.until_full(21.0)));
    -- A second tick teaches the real step. HP steps 1 per tick, MP steps 2 like Clear Mind.
    -- HP needs 22 more ticks at +12, +13, ... and MP needs 11 at +16, +18, ..., so HP decides.
    resting.on_vitals(30.2, 521, 126, 0, 1000, 400);
    local seconds = resting.until_full(30.2);
    local _, left = resting.progress(30.2);
    check('until full after two ticks', near(seconds, left + 21 * 10), tostring(seconds) .. ' vs ' .. tostring(left + 210));
    resting.on_vitals(31.0, 1000, 400, 0, 1000, 400);
    check('no estimate once full', resting.until_full(31.0) == nil);
end

-- Time until full with Regen -------------------------------------------------------------------
do
    resting.reset();
    resting.on_vitals(-1, 500, 380, 0, 1000, 400);
    resting.start(0);
    -- Regen adds 5 HP on every 3 s pass, and rides along in the tick packets.
    local hp = 500;
    for t = 3, 18, 3 do
        hp = hp + 5;
        resting.on_vitals(t, hp, 380, 0, 1000, 400);
    end
    hp = hp + 15;
    resting.on_vitals(21.0, hp, 392, 0, 1000, 400);
    for t = 24, 27, 3 do
        hp = hp + 5;
        resting.on_vitals(t, hp, 400, 0, 1000, 400);
    end
    hp = hp + 16;
    resting.on_vitals(30.0, hp, 400, 0, 1000, 400);
    -- The resting part is +10 then +11, plus 5 a pass. 429 HP takes 13 ticks. Without Regen it
    -- would be 20, and counting Regen as part of the tick would give 18.
    local seconds = resting.until_full(30.0);
    local _, left = resting.progress(30.0);
    check('regen counted in until full', near(seconds, left + 12 * 10), tostring(seconds) .. ' vs ' .. tostring(left + 120));

    -- A single cure between ticks isn't Regen.
    resting.reset();
    resting.on_vitals(-1, 500, 100, 0, 1000, 400);
    resting.start(0);
    resting.on_vitals(21.0, 510, 112, 0, 1000, 400);
    resting.on_vitals(25.0, 610, 112, 0, 1000, 400);
    resting.on_vitals(30.0, 621, 125, 0, 1000, 400);
    -- 379 HP at +12, +13, ... takes 19 ticks, 275 MP at +14, +15, ... takes 14.
    seconds = resting.until_full(30.0);
    _, left = resting.progress(30.0);
    check('a cure is not taken for Regen', near(seconds, left + 18 * 10), tostring(seconds) .. ' vs ' .. tostring(left + 180));
end

-- Presets --------------------------------------------------------------------------------------
do
    local s = defaults.make();
    presets.apply(s, 'High contrast');
    check('high contrast panel is black', near(s.style.panel_color[1], 0) and near(s.style.panel_color[4], 0.92));
    check('preset keeps sizes', s.attack.width == 240 and s.style.scale == 1.0);
    check('preset keeps what is shown', s.attack.show_value == true and s.resting.show_until_full == true);
    presets.apply(s, 'Minimal');
    check('minimal turns the card off', s.style.panel == false and s.style.border == false and s.style.rounding == 3);
    presets.apply(s, 'Phoenix');
    local d = defaults.make();
    check('phoenix matches the defaults', near(s.style.panel_color[1], d.style.panel_color[1])
        and s.style.accent == true and s.style.rounding == 0 and near(s.attack.almost_color[1], d.attack.almost_color[1]));
    s.style.panel_color[1] = 0.5;
    presets.apply(s, 'Classic FFXI');
    local again = defaults.make();
    check('presets never share tables with the defaults', again.style.panel_color[1] ~= 0.5);
end

-- One layout for all characters ----------------------------------------------------------------
do
    local mine = defaults.make();
    shared_layout.turn_off(mine);
    mine.style.scale = 1.75;
    local layout = shared_layout.turn_on(mine);
    layout.attack.x = 123;
    layout.resting.flash_color[1] = 0.25;
    shared_layout.save();
    check('sharing is on, with a copy to change', shared_layout.is_on() and layout ~= mine and layout.style.scale == 1.75
        and layout.resting.flash_color ~= mine.resting.flash_color);
    check('changing the copy leaves your own alone', mine.attack.x == 780 and mine.resting.flash_color[1] ~= 0.25);
    check('on again keeps the same copy', shared_layout.turn_on(mine) == layout);

    local other = defaults.make();
    local theirs = shared_layout.apply(other);
    check('another character takes the shared layout', theirs.style.scale == 1.75 and theirs.attack.x == 123
        and near(theirs.resting.flash_color[1], 0.25), theirs.style.scale);
    check('in a copy, with their own left alone', theirs ~= other and other.style.scale == 1.0 and other.attack.x == 780);

    check('turning it off gives back their own', shared_layout.turn_off(other) == other and not shared_layout.is_on());
    check('with the shared layout in it', other.style.scale == 1.75 and other.attack.x == 123
        and near(other.resting.flash_color[1], 0.25), other.attack.x);
    local third = defaults.make();
    check('after that a login gets its own', shared_layout.apply(third) == third and third.style.scale == 1.0);
end

-- Timer options through the whole addon --------------------------------------------------------
do
    MOCK.fs['C:\\Windows\\Fonts\\seguisb.ttf'] = true;
    os.getenv = function (k) if (k == 'WINDIR') then return 'C:\\Windows'; end end;
    MOCK.items[16535] = { Delay = 240, Skill = 3 };
    MOCK.player.equipment[0] = 16535;
    dofile(ADDON_DIR .. '/cadence.lua');
    MOCK.fire('load');
    local s = MOCK.settings.current;
    local hud = require('ui.hud');

    local function frames(n, dt)
        MOCK.imgui_calls = {};
        MOCK.record_imgui = true;
        for _ = 1, n do MOCK.frame(dt); end
        MOCK.record_imgui = false;
    end
    local function count(name, match)
        local n = 0;
        for _, c in ipairs(MOCK.imgui_calls) do
            if (c[1] == name and (match == nil or match(c))) then n = n + 1; end
        end
        return n;
    end

    s.style.rounding = 6;
    hud.refresh(s);
    -- Idle first, so cadence sees the fight start and knows when the first attack is due.
    MOCK.now = 100 - 1 / 60;
    frames(1);
    MOCK.player.status = 1;
    frames(1);
    -- The first attack is due at 102.8. At 102.5 the bar is inside the 0.5 s almost ready window.
    MOCK.now = 102.5;
    frames(1);
    local almost = theme.u32(s.attack.almost_color);
    check('almost ready color used', count('dl:AddRectFilled', function (c) return c[4] == almost; end) >= 1);
    check('rounded corners drawn', count('dl:AddRectFilled', function (c) return (c[5] or 0) > 0; end) >= 1);
    check('clip rects balanced', count('dl:PushClipRect') == count('dl:PopClipRect') and count('dl:PushClipRect') >= 1);

    s.attack.almost_ready = false;
    hud.refresh(s);
    frames(1);
    check('almost ready can be turned off', count('dl:AddRectFilled', function (c) return c[4] == almost; end) == 0);

    -- Tick flash on the resting timer.
    MOCK.player.status = 33;
    MOCK.player.mp_max = 400;
    MOCK.fire('packet_in', MOCK.vitals_packet(1001, 500, 100, 0));
    MOCK.now = 110;
    frames(1);
    MOCK.now = 131.2;
    MOCK.fire('packet_in', MOCK.vitals_packet(1001, 510, 112, 0));
    frames(1);
    local flashes_on = count('dl:AddRectFilled');
    s.resting.flash_on_tick = false;
    hud.refresh(s);
    frames(1);
    local flashes_off = count('dl:AddRectFilled');
    check('flash adds a layer right after a tick', flashes_on == flashes_off + 1, flashes_on .. ' vs ' .. flashes_off);

    -- At a shared spot with the window open and nothing live, only the auto attack sample shows.
    MOCK.player.status = 0;
    s.style.shared_spot = true;
    hud.refresh(s);
    MOCK.fire('command', { command = '/cadence' });
    frames(3);
    check('shared spot shows one sample', count('Begin', function (c) return c[2] == '##cadence_resting'; end) == 0
        and count('Begin', function (c) return c[2] == '##cadence_attack'; end) == 3);
    MOCK.fire('command', { command = '/cadence' });

    -- Resting with the shared spot puts the resting timer where the auto attack timer is.
    s.attack.x, s.attack.y = 555, 444;
    hud.refresh(s);
    MOCK.player.status = 33;
    frames(1);
    local placed = false;
    for _, c in ipairs(MOCK.imgui_calls) do
        if (c[1] == 'SetNextWindowPos' and c[2][1] == 555 and c[2][2] == 444) then placed = true; end
    end
    check('resting timer sits on the auto attack spot', placed);

    -- A live resting timer at the shared spot keeps the auto attack sample away while the window is open.
    MOCK.fire('command', { command = '/cadence' });
    frames(1);
    check('live resting timer beats the auto attack sample', count('Begin', function (c) return c[2] == '##cadence_attack'; end) == 0
        and count('Begin', function (c) return c[2] == '##cadence_resting'; end) == 1);
    MOCK.fire('command', { command = '/cadence' });

    -- "full in" switches to minutes past 60 seconds, and a long detail on a narrow timer is cut off.
    local function drawn_text(view)
        MOCK.imgui_calls = {};
        MOCK.record_imgui = true;
        hud.begin_frame();
        hud.draw_resting(view);
        hud.end_frame();
        MOCK.record_imgui = false;
        local texts = {};
        for _, c in ipairs(MOCK.imgui_calls) do
            if (c[1] == 'dl:AddText') then table.insert(texts, c[6]); end
        end
        return table.concat(texts, '|');
    end
    local view = { fill = 0.5, left = 5, gained_hp = 24, gained_mp = 31, full = false, until_full = 95, flash = 0 };
    check('full in uses minutes', drawn_text(view):find('full in 1:35', 1, true) ~= nil, drawn_text(view));
    view.until_full = 42;
    check('full in uses seconds under a minute', drawn_text(view):find('full in 42s', 1, true) ~= nil, drawn_text(view));
    s.resting.width = 120;
    hud.refresh(s);
    drawn_text(view);
    check('narrow detail is cut off', count('dl:PushClipRect') == count('dl:PopClipRect') and count('dl:PushClipRect') >= 2);
    s.resting.width = 240;
    hud.refresh(s);

    local errors = nil;
    for _, line in ipairs(MOCK.printed) do if (line:find('Drawing stopped')) then errors = line; end end
    check('no drawing errors', errors == nil, errors);
end

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
