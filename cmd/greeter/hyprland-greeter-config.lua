-- sysc-greet greeter session (Hyprland variant). greetd runs it as the
-- `greeter` user: start-hyprland -- --config /etc/greetd/hyprland-greeter-config.lua
--
-- Managed by 'setup greeter apply' — replaces the file sysc-greet-hyprland ships.
-- That one is in the package's backup=, so upgrades leave this alone and drop a
-- .pacnew next to it instead.
--
-- Same as upstream, plus one thing: the login lands on the monitor pinned in
-- /etc/greetd/greeter-output (EDID descriptions, most wanted first — connector
-- names move every time a driver update renumbers them), and EVERY OTHER OUTPUT
-- STAYS OFF, like in the session's monitors.lua.
--
-- Why off and not just unfocused: with all of them on, Hyprland segfaulted 2s
-- into the greeter in Aquamarine::CDRMBackend::flushAsyncCommitEvents (a
-- page-flip on the TV, which sits in standby with no CRTC), start-hyprland
-- relaunched it in safe mode, safe mode skips this file, and the login came up
-- on the TV with "your config has errors". The session, which only lights the
-- Samsung, never crashes.
--
-- The choice is made here, while parsing, so the other outputs are never
-- modeset at all — turning them off later would be the same teardown that
-- crashes. hl.get_monitors() is empty this early, so the EDIDs are read from
-- /sys/class/drm directly.

local GREETER_ENV = "cd /var/lib/greeter && env HOME=/var/lib/greeter"
    .. " XDG_CACHE_HOME=/var/lib/greeter/.cache"
    .. " XDG_CONFIG_HOME=/var/lib/greeter/.config"
    .. " XDG_STATE_HOME=/var/lib/greeter/.local/state"
local WANT_FILE = "/etc/greetd/greeter-output"

-- Same pointer as the session (hyprland/execs.lua), so it does not change shape
-- at login.
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")

hl.config({
    animations = { enabled = false },
    decoration = {
        rounding = 0,
        blur = { enabled = false },
        shadow = { enabled = false },
    },
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    input = { kb_layout = "us", repeat_delay = 400, repeat_rate = 40 },
    misc = { disable_hyprland_logo = true },
})

hl.window_rule({ match = { class = "kitty" }, rounding = 0 })

-- Descriptions (or connector names) from WANT_FILE, most wanted first.
local function wanted_outputs()
    local wants = {}
    local f = io.open(WANT_FILE, "r")
    if not f then return wants end
    for raw in f:lines() do
        local line = raw:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then table.insert(wants, line) end
    end
    f:close()
    return wants
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("a")
    f:close()
    return data
end

-- Product name (descriptor 0xFC), serial as text (0xFF) and numeric serial
-- (bytes 12-15) from an EDID base block. Hyprland's description is make +
-- name + whichever serial exists, so matching name and either serial covers it.
local function edid_fields(blob)
    if not blob or #blob < 128 then return nil end
    local name, serial = "", ""
    for _, off in ipairs({ 54, 72, 90, 108 }) do
        local d = blob:sub(off + 1, off + 18)
        if d:sub(1, 3) == "\0\0\0" then
            local text = d:sub(6):match("^[^\n]*"):match("^%s*(.-)%s*$")
            if d:byte(4) == 0xFC then name = text elseif d:byte(4) == 0xFF then serial = text end
        end
    end
    local b1, b2, b3, b4 = blob:byte(13, 16)
    return name, serial, string.format("0x%08X", b1 | b2 << 8 | b3 << 16 | b4 << 24)
end

-- { name = "DP-3", model = ..., serial = ..., serial_hex = ... } per connected output.
local function connected_outputs()
    local outputs = {}
    local ls = io.popen("ls -d /sys/class/drm/card*-* 2>/dev/null")
    if not ls then return outputs end
    for dir in ls:lines() do
        if (read_file(dir .. "/status") or ""):match("^connected") then
            local model, serial, serial_hex = edid_fields(read_file(dir .. "/edid"))
            table.insert(outputs, {
                name = dir:match("card%d+%-(.+)$"),
                model = model or "", serial = serial or "", serial_hex = serial_hex or "",
            })
        end
    end
    ls:close()
    return outputs
end

local function matches(output, want)
    if output.name == want then return true end
    if output.model == "" or not want:find(output.model, 1, true) then return false end
    return (output.serial ~= "" and want:find(output.serial, 1, true) ~= nil)
        or want:find(output.serial_hex, 1, true) ~= nil
end

-- Connector of the first wanted monitor that is connected, plus all connected
-- outputs. nil means "wherever Hyprland puts it", the safe way to fail: a login
-- on the wrong screen beats no login.
local function greeter_monitor()
    local outputs = connected_outputs()
    for _, want in ipairs(wanted_outputs()) do
        for _, o in ipairs(outputs) do
            if matches(o, want) then return o.name, outputs end
        end
    end
    return nil, outputs
end

local GREETER_MONITOR, OUTPUTS = greeter_monitor()

if GREETER_MONITOR then
    hl.monitor({ output = GREETER_MONITOR, mode = "preferred", position = "0x0", scale = "auto" })
    for _, o in ipairs(OUTPUTS) do
        if o.name ~= GREETER_MONITOR then hl.monitor({ output = o.name, disabled = true }) end
    end
else
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end

hl.on("hyprland.start", function()
    hl.exec_cmd(GREETER_ENV .. " /usr/local/bin/sysc-greet --wallpaper-daemon")

    -- sysc-greet treats the FOCUSED output as its primary, so focus matters as
    -- much as where kitty opens.
    local greeter = GREETER_ENV
        .. " kitty --start-as=fullscreen --config=/etc/greetd/kitty.conf /usr/local/bin/sysc-greet"
        .. " && hyprctl dispatch 'hl.dsp.exit()'"
    if GREETER_MONITOR then
        hl.dispatch(hl.dsp.focus({ monitor = GREETER_MONITOR }))
        hl.exec_cmd(greeter, { monitor = GREETER_MONITOR })
    else
        hl.exec_cmd(greeter)
    end
end)
