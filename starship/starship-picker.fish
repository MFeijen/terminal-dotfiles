# `starship-style` — pick a starship layout variant.
# Bare form opens fzf with live-render preview; positional swaps directly.

set -g __starship_style_variants_dir (dirname (status -f))/variants

function starship-style --description "Pick a starship layout variant"
    set -l variants_dir $__starship_style_variants_dir
    set -l active_link $HOME/.config/starship.toml

    if not test -d "$variants_dir"
        echo "starship-style: $variants_dir not found" >&2
        return 1
    end

    set -l variants
    for f in $variants_dir/*.toml
        test -f "$f"; or continue
        set -a variants (basename "$f" .toml)
    end
    set variants (printf '%s\n' $variants | sort -u)

    if test (count $variants) -eq 0
        echo "starship-style: no variants in $variants_dir" >&2
        return 1
    end

    # positional: swap directly, no picker
    if test (count $argv) -gt 0
        set -l target $argv[1]
        set -l target_file "$variants_dir/$target.toml"
        if not test -f "$target_file"
            echo "starship-style: no variant '$target'" >&2
            echo "available: $variants" >&2
            return 1
        end
        ln -sfn "$target_file" "$active_link"
        echo "starship-style: $target"
        return 0
    end

    # no args: fzf picker with live-render preview
    set -l original
    if test -L "$active_link"
        set original (basename (readlink "$active_link") .toml)
    end
    test -z "$original"; and set original pill

    set -l selection (printf '%s\n' $variants | fzf \
        --prompt="starship> " \
        --height=60% \
        --reverse \
        --ansi \
        --preview "STARSHIP_CONFIG=$variants_dir/{}.toml starship prompt 2>/dev/null" \
        --preview-window="right:60%" \
        --bind "esc:abort" \
        --header="enter: apply · esc: restore [$original]" \
        --query "$original")

    if test -z "$selection"
        ln -sfn "$variants_dir/$original.toml" "$active_link"
        echo "starship-style: restored $original"
    else
        ln -sfn "$variants_dir/$selection.toml" "$active_link"
        echo "starship-style: $selection"
    end
end

complete -c starship-style -f -a "(for f in $__starship_style_variants_dir/*.toml; basename \$f .toml; end)"
