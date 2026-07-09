# `starship-style` — pick a starship layout variant.
# Bare form opens fzf with live-render preview; positional swaps directly.

set -g __starship_style_variants_dir (dirname (status -f))/variants
set -g __starship_style_fixture $HOME/.cache/starship-preview

# Build a fake project (git repo, package.json, Cargo.toml, dirty file) so that
# starship's git / language modules light up in the preview. Cached — first
# picker invocation pays the cost, subsequent ones are free.
function __starship_style_ensure_fixture
    set -l fx $__starship_style_fixture
    if test -d $fx/.git
        return 0
    end
    if not type -q git
        return 1
    end
    mkdir -p $fx
    git -C $fx init -q -b feature/pill-preview 2>/dev/null; or return 1
    echo '{"name":"awesome","version":"2.3.1"}' > $fx/package.json
    printf '[package]\nname = "awesome"\nversion = "0.4.2"\n' > $fx/Cargo.toml
    echo 'baseline' > $fx/README.md
    git -C $fx -c user.email=preview@local -c user.name=preview add -A 2>/dev/null
    git -C $fx -c user.email=preview@local -c user.name=preview commit -q -m init 2>/dev/null
    # leave README dirty so git_status has something to render
    echo 'edited' >> $fx/README.md
end

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

    # Build preview fixture; if it fails, preview still works (just less context).
    __starship_style_ensure_fixture
    set -l fx $__starship_style_fixture
    set -l fake_path "$HOME/dev/awesome-project"

    set -l preview_cmd "STARSHIP_CONFIG=$variants_dir/{}.toml starship prompt --path '$fx' --logical-path '$fake_path' --cmd-duration 1234 --status 0 --jobs 0 2>/dev/null"

    set -l selection (printf '%s\n' $variants | fzf \
        --prompt="starship> " \
        --height=60% \
        --reverse \
        --ansi \
        --preview "$preview_cmd" \
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
