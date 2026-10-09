# Hyprland Dotfiles

A complete, ready-to-use Hyprland desktop for Arch Linux and CachyOS. Its
colors follow your wallpaper: change the wallpaper and the bar, launcher,
notifications, terminal and lock screen all re-theme themselves.

![Arch](https://img.shields.io/badge/Arch_Linux-CachyOS-1793D1)
![Hyprland](https://img.shields.io/badge/Hyprland-0.55+-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## Install

On a fresh Arch Linux or CachyOS system, logged in as your normal user:

```bash
sudo pacman -S --needed git
git clone https://github.com/pwnjack/.config.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installer asks before installing packages and backs up any file it
replaces; `./install.sh --dry-run` previews everything first. It also starts an
SSH agent, so your key's passphrase is asked once per login. CachyOS ships the
`paru` AUR helper it uses; on plain Arch, install `paru` or `yay` first.

When it finishes, log out and choose **Hyprland** at your login screen — or, if
you have no login manager, type `start-hyprland` in the console.

## First steps

| Keys | Does |
|---|---|
| `Super + Enter` | Terminal |
| `Super + Space` | App launcher |
| `Super + Ctrl + W` | Pick a wallpaper — colors follow |
| `Super + I` | Settings |
| `Super + H` | Every shortcut, searchable |

## Screenshots

Each wallpaper re-themes the whole desktop: bar, borders, terminal and overlays.

| | |
|---|---|
| ![Cosy retreat](screenshots/cosy-1.webp) | ![Cosy retreat, terminals](screenshots/cosy-2.webp) |
| ![Northern lights](screenshots/aurora-1.webp) | ![Northern lights, terminals](screenshots/aurora-2.webp) |
| ![Synthwave](screenshots/synthwave-1.webp) | ![Synthwave, terminals](screenshots/synthwave-2.webp) |

| Settings (`Super + I`) | Keybindings (`Super + H`) |
|---|---|
| ![Settings panel](screenshots/settings.webp) | ![Keybindings overlay](screenshots/keybinds.webp) |
| **Wallpaper carousel (`Super + Ctrl + W`)** | **Capture bar (`Super + Shift + S`)** |
| ![Wallpaper carousel](screenshots/carousel.webp) | ![Capture bar](screenshots/capture.webp) |

## More

- [Guide](docs/guide.md) — customization, troubleshooting, maintenance
- [All keybindings](docs/keybindings.md)

## License

[MIT](LICENSE)
