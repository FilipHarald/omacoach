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
- Collapses numeric workspace and bar-panel families into presentation-only
  `[nbr]` rows while retaining independent underlying bindings and counts.
- Resolves terminal key presses through the active XKB layout and stores only
  aggregate counts for chords that uniquely match the displayed inventory.
- Labels those counts as attempted shortcuts, not confirmed invocations.

Mouse, wheel, `XF86`, `code:`, submap, and native multi-key chord bindings are
not promised by this prototype. Hyprland does not expose a post-dispatch event,
so they are excluded from attempted-shortcut measurement.

Measurement is local and enabled when the plugin is enabled. It can be paused,
inspected, or reset without disabling shortcut hints. The overlay measurement
pane exposes the same toggle and delete controls; hover it before releasing
`SUPER` for passive hints, or press `SUPER+CTRL+K` to toggle a pinned,
interactive popover. The hold overlay stays fully click-through because QML
cannot suppress Hyprland's compositor-level `SUPER+mouse` move/resize bindings:

```bash
omarchy-shell omacoach measurement off
omarchy-shell omacoach measurement on
omarchy-shell omacoach attempts
omarchy-shell omacoach resetAttempts
```

The plugin stores only a count per matched binding in
`${XDG_STATE_HOME:-~/.local/state}/omacoach/attempts.json`. It stores no raw
keys, unmatched chords, timestamps, focused applications, or event history.

The searched-app experiment can record a stable desktop-entry ID and display
name only when the user explicitly selects an app after a non-empty Omarchy
menu search. It does not receive or retain the search query:

```bash
omarchy-shell omacoach searchedApps
```

## Development install

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/omacoach
omarchy-shell shell rescanPlugins
omarchy plugin enable omacoach
./bin/install-hook
```

The observer installer makes a timestamped backup of
`~/.config/hypr/bindings.lua`, adds one marked loader block, reloads Hyprland,
adds a separate marked `SUPER+CTRL+K` panel binding, reloads Hyprland, and
rolls back if validation fails.

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
