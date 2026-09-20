#!/bin/bash
#
# Dotfiles Installation Script
# Self-contained deployment for fresh Hyprland installations on CachyOS/Arch
#
# Usage: ./install.sh [options]
#   --dry-run    Show what would be done without making changes
#   --no-backup  Skip creating backups of existing configs
#   --help       Show this help message
#

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
NO_BACKUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --no-backup) NO_BACKUP=true; shift ;;
        --help)
            head -n 10 "$0" | tail -n 6
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Helper functions
info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

execute() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        warning "$1 not found - some features may not work"
        return 1
    fi
    return 0
}

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Hyprland Dotfiles Installation                          ║
║   CachyOS/Arch Edition                                    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running on Arch-based system
if [ ! -f /etc/arch-release ]; then
    warning "This script is designed for Arch-based systems"
    read -p "Continue anyway? (y/N) " -n 1 -r || true
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# ------------------------------------------------------------------
# Packages
# ------------------------------------------------------------------
# Everything the configs, keybinds, and scripts reference.
# Availability is checked at runtime: packages found in the configured
# pacman repos are installed with pacman, the rest go to the AUR helper.
PACKAGES=(
    # Hyprland ecosystem
    "hyprland" "hyprlock" "hypridle" "hyprpolkitagent"
    "hyprshot" "hyprpicker" "hyprsunset" "swappy"
    # Bar, notifications, OSD, wallpaper
    "waybar" "swaync" "swayosd" "awww" "waypaper" "quickshell"
    # Launchers and menus
    "rofi" "rofi-emoji"
    # Terminals, shell, editors
    "ghostty" "fish" "starship" "neovim" "zed" "kwrite"
    # File managers and system tools
    "thunar" "yazi" "btop" "bottom" "resources" "fastfetch" "cava"
    # checkupdates, for the waybar updates module
    "pacman-contrib"
    # Clipboard, screenshots, media
    "cliphist" "wl-clipboard" "playerctl"
    # Theming
    "python-pywal" "qt5ct" "qt6ct" "nwg-look"
    # Applets and controls
    "pavucontrol" "blueman" "nm-connection-editor"
    "gnome-calculator"
    # Script dependencies
    "jq" "ffmpeg" "inotify-tools" "zoxide" "atuin" "aichat" "shellcheck"
    # Isolated deployment/hook fixtures and panel persistence tests
    "python" "nodejs" "gjs"
    # Fonts (configs default to FiraCode Nerd Font)
    "ttf-firacode-nerd" "ttf-cascadia-mono-nerd" "ttf-nerd-fonts-symbols"
    "noto-fonts" "noto-fonts-emoji"
)

AUR_PACKAGES=(
    "zen-browser-bin"
    "vesktop"
    "waybar-weather"
)

info "Checking system dependencies..."
MISSING_PACMAN=()
MISSING_AUR=("${AUR_PACKAGES[@]}")
for pkg in "${PACKAGES[@]}"; do
    if pacman -Qq "$pkg" &> /dev/null; then
        continue
    fi
    if pacman -Si "$pkg" &> /dev/null; then
        MISSING_PACMAN+=("$pkg")
    else
        # Not in any configured repo - try the AUR instead
        MISSING_AUR+=("$pkg")
    fi
done

if [ ${#MISSING_PACMAN[@]} -gt 0 ]; then
    warning "Missing packages: ${MISSING_PACMAN[*]}"
    read -p "Install missing packages? (y/N) " -n 1 -r || true
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        execute sudo pacman -S --needed "${MISSING_PACMAN[@]}"
        success "Packages installed"
    else
        warning "Skipping package installation - some features may not work"
    fi
fi

info "Checking AUR packages..."
STILL_MISSING_AUR=()
for pkg in "${MISSING_AUR[@]}"; do
    # Accept either the package itself or its non -bin/-git variant
    if ! pacman -Qq "$pkg" &> /dev/null \
        && ! pacman -Qq "${pkg%-bin}" &> /dev/null \
        && ! pacman -Qq "${pkg}-git" &> /dev/null; then
        STILL_MISSING_AUR+=("$pkg")
    fi
done

if [ ${#STILL_MISSING_AUR[@]} -gt 0 ]; then
    warning "Missing AUR packages: ${STILL_MISSING_AUR[*]}"
    if command -v paru &> /dev/null || command -v yay &> /dev/null; then
        read -p "Install missing AUR packages? (y/N) " -n 1 -r || true
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            AUR_HELPER=$(command -v paru || command -v yay)
            execute "$AUR_HELPER" -S --needed "${STILL_MISSING_AUR[@]}"
            success "AUR packages installed"
        fi
    else
        warning "No AUR helper found (paru/yay). Install manually: ${STILL_MISSING_AUR[*]}"
    fi
fi

# ------------------------------------------------------------------
# Back up and deploy the same tracked-file plan
# ------------------------------------------------------------------
if [ "$DOTFILES_DIR" != "$CONFIG_DIR" ]; then
    info "Deploying tracked dotfiles to $CONFIG_DIR..."
    # shellcheck source=scripts/lib/deploy.sh
    source "$DOTFILES_DIR/scripts/lib/deploy.sh"
    deploy_dotfiles "$DOTFILES_DIR" "$CONFIG_DIR" "$BACKUP_DIR" "$DRY_RUN" "$NO_BACKUP"
    success "Tracked dotfiles deployed"
    [ "$NO_BACKUP" = true ] || info "Backup saved to: $BACKUP_DIR"
else
    info "Repo already lives at $CONFIG_DIR - no deployment needed"
fi

# ------------------------------------------------------------------
# Directories and wallpapers
# ------------------------------------------------------------------
info "Setting up directory structure..."
execute mkdir -p "$HOME/.cache/wal"
execute mkdir -p "$HOME/.cache/awww"
execute mkdir -p "$HOME/Pictures/Wallpapers"
execute mkdir -p "$HOME/Pictures/Screenshots"
success "Directories created"

info "Copying wallpapers..."
if [ -d "$CONFIG_DIR/wallpapers" ]; then
    execute cp -n "$CONFIG_DIR/wallpapers/"* "$HOME/Pictures/Wallpapers/" 2>/dev/null || true
    success "Wallpapers copied"
fi

# ------------------------------------------------------------------
# Pywal initialization
# ------------------------------------------------------------------
info "Initializing pywal color scheme..."
FIRST_WALLPAPER="$CONFIG_DIR/wallpapers/wall1.jpg"
if [ ! -f "$FIRST_WALLPAPER" ]; then
    FIRST_WALLPAPER=$(find "$HOME/Pictures/Wallpapers" -type f \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | head -n 1)
fi
if [ -n "$FIRST_WALLPAPER" ] && check_dependency "wal"; then
    execute wal -i "$FIRST_WALLPAPER" -n -q
    success "Pywal initialized"
else
    warning "Could not initialize pywal - run 'wal -i /path/to/wallpaper' manually later"
fi

# Pywal symlinks for Hyprland (Lua) and hyprlock (Hyprlang) colors.
# The target is relative on purpose. An absolute one bakes this machine's home
# path into a tracked file, which doctor.sh reports as a portability warning
# and which breaks the moment the repo is checked out under a different user.
info "Setting up pywal integration..."
execute ln -sfn "../../../.cache/wal/colors-hyprland.conf" "$CONFIG_DIR/hypr/config/colors.conf"
execute ln -sfn "../../../.cache/wal/colors-hyprland.lua" "$CONFIG_DIR/hypr/config/colors.lua"
if [ -f "$HOME/.cache/wal/colors-hyprland.conf" ] \
    && [ -f "$HOME/.cache/wal/colors-hyprland.lua" ]; then
    success "Pywal symlinks created"
else
    warning "Pywal colors not generated yet - the theming pass below will create fallbacks"
fi

# Current-wallpaper state + generated configs (cache-backed, symlinked from the repo)
if [ -n "$FIRST_WALLPAPER" ]; then
    execute ln -sfn "$FIRST_WALLPAPER" "$HOME/.cache/current_wallpaper"
    if [ "$DRY_RUN" = false ]; then
        echo "* { wallpaper: url(\"$FIRST_WALLPAPER\", width); }" > "$HOME/.cache/wal/rofi-wallpaper.rasi"
    else
        echo "[DRY RUN] write $HOME/.cache/wal/rofi-wallpaper.rasi"
    fi
    success "Wallpaper state initialized"
fi

# Render every themed component's colors (cache-backed, reached from tracked
# configs by symlink or include). The driver globs for the per-component
# scripts, and each one produces its output even when pywal has not run, so
# no component needs a fallback here.
if ! execute "$CONFIG_DIR/scripts/theming/apply-wal.sh"; then
    warning "Some theme components failed; run scripts/theming/apply-wal.sh to retry"
fi

# Seed waypaper config
if [ ! -f "$HOME/.cache/waypaper-config.ini" ]; then
    execute cp "$CONFIG_DIR/waypaper/config.ini.template" "$HOME/.cache/waypaper-config.ini"
fi

# ------------------------------------------------------------------
# Git hooks
# ------------------------------------------------------------------
# Tracked hooks live in scripts/hooks and are activated by pointing git at
# them, so they update with a pull instead of rotting in .git/hooks.
if [ -d "$CONFIG_DIR/.git" ]; then
    info "Activating tracked git hooks..."
    execute git -C "$CONFIG_DIR" config core.hooksPath scripts/hooks
    success "Pre-commit gate active (shellcheck + test suites + ags bundle)"
fi

# ------------------------------------------------------------------
# Final wiring
# ------------------------------------------------------------------
info "Making scripts executable..."
if [ "$DRY_RUN" = false ]; then
    find "$CONFIG_DIR/scripts" "$CONFIG_DIR/rofi" "$CONFIG_DIR/swaync" \
         "$CONFIG_DIR/waybar" "$CONFIG_DIR/sddm" "$CONFIG_DIR/ghostty" \
         "$CONFIG_DIR/Thunar" \
         -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
fi
success "Scripts are executable"

# API keys template
if [ ! -f "$CONFIG_DIR/.env" ] && [ -f "$CONFIG_DIR/.env.example" ]; then
    execute cp "$CONFIG_DIR/.env.example" "$CONFIG_DIR/.env"
    success "Created $CONFIG_DIR/.env from template (add your API keys there)"
fi

# Set fish as default shell
if check_dependency "fish"; then
    if [ "$SHELL" != "$(which fish)" ]; then
        read -p "Set fish as default shell? (y/N) " -n 1 -r || true
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            execute chsh -s "$(which fish)"
            success "Fish set as default shell (logout to apply)"
        fi
    else
        success "Fish is already default shell"
    fi
fi

# Print summary
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║   Installation Complete!                                  ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Next steps:"
echo "  1. Log out and log back in (or reboot)"
echo "  2. Select Hyprland from your login manager"
echo "  3. Press SUPER+ENTER to open terminal (ghostty)"
echo "  4. Press SUPER+CTRL+W to pick a wallpaper (colors follow automatically)"
echo ""
info "Key bindings:"
echo "  SUPER+ENTER      - Terminal"
echo "  SUPER+Q          - Close window"
echo "  SUPER+SPACE      - Application launcher"
echo "  SUPER+L          - Lock screen"
echo "  SUPER+SHIFT+L    - Power menu"
echo "  SUPER+H          - Keybinds cheatsheet"
echo ""
if [ "$NO_BACKUP" = false ] && [ "$DOTFILES_DIR" != "$CONFIG_DIR" ]; then
    info "Backup location: $BACKUP_DIR"
fi
echo ""
success "Enjoy your new Hyprland setup!"
