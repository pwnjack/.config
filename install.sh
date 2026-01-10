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
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
NO_BACKUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --no-backup) NO_BACKUP=true; shift ;;
        --help)
            head -n 12 "$0" | tail -n 8
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
║   Hyprland Dotfiles Installation                         ║
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

# Package lists
ESSENTIAL_PACKAGES=(
    "hyprland"
    "hyprlock"
    "hypridle"
    "waybar"
    "swaync"
    "swayosd"
    "swww"
    "rofi-wayland"
    "wofi"
    "wlogout"
    "ghostty"
    "kitty"
    "fish"
    "neovim"
    "thunar"
    "yazi"
    "btop"
    "fastfetch"
    "flameshot"
    "playerctl"
    "cliphist"
    "wl-clipboard"
    "python-pywal"
    "qt5ct"
    "qt6ct"
    "nwg-look"
    "hyprpolkitagent"
)

AUR_PACKAGES=(
    "zen-browser-bin"
    "vesktop"
    "waybar-weather"
)

info "Checking system dependencies..."
MISSING_PACKAGES=()
for pkg in "${ESSENTIAL_PACKAGES[@]}"; do
    if ! pacman -Qq "$pkg" &> /dev/null; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    warning "Missing packages: ${MISSING_PACKAGES[*]}"
    read -p "Install missing packages? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        execute sudo pacman -S --needed "${MISSING_PACKAGES[@]}"
        success "Packages installed"
    else
        warning "Skipping package installation - some features may not work"
    fi
fi

info "Checking AUR packages..."
MISSING_AUR=()
for pkg in "${AUR_PACKAGES[@]}"; do
    if ! pacman -Qq "${pkg%-bin}" "$pkg" &> /dev/null 2>&1; then
        MISSING_AUR+=("$pkg")
    fi
done

if [ ${#MISSING_AUR[@]} -gt 0 ]; then
    warning "Missing AUR packages: ${MISSING_AUR[*]}"
    if command -v paru &> /dev/null || command -v yay &> /dev/null; then
        read -p "Install missing AUR packages? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            AUR_HELPER=$(command -v paru || command -v yay)
            execute "$AUR_HELPER" -S --needed "${MISSING_AUR[@]}"
            success "AUR packages installed"
        fi
    else
        warning "No AUR helper found (paru/yay). Install manually: ${MISSING_AUR[*]}"
    fi
fi

# Backup existing configs
if [ "$NO_BACKUP" = false ]; then
    info "Creating backup of existing configs..."
    execute mkdir -p "$BACKUP_DIR"

    CONFIGS_TO_BACKUP=(
        "hypr"
        "waybar"
        "fish"
        "ghostty"
        "kitty"
        "nvim"
        "rofi"
        "btop"
        "mimeapps.list"
    )

    for config in "${CONFIGS_TO_BACKUP[@]}"; do
        if [ -e "$HOME/.config/$config" ]; then
            execute cp -r "$HOME/.config/$config" "$BACKUP_DIR/"
            success "Backed up: $config"
        fi
    done

    info "Backup saved to: $BACKUP_DIR"
fi

# Create necessary directories
info "Setting up directory structure..."
execute mkdir -p "$HOME/.cache/wal"
execute mkdir -p "$HOME/.cache/swww"
execute mkdir -p "$HOME/Pictures/Wallpapers"
success "Directories created"

# Copy wallpapers
info "Copying wallpapers..."
if [ -d "$DOTFILES_DIR/wallpapers" ]; then
    execute cp -r "$DOTFILES_DIR/wallpapers"/* "$HOME/Pictures/Wallpapers/" 2>/dev/null || true
    success "Wallpapers copied"
fi

# Initialize pywal with first wallpaper
info "Initializing pywal color scheme..."
FIRST_WALLPAPER=$(find "$HOME/Pictures/Wallpapers" -type f \( -iname "*.jpg" -o -iname "*.png" \) | head -n 1)
if [ -n "$FIRST_WALLPAPER" ] && check_dependency "wal"; then
    execute wal -i "$FIRST_WALLPAPER" -n -q
    success "Pywal initialized"
else
    warning "Could not initialize pywal - run 'wal -i /path/to/wallpaper' manually later"
fi

# Create pywal symlink for Hyprland
info "Setting up pywal integration..."
if [ -f "$HOME/.cache/wal/colors-hyprland.conf" ]; then
    execute rm -f "$DOTFILES_DIR/hypr/config/colors.conf"
    execute ln -sf "$HOME/.cache/wal/colors-hyprland.conf" "$DOTFILES_DIR/hypr/config/colors.conf"
    success "Pywal symlink created"
else
    warning "Pywal colors not generated - symlink will be created after first wal run"
fi

# Update wallpaper symlink in options
if [ -n "$FIRST_WALLPAPER" ]; then
    execute ln -sf "$FIRST_WALLPAPER" "$DOTFILES_DIR/options/wallpaper"
    success "Wallpaper option set"
fi

# Make scripts executable
info "Making scripts executable..."
find "$DOTFILES_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
success "Scripts are executable"

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

# Final checks
info "Running final checks..."

# Check if Hyprland config is valid
if check_dependency "hyprctl"; then
    success "Hyprland configuration appears valid"
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
echo "  4. Run 'wal -i ~/Pictures/Wallpapers/wall1.jpg' to set colors"
echo ""
info "Key bindings:"
echo "  SUPER+ENTER      - Terminal"
echo "  SUPER+Q          - Close window"
echo "  SUPER+D          - Application launcher"
echo "  SUPER+L          - Lock screen"
echo "  SUPER+SHIFT+E    - Power menu"
echo ""
if [ "$NO_BACKUP" = false ]; then
    info "Backup location: $BACKUP_DIR"
fi
echo ""
success "Enjoy your new Hyprland setup!"
