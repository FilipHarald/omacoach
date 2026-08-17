# Omacoach

Omacoach is an experimental Omarchy Quattro plugin that reveals available
keyboard shortcuts while `SUPER` is held. Adding `SHIFT`, `CTRL`, or `ALT`
filters the overlay to that exact modifier combination. The overlay never
takes keyboard focus and disappears before Hyprland executes an action key.

## Current prototype

- Reads effective, described bindings from `omarchy-menu-keybindings --print`.
- Shows only keyboard bindings containing `SUPER`.
- Waits 180 ms before appearing, avoiding flashes for shortcuts already in
  muscle memory.
- Runs as a click-through, keyboard-focus-free layer-shell overlay.
- Supports live modifier filtering and reloads after Hyprland config changes.

Mouse, wheel, `XF86`, `code:`, submap, and native multi-key chord bindings are
not promised by this prototype. Hyprland does not expose a post-dispatch event,
so no usage measurement is implemented yet.

## Development install

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/omacoach
omarchy-shell shell rescanPlugins
omarchy plugin enable omacoach
./bin/install-hook
```

The observer installer makes a timestamped backup of
`~/.config/hypr/bindings.lua`, adds one marked loader block, reloads Hyprland,
and rolls back if validation fails.

Remove the observer before removing the plugin:

```bash
./bin/uninstall-hook
omarchy plugin disable omacoach
```

Run the checks with `./scripts/check`. Preview the UI without holding a key:

```bash
omarchy-shell omacoach preview SUPER "$(hyprctl activeworkspace -j | jq -r .monitor)"
omarchy-shell omacoach hide
```

## Attribution

The passive Hyprland observer and contextual overlay architecture were informed
by [NextKey](https://github.com/russellmorton/next-key), Copyright (c) 2026
Russell Morton, available under the MIT License. See
`THIRD_PARTY_NOTICES.md`.
