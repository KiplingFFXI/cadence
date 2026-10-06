-- Each run of the tests writes into its own folder in %TEMP%, so two runs at once can't break each other.
local out, fails = {}, 0;
local function check(name, cond, detail)
    if (cond) then table.insert(out, 'ok   ' .. name);
    else fails = fails + 1; table.insert(out, 'FAIL ' .. name .. (detail and ('  -> ' .. tostring(detail)) or '')); end
end

local path = tostring(MOCK_INSTALL_PATH):gsub('/', '\\');
local folder = path:match('([^\\]+)\\?$') or '';

-- tempfile.mkdtemp ends the name with 8 random characters, so no two runs get the same folder.
check('the folder has a name of its own for this run', folder:find('^cadence_tests_[%w_]+$') ~= nil
    and #folder == #'cadence_tests_' + 8, folder);

-- The addon writes its settings and shared_layout.json here.
local probe = path .. '\\config\\addons\\cadence\\run_folder_check.txt';
local file = io.open(probe, 'w');
check('the addon can write into it', file ~= nil, probe);
if (file ~= nil) then
    file:close();
    os.remove(probe);
end

table.insert(out, (fails == 0) and 'ALL PASSED' or (fails .. ' FAILED'));
return table.concat(out, '\n');
