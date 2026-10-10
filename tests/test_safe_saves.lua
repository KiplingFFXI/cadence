-- A failed replacement must leave the last saved file and deletion recovery intact.
local out, failed = {}, 0;
local function check(name, yes)
    out[#out+1]=(yes and 'ok   ' or 'FAIL ')..name;
    if (not yes) then failed=failed+1; end
end
addon.name = 'cadence';
local folder=MOCK_INSTALL_PATH..'\\config\\addons\\cadence\\';
local file, layout=folder..'profiles.json',folder..'shared_layout.json';
os.remove(file); os.remove(layout);
local real_open, real_remove, real_exists = io.open, os.remove, ashita.fs.exists;
local function contents(path)
    local f=real_open(path,'r'); if (not f) then return nil; end
    local s=f:read('*a');f:close();return s;
end
ashita.fs.exists=function(path) return contents(path)~=nil or real_exists(path); end;
local profiles=require('ui.profiles');
local defaults=require('ui.defaults');
local shared=require('core.shared_layout');
local s=defaults.make();
check('initial profile saves',profiles.save(s,'Keep'));
local before=contents(file);
local function failed_write(mode)
    io.open=function(path, access)
        if (access=='w' and path:sub(1,#file+1)==file..'.') then
            if (mode=='open') then return nil; end
            local f=assert(real_open(path,access));
            return { write=function(_,text)
                if (mode=='write') then return nil,'disk full'; end
                if (mode=='throw') then error('disk full'); end
                return f:write(text);
            end, close=function()
                local ok=f:close();
                if (mode=='close') then return nil,'flush failed'; end
                return ok;
            end };
        end
        return real_open(path,access);
    end;
    local ok=profiles.save(s,'New');
    io.open=real_open;
    check(mode..' failure preserves the saved bytes and names',not ok and contents(file)==before and not profiles.exists('New'));
end
for _, mode in ipairs({'open','write','throw','close'}) do failed_write(mode); end
MOCK.file_replace_error=true;
check('replacement failure preserves the original file',not profiles.save(s,'New') and contents(file)==before);
MOCK.file_replace_error=nil;
io.open=function(path,access) if (path==file and access=='r') then return nil,'access denied'; end return real_open(path,access); end;
check('read access failure never becomes an empty profile file',not profiles.save(s,'New') and contents(file)==before and not profiles.file_ok());
io.open=real_open;profiles.refresh();
s.job_links[1],s.job_links[2]='Keep','Keep';
check('delete keeps a separate recovery entry',profiles.delete(s,'Keep') and profiles.can_undo_delete() and s.job_links[1]==nil);
s.job_links[2]='New choice';
MOCK.file_replace_error=true;
check('failed undo remains available',not profiles.undo_delete(s) and profiles.can_undo_delete() and not profiles.exists('Keep'));
MOCK.file_replace_error=nil;
local ok,name,links=profiles.undo_delete(s);
check('undo restores the profile and only unchanged job links',ok and name=='Keep' and links and s.job_links[1]=='Keep' and s.job_links[2]=='New choice' and not profiles.can_undo_delete());
profiles.delete(s,'Keep');profiles.save(s,'keep');
local recovered,reason=profiles.undo_delete(s);
check('case-insensitive collision cannot overwrite a newer profile',not recovered and reason=='exists' and profiles.can_undo_delete());
-- Another character can recover the shared profile, but not inherit this character's links.
os.remove(file);profiles.refresh();profiles.save(s,'Owner');s.job_links[3]='Owner';profiles.delete(s,'Owner');
local other=defaults.make();ok,name,links=profiles.undo_delete(other);
check('another character never inherits deletion links',ok and name=='Owner' and not links and other.job_links[3]==nil);
local copy=shared.turn_on(s);
check('enabling a shared layout persists it before reporting success',copy and shared.is_on() and contents(layout));
local layout_before=contents(layout);copy.attack.x=222;
MOCK.file_replace_error=true;
check('shared save failure preserves disk and current layout',not shared.save() and contents(layout)==layout_before and copy.attack.x==222);
MOCK.file_replace_error=nil;
check('shared save can be retried',shared.save() and contents(layout)~=layout_before);
os.remove=function(path) if (path==layout) then return nil,'access denied'; end return real_remove(path); end;
check('failed shared removal does not turn off sharing',shared.turn_off(s)==nil and shared.is_on());
os.remove=real_remove;
check('successful shared removal keeps the displayed layout',shared.turn_off(s)==s and not shared.is_on() and s.attack.x==222);
local f=assert(real_open(layout,'w'));f:write('{broken');f:close();
check('malformed shared data is never overwritten on enable',shared.turn_on(s)==nil and contents(layout)=='{broken' and not shared.is_on());
os.remove(layout);os.remove(file);
ashita.fs.exists=real_exists;
-- The same undo is available from the command line, separate from layout Undo.
dofile(ADDON_DIR..'/cadence.lua');MOCK.fire('load');
MOCK.fire('command',{command='/cadence profile save Command'});
MOCK.fire('command',{command='/cadence profile delete Command'});
MOCK.fire('command',{command='/cadence profile undo'});
check('profile undo command restores a deletion',profiles.exists('Command') and not profiles.can_undo_delete());
MOCK.fire('command',{command='/cadence tips off'});
check('hover tips have a command',MOCK.settings.current.style.hover_tips==false);
os.remove(file);os.remove(layout);
out[#out+1]=failed==0 and 'ALL PASSED' or (failed..' FAILED');return table.concat(out,'\n');
