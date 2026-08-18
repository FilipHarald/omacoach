# Omacoach

> ⚠️ **Omarchy search must be modified for search-selection coaching to work.**
> Shortcut discovery and attempted-shortcut measurement work with stock Omarchy,
> but the Coach cannot observe menu selections unless the active Omarchy menu has
> the capability proposed in
> [basecamp/omarchy#7372](https://github.com/basecamp/omarchy/pull/7372).
> `experiments/menu-search-event.patch` remains an app-only fallback. Omacoach
> detects the proposed capability automatically. Follow
> [issue #17](https://github.com/FilipHarald/omacoach/issues/17) for status.

Omacoach helps you discover Omarchy with the keyboard and coaches you to become
better at using shortcuts. It is an experimental Omarchy Quattro plugin.

## Screenshots

Hold a configured modifier to open the passive, click-through shortcut overlay:

![Passive shortcut overlay](docs/screenshots/passive-overlay.webp)

Press `SUPER+CTRL+K` to open the permanent, interactive panel:

![Permanent coaching panel](docs/screenshots/permanent-panel.webp)

See [GUIDE_PRINTSCREENS.md](GUIDE_PRINTSCREENS.md) to reproduce or update these
images.

## Shortcut overlay

- Reads effective, described bindings from `omarchy-menu-keybindings --print`.
- Shows described keyboard bindings containing at least one supported modifier.
- Opens after a 180 ms hold, avoiding flashes for shortcuts already in muscle
  memory.
- Supports `SUPER`, `SHIFT`, `CTRL`, and `ALT` as independent passive triggers;
  all four are enabled by default and can be disabled separately.
- Filters immediately when modifiers are added or removed.
- Runs as a click-through, keyboard-focus-free layer-shell surface.
- Starts around 50% screen height and grows downward, shifting upward only when
  required to fit the output.
- Collapses numeric workspace and bar-panel families into presentation-only
  `[nbr]` rows while retaining independent underlying bindings and counts.
- Supports source-order, alphabetical, or measurement-count sorting with
  row-first or column-first grid flow.

Mouse, wheel, `XF86`, `code:`, submap, and native multi-key chord bindings are
not promised by this prototype. Hyprland does not expose a post-dispatch event,
so Omacoach records attempted shortcuts rather than confirmed invocations.

## Permanent panel

Press `SUPER+CTRL+K` to toggle the permanent panel. It starts 20% from the top
of the active output and grows downward so the close control and modifier row
stay in fixed positions.

The permanent panel:

- Closes with `Escape`, `SUPER+CTRL+K`, or its top-right close button.
- Uses the same live modifier filtering as the passive overlay.
- Shows Coach, Data, and Settings controls below the shortcut inventory.
- Opens the configured Omarchy agent with the current aggregate measurements
  and a prepared Coach discussion prompt.
- Lets you pause collection, delete local data, configure passive triggers,
  change sorting, and reset coaching decisions.
- Requests keyboard focus only while open; the passive overlay never does.

## Local measurement

Measurement is local and enabled when the plugin is enabled. Omacoach resolves
terminal key presses through the configured XKB keymap and stores aggregate
counts when a chord matches the parsed binding inventory. It stores no raw keys,
unmatched chords, timestamps, focused applications, or event history.

State is stored at:

```text
${XDG_STATE_HOME:-~/.local/state}/omacoach/attempts.json
```

Inspect or control measurement through the permanent panel or IPC:

```bash
omarchy-shell omacoach measurement off
omarchy-shell omacoach measurement on
omarchy-shell omacoach attempts
omarchy-shell omacoach resetAttempts
```

## Search-selection coaching

With the modified menu integration, Omacoach records a stable item ID, item kind,
label, and canonical menu path only when the user explicitly selects a static
action, app, menu, or link after a non-empty search. App events additionally
include the desktop-entry ID. It does not receive or retain the search query,
command, result rank, timestamp, or dmenu value. Dynamic provider rows and dmenu
selections are excluded. Inspect the aggregates with:

```bash
omarchy-shell omacoach menuSelections
omarchy-shell omacoach searchedApps
```

`searchedApps` is the app-only compatibility view. For app selections, the
matcher cross-checks desktop-entry identity, launcher-capable `o.bind`
definitions, and the effective binding list. It reports URL, command, Omarchy
launcher, and default-application evidence rather than trusting labels alone:

```bash
./scripts/match-searched-app-bindings
./scripts/match-searched-app-bindings --json
```

App Coach rows expose three actions:

- **Ignore** hides an app until **Reset coach decisions** is used.
- **Add keybind** prepends a commented, deduplicated app-specific draft to
  `~/.config/hypr/bindings.lua`, then opens the normal Omarchy config editor.
- **Show keybinding** opens the Omarchy keybinding selector narrowed to effective
  launcher bindings matched for that app.

Static action rows expose **Show keybinding** when their effective menu command
matches an effective `o.bind` definition, such as `Learn › Keybindings` and its
locally remapped `SUPER+U` binding. Static action, menu, and link rows expose
**Ignore**, but Omacoach does not suggest or generate new keybindings for those
item kinds.

Use **Talk about coach insights with agent** to open the configured Omarchy
agent with the prepared prompt in [`prompts/coach-insights.md`](prompts/coach-insights.md).
The prompt receives all current aggregate binding-attempt, searched-app, and
searched-menu measurements. It does not include search queries, commands,
timestamps, result ranks, unmatched or raw keys, focused applications, event
history, UI preferences, or ignored-item decisions. Configure a default agent
with `omarchy default agent <name>` before using the button.

The native event and capability contract is tracked in
[issue #17](https://github.com/FilipHarald/omacoach/issues/17) and proposed in
[basecamp/omarchy#7372](https://github.com/basecamp/omarchy/pull/7372).
Omacoach accepts the proposed semantic event and detects its declared capability.
Unsupported menus disable only search-selection coaching; shortcut hints and
attempted-shortcut measurement are independent and continue working.

## Requirements

- Omarchy Quattro with `omarchy-shell`, `omarchy-menu-keybindings`,
  `omarchy-menu-select`, and `omarchy-launch-config-editor`.
- Hyprland with the Lua APIs validated by `bin/install-hook`.
- `hyprctl`, `luac`, `jq`, `xkbcli`, and Node.js available on `PATH`.
- `qmllint` for development checks only.

Search-selection coaching additionally needs the menu hook described at the top
of this README. Shortcut discovery and attempted-shortcut measurement work
without it.

## Install

Install and enable the public plugin, then install its Hyprland observer and
`SUPER+CTRL+K` panel binding:

```bash
omarchy plugin add https://github.com/FilipHarald/omacoach.git --enable
~/.config/omarchy/plugins/io.github.filipharald.omacoach/bin/install-hook
```

The hook validates the plugin and Hyprland Lua APIs, makes a timestamped backup
of `~/.config/hypr/bindings.lua`, adds marked observer and panel-binding blocks,
reloads Hyprland, and restores the backup if validation fails.

## Remove

Run the uninstall hook before removing the plugin checkout:

```bash
~/.config/omarchy/plugins/io.github.filipharald.omacoach/bin/uninstall-hook
omarchy plugin remove io.github.filipharald.omacoach
```

Uninstalling disables the plugin when possible, transactionally removes the
observer and panel binding, and permanently deletes
`${XDG_STATE_HOME:-~/.local/state}/omacoach`. Configuration is restored from the
timestamped backup if Hyprland rejects the change.

## Development install

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.filipharald.omacoach
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.filipharald.omacoach
./bin/install-hook
```

Use `./bin/uninstall-hook` before removing the development symlink.

## Development

Run all model, observer, lifecycle, plugin, Lua, and QML checks with:

```bash
./scripts/check
```

Preview or hide the passive UI without holding a modifier:

```bash
monitor=$(hyprctl activeworkspace -j | jq -r '.monitor // ""')
omarchy-shell omacoach preview SUPER "$monitor"
omarchy-shell omacoach hide "$(date +%s%3N)"
```

## Attribution

The passive Hyprland observer and contextual overlay architecture were informed
by [NextKey](https://github.com/russellmorton/next-key), Copyright (c) 2026
Russell Morton, available under the MIT License. See
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
