# CachyOS defaults (skipped on vanilla Arch)
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

# Load environment variables from .env file
if test -f ~/.config/.env
    export (cat ~/.config/.env | grep -v '^#' | grep -v '^$' | xargs)
end

# Load aliases
source ~/.config/fish/aliases.fish

if type -q zoxide
    zoxide init fish | source
end

# Starship prompt. Without this the CachyOS vendor fish_prompt stays in charge
# and starship.toml is never read. Must come after the cachyos-config source
# above, since that is what defines the prompt being replaced.
# starship.toml is a symlink to the pywal-rendered copy in ~/.cache, so the
# prompt follows the wallpaper — see starship/apply_wal_colors.sh.
if type -q starship
    starship init fish | source
end

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
