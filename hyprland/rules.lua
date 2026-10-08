-- AeroSpace parity: persistent-workspaces 1-8 and
-- workspace-to-monitor-force-assignment from aerospace/aerospace.toml.
-- install.sh symlinks this to ~/.config/hypr/custom/rules.lua.

-- aerospace numbers monitors left to right. HDMI-A-1 sits left of the laptop
-- (see the monitor block in hyprland/general.lua), so aerospace's monitor 1
-- is HDMI-A-1 and monitor 2 is eDP-1.
local laptop, external = "eDP-1", "HDMI-A-1"

for i = 1, 8 do
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = i <= 4 and external or laptop,
        persistent = true,
        -- each monitor opens on the first of its workspaces
        default = i == 1 or i == 5,
    })
end
