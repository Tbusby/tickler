-- This work is licensed under a Creative Commons Attribution-NonCommercial 4.0 International License.
-- https://creativecommons.org/licenses/by-nc/4.0/

-- TODO:
--    Make a loading bar tick down instead of / aswel as timer number
--    Dont display on /shutdown
--    Make font more visible on light backgrounds
--    Save x,y pos on shutdown/unload

addon.name      = 'tickler';                    
addon.author    = 'nappaa';  
addon.version   = '1.0';                 
addon.desc      = 'A timer for the next tick of resting hp/mp.';  

require 'common'
local chat = require('chat');
local fonts = require('fonts');
local scaling = require('scaling');
local settings = require('settings');

----------------------------------------------------------------------------------------------------
-- Config
----------------------------------------------------------------------------------------------------
local default_settings = 
{
    font = T{
        visible = true,
        font_family = 'Arial',
        font_height = scaling.scale_f(16),
        color = 0xFFFFFFFF,
        bold = true,
        position_x = scaling.scale_w(-180),
        position_y = scaling.scale_h(20),
    },
    show_summary    = false
};
local tickler = T{
    settings = settings.load(default_settings),
    debug = false
};

----------------------------------------------------------------------------------------------------
-- func: update_settings
-- desc: @param {table} s - The new settings table to use for the addon settings. (Optional.)
----------------------------------------------------------------------------------------------------
local function update_settings(s)
    -- Update the settings table..
    if (s ~= nil) then
        tickler.settings = s;
    end

    -- -- Apply the font settings..
    -- if (tickler.displayfont ~= nil) then
    --     tickler.displayfont:apply(tickler.settings.font);
    -- end

    -- Save the current settings..
    settings.save();
end

----------------------------------------------------------------------------------------------------
-- Registers a callback for the settings to monitor for character switches.
----------------------------------------------------------------------------------------------------
settings.register('settings', 'settings_update', update_settings);

----------------------------------------------------------------------------------------------------
-- func: load
-- desc: Event called when the addon is being loaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    -- Set up initial vars
    playerIsResting = false;
    currentTick = 0;
    currentDelay = 20;
    restPacketSent = false;
    restTimer = 
    {
        first      = 0, -- Time of the first tick of our current /heal
        last       = 0, -- Time of the most recent tick of our current /heal
        previous   = 0, -- Time of the second most recent tick of our current /heal
        deltaFirst = 0, -- Seconds between first and last
        deltaLast  = 0, -- Seconds between last and previous
        label      = 0  -- Seconds until next healing tick (this is what gets rendered)
    };

    tickler.displayfont = fonts.new(tickler.settings.font)

end);

----------------------------------------------------------------------------------------------------
-- func: unload
-- desc: Event called when the addon is being unloaded.
----------------------------------------------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    update_settings();
    if (tickler.displayfont ~= nil) then
        tickler.displayfont:destroy();
        tickler.displayfont = nil;
    end
end);

----------------------------------------------------------------------------------------------------
-- func: msg
-- desc: Prints out a message with the Nomad tag at the front.
----------------------------------------------------------------------------------------------------
local function msg(s)
    -- TODO: fix timestamp formatting 
    -- local timestamp = os.date(string.format('\31\%c[%s]\30\01 ', 200, '%H:%M:%S'));
    -- local txt = timestamp .. '\31\200[\31\05' .. _addon.name .. '\31\200]\31\130 ' .. s;
    print(s);
end

----------------------------------------------------------------------------------------------------
-- func: command
-- desc: Event called when a command was entered.
----------------------------------------------------------------------------------------------------
ashita.events.register('command', 'command_cb', function(e)
    -- Get the arguments of the command..
    local args = e.command:args();
    if (args[1] ~= '/tickler') then
        return false;
    end

    -- Toggle debug mode
    if (args[2] == 'debug') then
        tickler.debug = not tickler.debug;
        if tickler.debug == false then
            msg('Debug output disabled')
        else
            msg('Debug output enabled')
        end
        return true;
    end

end);

---------------------------------------------------------------------------------------------------
-- func: outgoing_packet
-- desc: Called when our addon receives an outgoing packet.
---------------------------------------------------------------------------------------------------
ashita.events.register('packet_out', 'packet_out_cb', function(e)
    -- Listen for heal toggle packet
    if (e.id == 0x0E8) then
        restPacketSent = true;
        if (tickler.debug) then msg('DEBUG: Detected outgoing heal toggle packet [0x0E8]') end;
    end

    return false;
end);

---------------------------------------------------------------------------------------------------
-- func: incoming_packet
-- desc: Called when our addon receives an incoming packet.
---------------------------------------------------------------------------------------------------
ashita.events.register('packet_in', 'packet_in_cb', function(e)
    -- Listen for character update packet and read the address that contains player status
    if (e.id == 0x037) then
        if (tickler.debug) then msg('DEBUG: Detected incoming character update packet [0x037]') end;
        local packet = e.data:totable()
        local playerStatus = packet[0x31];
        if (playerStatus == 33) then 
            playerIsResting = true
            if (tickler.debug) then msg('DEBUG: player is resting is ' .. tostring(playerIsResting)) end;
        else
            playerIsResting = false
            if (tickler.debug) then msg('DEBUG: player is resting is ' .. tostring(playerIsResting)) end;
        end

        if (playerIsResting) then
            -- Store time of last tick and then update it
            restTimer.previous = restTimer.last;
            if (restTimer.last == 0) then
                restTimer.last = 0;
            else
                restTimer.previous = restTimer.last;
            end
            
            restTimer.last = os.time();

            -- If this is the first resting update received since sending /heal, record that too
            if (restPacketSent) then
                restTimer.first = restTimer.last;
                restPacketSent = false;
            end

            -- Update deltas
            restTimer.deltaFirst = (restTimer.last - restTimer.first);
            restTimer.deltaLast = (restTimer.last - restTimer.previous);
            -- msg(type(restTimer.last) .. type(restTimer.previous))
            -- msg(restTimer.deltaFirst .. ' ' .. restTimer.deltaLast)

            -- Keep track of how many ticks we've rested
            -- TODO: discard (or count separately) update packets that are not related to resting
            currentTick = currentTick + 1;

            if (tickler.debug) then msg('DEBUG: currentTick is ' .. tostring(currentTick)) end;
            
        else
            -- When we're no longer resting, reset tick counter to 0
            currentTick = 0;

            -- TODO: Show total hp/mp recovered and number of ticks / time rested
            --if (tickler.show_summary) then

        end
        -- Uncomment to show full packet data
        -- for k, v in pairs(packet) do
        --     print(k .. ': ' .. v);
        -- end
    end

    return false;
end);

----------------------------------------------------------------------------------------------------
-- func: d3d_present
-- desc: Event called when the Direct3D device is presenting a scene.
----------------------------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    if (playerIsResting) then
        -- Update the time since our last resting tick
        restTimer.deltaLast = (os.time() - restTimer.last);
        restTimer.label = os.date('%S', restTimer.deltaLast)

        -- Determine delay in seconds for the current resting tick
        if currentTick > 1 then
            currentDelay = 10;
        elseif currentTick == 1 then
            currentDelay = 20;
        end

        restTimer.label = tostring(currentDelay - restTimer.label);
        tickler.displayfont.text = restTimer.label
    else
        -- If we're not resting, blank out the timer
        tickler.displayfont.text = '';
    end

    local positionX = tickler.displayfont.position_x;
    local positionY = tickler.displayfont.position_y;
    if (positionX ~= tickler.settings.font.position_x) or (positionY ~= tickler.settings.font.position_y) then
        tickler.settings.font.position_x = positionX;
        tickler.settings.font.position_y = positionY;
        settings.save();        
    end

end);
