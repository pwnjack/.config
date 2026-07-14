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

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
