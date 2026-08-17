# Upstream requirements

Omacoach can prototype its core behavior with current Omarchy and Hyprland,
but three upstream contracts would remove approximation and local forks.

## 1. Hyprland: binding-invoked event

`input.keyboard.key` fires before keybinding resolution. It cannot prove that a
binding matched its submap and device constraints, survived inhibitors, or ran
its dispatcher.

Hyprland should expose a non-cancellable Lua event after actual invocation:

```text
keybinds.invoked(bind, phase, result)
```

The event should:

- fire only after an eligible binding callback runs;
- distinguish `press`, `release`, and compositor-generated `repeat`;
- expose stable binding metadata including display key, key/keycode, modifier
  mask, description, submap, flags, handler, and device constraints;
- report dispatcher success without claiming an asynchronous application later
  started successfully;
- omit inhibited, shadowed, incomplete, and merely scheduled candidates.

This belongs in `hyprwm/Hyprland`. Omacoach would retain raw keyboard events
only for latency-sensitive overlay behavior and use this event for exact
activation statistics.

## 2. Omarchy: app selected after search

The current experiment clones `omarchy.menu` and adds a hook immediately before
the app launch request. It tests whether `filterText.trim()` is non-empty and
sends only the selected desktop-entry ID and display name to Omacoach. It does
not send or retain the query.

The production contract should be a shell-level semantic signal, not an
Omacoach-specific command in the menu:

```qml
signal appSelectedAfterSearch(var event)
```

The event should fire for keyboard or pointer commitment of an app row after a
non-empty search, before clearing menu state. It should not fire for cancelled
searches, empty-filter selections, dmenu modes, static actions, or navigation.
The shell may include the trimmed query for other consumers, but Omacoach does
not need to consume or persist it.

This belongs in `basecamp/omarchy` on the Quattro shell. The validated local
patch is `experiments/menu-search-event.patch`.

## 3. Hyprland/Quickshell: pointer shortcut inhibition

Hyprland resolves global `SUPER+mouse` move/resize bindings before forwarding a
pointer button to the focused Wayland surface. A QML input mask controls where
the surface can receive pointer input, but cannot override compositor binding
resolution. `pass_mouse_when_bound` is insufficient because it still executes
the move/resize action.

Omacoach therefore requires users to hover the measurement pane, release
`SUPER` to pin it, and only then click. If direct interaction while holding
`SUPER` is desired upstream, it needs a pointer-shortcut inhibitor that:

- applies while pointer focus is inside a surface input region;
- does not require or steal keyboard focus;
- suppresses pointer-button binding resolution before dispatch;
- consistently routes the matching press and release to the surface;
- reports whether inhibition was granted and active.

That would require protocol design in `hyprwm/hyprland-protocols`, compositor
support in `hyprwm/Hyprland`, and a QML wrapper in Quickshell. It should remain
separate from the binding-invoked and Omarchy menu-event pull requests.

## Priority

1. Omarchy app-selection signal: smallest change and removes the local menu fork.
2. Hyprland binding-invoked event: upgrades approximate attempts to activations.
3. Pointer shortcut inhibition: optional; the release-to-interact UX works now.

## References

- [Hyprland raw keyboard event](https://github.com/hyprwm/Hyprland/blob/5751911091d2bbcd580597d489a1ec0b9dd542bd/src/config/lua/LuaEventHandler.cpp#L181-L187)
- [Hyprland bind resolution and invocation](https://github.com/hyprwm/Hyprland/blob/5751911091d2bbcd580597d489a1ec0b9dd542bd/src/keybinds/Manager.cpp#L445-L619)
- [Hyprland mouse processing](https://github.com/hyprwm/Hyprland/blob/5751911091d2bbcd580597d489a1ec0b9dd542bd/src/managers/input/InputManager.cpp#L869-L940)
- [Omarchy app activation flow](https://github.com/basecamp/omarchy/blob/262d6f0681ce27abbb10587b794f22d58bdbcec8/shell/plugins/menu/Menu.qml#L759-L786)
- [Omarchy `SUPER+mouse` bindings](https://github.com/basecamp/omarchy/blob/262d6f0681ce27abbb10587b794f22d58bdbcec8/default/hypr/bindings/tiling.lua#L67-L71)
- [Wayland keyboard shortcut inhibition](https://wayland.app/protocols/keyboard-shortcuts-inhibit-unstable-v1)
