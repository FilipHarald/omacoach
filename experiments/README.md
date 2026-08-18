# Searched-app menu experiment

Omarchy's stock menu does not publish an event when an application is selected
after search. The experiment in `menu-search-event.patch` applies to a clone
created by:

```bash
omarchy plugin clone omarchy.menu
```

It emits only the selected desktop-entry ID and display name when the trimmed
filter is non-empty. It does not emit the query, cancelled searches, dmenu
input, submenu navigation, or static menu actions.

This is a temporary Omacoach-specific proof of concept. Native semantic events
and capability detection are tracked in
[issue #17](https://github.com/FilipHarald/omacoach/issues/17) and proposed in
[basecamp/omarchy#7372](https://github.com/basecamp/omarchy/pull/7372). Removing
the cloned plugin restores the stock menu through Omarchy's clone-source routing.
