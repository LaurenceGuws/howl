# Built-in theme families

Settings → Color schemes selects App palette and Terminal palette independently.
Use the arrows to cycle presets; Enter edits the exact saved id. Existing Howl,
Slate and High Contrast choices remain available. Explicit overrides survive a
preset change; each reset-overrides action clears only its own group.

Terminal presets set default foreground/background, cursor/under-cursor colours,
and ANSI entries 0–15. Entries 16–255 retain VT defaults. Application RGB cells
retain their specified colours; programs can still change/reset the palette.
These are colour palettes, not full upstream editor or Kitty configuration ports.

App palettes are Howl adaptations using explicit window, title, active, idle,
panel, border, text, muted and accent roles. They use subdued family surfaces to
keep a single foreground legible on active tabs. They are independent of terminal
selection and do not claim to be official upstream app themes.

## Presets and source pins

| Name | Saved id | Terminal source |
| --- | --- | --- |
| Catppuccin Latte | `catppuccin_latte` | [catppuccin/kitty · 4309831](https://github.com/catppuccin/kitty/blob/43098316202b84d6a71f71aaf8360f102f4d3f1a/themes/latte.conf) |
| Catppuccin Frappé | `catppuccin_frappe` | [catppuccin/kitty · 4309831](https://github.com/catppuccin/kitty/blob/43098316202b84d6a71f71aaf8360f102f4d3f1a/themes/frappe.conf) |
| Catppuccin Macchiato | `catppuccin_macchiato` | [catppuccin/kitty · 4309831](https://github.com/catppuccin/kitty/blob/43098316202b84d6a71f71aaf8360f102f4d3f1a/themes/macchiato.conf) |
| Catppuccin Mocha | `catppuccin_mocha` | [catppuccin/kitty · 4309831](https://github.com/catppuccin/kitty/blob/43098316202b84d6a71f71aaf8360f102f4d3f1a/themes/mocha.conf) |
| Dracula | `dracula` | [dracula/kitty · 87717a3](https://github.com/dracula/kitty/blob/87717a3f00e3dff0fc10c93f5ff535ea4092de70/dracula.conf) |
| Nord | `nord` | [nordtheme/alacritty · 9949642](https://github.com/nordtheme/alacritty/blob/9949642f3903e8fcb62bfc03f09410e3d78440c2/src/nord.yaml) |
| Gruvbox Dark | `gruvbox_dark` | [gruvbox-community/gruvbox-contrib · 5bfe85a](https://github.com/gruvbox-community/gruvbox-contrib/blob/5bfe85a961d144376f9f9460f2b2a85343a0f0b3/kitty/gruvbox-dark.conf) |
| Gruvbox Light | `gruvbox_light` | [gruvbox-community/gruvbox-contrib · 5bfe85a](https://github.com/gruvbox-community/gruvbox-contrib/blob/5bfe85a961d144376f9f9460f2b2a85343a0f0b3/kitty/gruvbox-light.conf) |
| Solarized Dark | `solarized_dark` | [altercation/solarized · 62f656a](https://github.com/altercation/solarized/blob/62f656a02f93c5190a8753159e34b385588d5ff3/xresources/solarized) |
| Solarized Light | `solarized_light` | [altercation/solarized · 62f656a](https://github.com/altercation/solarized/blob/62f656a02f93c5190a8753159e34b385588d5ff3/xresources/solarized) |
| Tokyo Night | `tokyo_night` | [folke/tokyonight.nvim · cdc07ac](https://github.com/folke/tokyonight.nvim/blob/cdc07ac78467a233fd62c493de29a17e0cf2b2b6/extras/kitty/tokyonight_night.conf) |
| Tokyo Night Storm | `tokyo_night_storm` | [folke/tokyonight.nvim · cdc07ac](https://github.com/folke/tokyonight.nvim/blob/cdc07ac78467a233fd62c493de29a17e0cf2b2b6/extras/kitty/tokyonight_storm.conf) |
| Tokyo Night Moon | `tokyo_night_moon` | [folke/tokyonight.nvim · cdc07ac](https://github.com/folke/tokyonight.nvim/blob/cdc07ac78467a233fd62c493de29a17e0cf2b2b6/extras/kitty/tokyonight_moon.conf) |
| Tokyo Night Day | `tokyo_night_day` | [folke/tokyonight.nvim · cdc07ac](https://github.com/folke/tokyonight.nvim/blob/cdc07ac78467a233fd62c493de29a17e0cf2b2b6/extras/kitty/tokyonight_day.conf) |

Catppuccin colours are by Catppuccin; Dracula by Dracula Theme; Nord by Sven
Greb; Solarized by Ethan Schoonover; Tokyo Night by Folke Lemaitre; Gruvbox by
morhetz and the Gruvbox community. Solarized Light applies the source’s light
base substitutions to its stated ANSI mapping. Numeric palette values are
transcribed into static data; no upstream parser, shell script or runtime code is
included. Source licence notices follow in [THEME-LICENSES.md](THEME-LICENSES.md).

The palette catalogue performs no runtime file reads, network requests or theme
conversion. Defaults and accepted saved ids are explicit; unknown ids fail config
validation. Human labels are never persisted in place of ids.
