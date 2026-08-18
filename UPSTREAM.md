# Upstream Omarchy requirement

Omacoach can prototype searched-app observations with a local menu clone, but
production integration requires one semantic event in `basecamp/omarchy`.

The current stock and cloned menus expose no reliable runtime capability probe.
Omacoach cannot distinguish an unsupported menu from one that simply has not
produced an event yet, and Omarchy/menu version numbers do not identify the
experimental hook.

## App selected after search

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

## Capability detection

The active menu should declare the versioned semantic capability in its
manifest:

```json
{
  "capabilities": {
    "app-selected-after-search": 1
  }
}
```

The shell should expose a documented, clone-aware query equivalent to:

```qml
pluginSupports("omarchy.menu", "app-selected-after-search", 1)
```

The query must resolve the currently enabled implementation of `omarchy.menu`,
including user clones, and return distinct `checking`, `supported`, and
`unsupported` states without requiring the menu to be open. Source inspection,
version gating, and waiting for the first event are not reliable substitutes.

The shell should accept publications only from the resolved active menu whose
manifest declares the capability. Older shells without the query or signal are
unsupported. Omacoach should then disable only searched-app collection,
matching, counters, and Coach actions; passive shortcut hints and attempted-
shortcut measurement are independent and should remain available.

This belongs in `basecamp/omarchy` on the Quattro shell. The validated local
patch is `experiments/menu-search-event.patch`.

## References

- [Omarchy app activation flow](https://github.com/basecamp/omarchy/blob/262d6f0681ce27abbb10587b794f22d58bdbcec8/shell/plugins/menu/Menu.qml#L759-L786)
