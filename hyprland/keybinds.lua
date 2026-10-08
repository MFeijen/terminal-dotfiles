-- AeroSpace parity: the binds from aerospace/aerospace.toml, so the same
-- layout of keys does the same thing on the Mac and here. install.sh symlinks
-- this to ~/.config/hypr/custom/keybinds.lua, which end-4's hyprland.lua loads
-- after its own keybinds (and which its updates never overwrite).

-- aerospace's alt-* binds live on Super here, and general.lua swaps Alt and
-- Super, so they're still pressed with the Alt key.
local mod = "SUPER"
local terminal = "ghostty"

hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Lua binds stack rather than replace, so a key end-4 already uses would fire
-- both. Clear end-4's bind first. hl.unbind only matches the exact spelling,
-- so keycode aliases (end-4 binds "SUPER + code:10" next to "SUPER + 1") are
-- cleared separately below.
local function rebind(keys, action, opts)
    hl.unbind(keys)
    hl.bind(keys, action, opts)
end

-- vim key, Hyprland direction, label
local dirs = { { "H", "l", "left" }, { "J", "d", "down" }, { "K", "u", "up" }, { "L", "r", "right" } }
-- keycodes of keypad 1-8 (same table as end-4's keybinds.lua; check with `wev`)
local keypad = { 87, 88, 89, 83, 84, 85, 79, 80 }

-- Hyprland has no accordion layout. A group (tabbed stack) is the closest
-- thing, so accordion pulls every tiled window on the workspace into one
-- group, like aerospace switching the root container to accordion.
local function accordion()
    local win = hl.get_active_window()
    if not win or win.floating or win.group then return end
    hl.dispatch(hl.dsp.group.toggle())
    if not win.group then return end
    for _, other in ipairs(hl.get_workspace_windows(win.workspace.id)) do
        if not other.floating and not other.group then
            win.group:add(other)
        end
    end
end

-- `layout tiles horizontal vertical`: leave the accordion if in one,
-- otherwise flip the split between side-by-side and stacked.
local function tiles()
    local win = hl.get_active_window()
    if not win then return end
    if win.group then
        hl.dispatch(hl.dsp.group.toggle())
    else
        hl.dispatch(hl.dsp.layout("togglesplit"))
    end
end

-- flatten-workspace-tree: the only nesting these binds create is groups
-- (accordion, join-with), so resetting the layout means dissolving them.
-- Toggling one member dissolves its whole group, and window objects are
-- live, so the other members read as ungrouped by the time we reach them.
local function flatten()
    local win = hl.get_active_window()
    if not win then return end
    for _, other in ipairs(hl.get_workspace_windows(win.workspace.id)) do
        if other.group then hl.dispatch(hl.dsp.group.toggle({ window = other })) end
    end
end

local function close_all_but_current()
    local win = hl.get_active_window()
    if not win then return end
    for _, other in ipairs(hl.get_workspace_windows(win.workspace.id)) do
        if other.address ~= win.address then
            hl.dispatch(hl.dsp.window.close({ window = other }))
        end
    end
end

rebind(mod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "AeroSpace: Terminal" })
rebind(mod .. " + Q", hl.dsp.window.close(), { description = "AeroSpace: Close window" })

rebind(mod .. " + Slash", tiles, { description = "AeroSpace: Tiles / flip split" })
rebind(mod .. " + Comma", accordion, { description = "AeroSpace: Accordion" })

for _, d in ipairs(dirs) do
    local key, dir, label = d[1], d[2], d[3]
    rebind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }), { description = "AeroSpace: Focus " .. label })
    -- group_aware: a window steps out of an accordion the way it leaves an
    -- aerospace container
    rebind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir, group_aware = true }),
        { description = "AeroSpace: Move " .. label })
end

-- workspace --wrap-around prev/next: m-/m+ cycle this monitor's workspaces
rebind(mod .. " + CTRL + H", hl.dsp.focus({ workspace = "m-1" }), { description = "AeroSpace: Previous workspace" })
rebind(mod .. " + CTRL + L", hl.dsp.focus({ workspace = "m+1" }), { description = "AeroSpace: Next workspace" })

-- resize smart -50/+50. Dwindle has no "along the parent" axis, so this
-- resizes both; an axis with no neighbour to push against just doesn't move.
rebind(mod .. " + Minus", hl.dsp.window.resize({ x = -50, y = -50, relative = true }),
    { repeating = true, description = "AeroSpace: Shrink window" })
rebind(mod .. " + Equal", hl.dsp.window.resize({ x = 50, y = 50, relative = true }),
    { repeating = true, description = "AeroSpace: Grow window" })

for i = 1, 8 do
    hl.unbind(mod .. " + code:" .. (9 + i)) -- end-4's number-row alias of mod+i
    rebind(mod .. " + " .. i, hl.dsp.focus({ workspace = i }), { description = "AeroSpace: Workspace " .. i })
    rebind(mod .. " + code:" .. keypad[i], hl.dsp.focus({ workspace = i }))
    -- follow = false: move-node-to-workspace leaves focus where it was
    rebind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i, follow = false }),
        { description = "AeroSpace: Send window to workspace " .. i })
    rebind(mod .. " + SHIFT + code:" .. keypad[i], hl.dsp.window.move({ workspace = i, follow = false }))
end

-- aerospace's fullscreen keeps the menu bar and gaps, which is Hyprland's
-- "maximized"; real fullscreen moves to SHIFT below
rebind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "AeroSpace: Fullscreen" })

rebind(mod .. " + Tab", hl.dsp.focus({ workspace = "previous" }), { description = "AeroSpace: Workspace back and forth" })
rebind(mod .. " + SHIFT + Tab", hl.dsp.workspace.move({ monitor = "+1" }),
    { description = "AeroSpace: Move workspace to next monitor" })

rebind(mod .. " + SHIFT + Semicolon", hl.dsp.submap("service"), { description = "AeroSpace: Service mode" })
rebind(mod .. " + R", hl.dsp.submap("resize"), { description = "AeroSpace: Resize mode" })

hl.define_submap("resize", function()
    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("H", hl.dsp.window.resize({ x = -50, y = 0, relative = true }), { repeating = true })
    hl.bind("J", hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
    hl.bind("K", hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true })
    hl.bind("L", hl.dsp.window.resize({ x = 50, y = 0, relative = true }), { repeating = true })
end)

-- Every service action ends in `mode main` in aerospace; the "reset" here
-- drops back to the global binds after any bind in this submap fires.
hl.define_submap("service", "reset", function()
    hl.bind("Escape", hl.dsp.exec_cmd("hyprctl reload"))
    hl.bind("R", flatten)
    hl.bind("F", hl.dsp.window.float({ action = "toggle" }))
    hl.bind("BackSpace", close_all_but_current)
    -- join-with: put the window and its neighbour in a group together
    for _, d in ipairs(dirs) do
        hl.bind(mod .. " + SHIFT + " .. d[1], hl.dsp.window.move({ into_or_create_group = d[2] }))
    end
end)

-- end-4 binds pushed off their keys above, moved where they still fit.
-- Still reachable without a key of their own: suspend (session menu,
-- CTRL+ALT+Delete), overview (4-finger swipe up), zoom (Super + keypad -/+).
-- Dropped: bar toggle (J), on-screen keyboard (K).
rebind("CTRL + SUPER + Q", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Session: Lock" })
rebind("SUPER + SHIFT + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet" })
rebind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    { description = "Window: Fullscreen" })
