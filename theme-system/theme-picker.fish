function theme --description "Fuzzy-pick a helix theme; syncs kitty + helix live"
    set -l script_dir (dirname (status -f))
    set -l apply "$script_dir/theme-apply.py"

    if not test -x "$apply"
        echo "theme: $apply not found or not executable" >&2
        return 1
    end

    # snapshot current theme so we can restore on cancel
    set -l original (python3 "$apply" --current)
    if test -z "$original"
        set original "default"
    end

    # theme sources, in the order theme-apply.py resolves them
    set -l theme_dirs \
        ~/.config/helix/themes \
        ~/helix-ide/config/helix/themes \
        /usr/lib/helix/runtime/themes \
        "$script_dir/themes"

    set -l themes
    for d in $theme_dirs
        if test -d "$d"
            for f in $d/*.toml
                test -f "$f"; or continue
                set -a themes (basename "$f" .toml)
            end
        end
    end

    # dedupe, sort
    set themes (printf '%s\n' $themes | sort -u)

    if test (count $themes) -eq 0
        echo "theme: no themes found" >&2
        return 1
    end

    set -l selection (printf '%s\n' $themes | fzf \
        --prompt="theme> " \
        --height=60% \
        --reverse \
        --ansi \
        --preview "python3 $apply --preview {}" \
        --preview-window="right:60%" \
        --bind "esc:abort" \
        --header="enter: keep · esc: restore [$original]" \
        --query "$original")

    if test -z "$selection"
        # cancelled — restore original
        python3 "$apply" "$original"
        echo "theme: restored $original"
    else
        # confirmed — preview already applied it, but call explicitly for clarity
        python3 "$apply" "$selection"
        echo "theme: $selection"
    end
end
