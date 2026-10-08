-- Settings on top of end-4's hyprland/general.lua: gaps and focus behaviour
-- from aerospace/aerospace.toml, plus Caps Lock/Escape and Alt/Super swapped.
-- install.sh symlinks this to ~/.config/hypr/custom/general.lua.

hl.config({
    general = {
        -- aerospace's inner gap (10) is the whole space between two windows;
        -- Hyprland pads each window by gaps_in, so 5 renders the same 10px
        gaps_in = 5,
        gaps_out = 5,
    },
    input = {
        follow_mouse = 1, -- focus-follows-mouse.enabled = true
        -- the Alt key acts as Super (and Super as Alt), so super-* binds sit
        -- on the same key as aerospace's alt-* on the Mac
        kb_options = "caps:swapescape,altwin:swap_alt_win",
    },
    binds = {
        -- alt-hjkl walks through an accordion (group) before leaving it,
        -- like focus inside an aerospace accordion container
        movefocus_cycles_groupfirst = true,
    },
})
