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
    read -p "Continue anyway? (y/N) " -n 1 -r
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
    "hyprshot" "hyprpicker" "hyprsunset"
    # Bar, notifications, OSD, wallpaper
    "waybar" "swaync" "swayosd" "awww" "waypaper"
    # Launchers and menus
    "rofi" "rofi-emoji" "wofi" "wlogout"
    # Terminals, shell, editors
    "ghostty" "kitty" "fish" "starship" "neovim" "zed" "kwrite"
    # File managers and system tools
    "thunar" "yazi" "btop" "bottom" "resources" "fastfetch"
    # Clipboard, screenshots, media
    "cliphist" "wl-clipboard" "flameshot" "playerctl"
    # Theming
    "python-pywal" "qt5ct" "qt6ct" "nwg-look"
    # Applets and controls
    "brightnessctl" "pavucontrol" "blueman" "nm-connection-editor"
    "gnome-calculator"
    # Script dependencies
    "jq" "ffmpeg" "inotify-tools" "zoxide" "atuin" "aichat"
    # Fonts (configs default to FiraCode Nerd Font)
    "ttf-firacode-nerd" "ttf-cascadia-mono-nerd" "ttf-nerd-fonts-symbols"
    "noto-fonts" "noto-fonts-emoji"
)

AUR_PACKAGES=(
    "zen-browser-bin"
    "vesktop"
    "waybar-weather"
    "aylurs-gtk-shell"   # ags (settings panel)
    "libastal-meta"      # astal CLI used by keybinds/waybar
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
    read -p "Install missing packages? (y/N) " -n 1 -r
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
        read -p "Install missing AUR packages? (y/N) " -n 1 -r
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
# Backup existing configs
# ------------------------------------------------------------------
if [ "$NO_BACKUP" = false ] && [ "$DOTFILES_DIR" != "$CONFIG_DIR" ]; then
    info "Creating backup of existing configs..."
    execute mkdir -p "$BACKUP_DIR"

    CONFIGS_TO_BACKUP=(
        "hypr" "waybar" "swaync" "rofi" "wofi" "wlogout" "mako"
        "fish" "ghostty" "kitty" "nvim" "btop" "gtk-3.0" "gtk-4.0"
        "qt5ct" "qt6ct" "options" "scripts" "mimeapps.list" "starship.toml"
    )

    for config in "${CONFIGS_TO_BACKUP[@]}"; do
        if [ -e "$CONFIG_DIR/$config" ]; then
            execute cp -r "$CONFIG_DIR/$config" "$BACKUP_DIR/"
            success "Backed up: $config"
        fi
    done

    info "Backup saved to: $BACKUP_DIR"
fi

# ------------------------------------------------------------------
# Deploy dotfiles into ~/.config
# ------------------------------------------------------------------
if [ "$DOTFILES_DIR" != "$CONFIG_DIR" ]; then
    info "Deploying dotfiles to $CONFIG_DIR..."
    execute mkdir -p "$CONFIG_DIR"
    while IFS= read -r -d '' item; do
        name=$(basename "$item")
        case "$name" in
            .git|.github|.claude) continue ;;
        esac
        execute cp -a "$item" "$CONFIG_DIR/"
    done < <(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -print0)
    success "Dotfiles deployed"
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

# Pywal symlink for Hyprland colors
info "Setting up pywal integration..."
execute ln -sfn "$HOME/.cache/wal/colors-hyprland.conf" "$CONFIG_DIR/hypr/config/colors.conf"
if [ -f "$HOME/.cache/wal/colors-hyprland.conf" ]; then
    success "Pywal symlink created"
else
    warning "Pywal colors not generated yet - they will appear after the first 'wal -i' run"
fi

# Current-wallpaper symlink + rofi background
if [ -n "$FIRST_WALLPAPER" ]; then
    execute ln -sfn "$FIRST_WALLPAPER" "$CONFIG_DIR/options/wallpaper"
    if [ "$DRY_RUN" = false ]; then
        echo "* { wallpaper: url(\"$FIRST_WALLPAPER\", width); }" > "$CONFIG_DIR/rofi/options/wallpaper.rasi"
    else
        echo "[DRY RUN] write $CONFIG_DIR/rofi/options/wallpaper.rasi"
    fi
    success "Wallpaper option set"
fi

# ------------------------------------------------------------------
# Final wiring
# ------------------------------------------------------------------
info "Making scripts executable..."
if [ "$DRY_RUN" = false ]; then
    find "$CONFIG_DIR/scripts" "$CONFIG_DIR/rofi" "$CONFIG_DIR/swaync" \
         "$CONFIG_DIR/waybar" "$CONFIG_DIR/sddm" "$CONFIG_DIR/ghostty" \
         "$CONFIG_DIR/mako" "$CONFIG_DIR/Thunar" \
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
        read -p "Set fish as default shell? (y/N) " -n 1 -r
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
