source /usr/share/cachyos-fish-config/cachyos-config.fish

# Load environment variables from .env file
if test -f ~/.config/.env
    export (cat ~/.config/.env | grep -v '^#' | grep -v '^$' | xargs)
end

# Load aliases
source ~/.config/fish/aliases.fish

zoxide init fish | source

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end
