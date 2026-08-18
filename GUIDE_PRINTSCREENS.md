# Screenshot guide

This guide reproduces the screenshots embedded in `README.md` without capturing
unrelated application windows.

## Requirements

The commands use:

- `grim` to capture a selected Wayland region;
- `slurp` to select the Omacoach card;
- ImageMagick's `magick` command to remove metadata and create compact WebP
  images.

Confirm they are available:

```bash
command -v grim slurp magick
```

## Prepare the desktop

1. Switch to an empty workspace or start the Omarchy screensaver.
2. Ensure no notifications, menus, or private content overlap the Omacoach card.
3. Reload the shell so the screenshots use the current source:

```bash
omarchy-restart-shell
```

## Capture the passive overlay

Open a deterministic SUPER preview on the active output:

```bash
monitor=$(hyprctl activeworkspace -j | jq -r '.monitor // ""')
omarchy-shell omacoach preview SUPER "$monitor"
```

Capture the card. When `slurp` appears, drag from the card's top-left border to
its bottom-right border, excluding the desktop around it:

```bash
grim -g "$(slurp)" /tmp/omacoach-passive.png
magick /tmp/omacoach-passive.png -strip -quality 88 docs/screenshots/passive-overlay.webp
```

Hide the preview:

```bash
omarchy-shell omacoach hide "$(date +%s%3N)"
```

## Capture the permanent panel

Open the panel:

```bash
./bin/toggle-panel
```

Select only the card and convert it:

```bash
grim -g "$(slurp)" /tmp/omacoach-permanent.png
magick /tmp/omacoach-permanent.png -strip -quality 88 docs/screenshots/permanent-panel.webp
```

Press `Escape` to close the panel.

## Verify the files

Check dimensions, sizes, and repository changes:

```bash
magick identify docs/screenshots/passive-overlay.webp docs/screenshots/permanent-panel.webp
du -h docs/screenshots/*.webp
git status --short
```

Open both images and verify that:

- text is legible at GitHub's README width;
- no private window, notification, username, or search query is visible;
- the complete Omacoach border is included;
- the passive image has no permanent controls;
- the permanent image shows the close row, modifier filter, and all three footer
  sections.

Commit both screenshots together with any README layout changes so the images
always describe the checked-in UI.
