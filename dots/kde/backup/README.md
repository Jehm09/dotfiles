# Panel backups

The panel/taskbar is built **by hand**, not by a script. Nothing in the profile
touches it: `plasma-org.kde.plasma.desktop-appletsrc` is deliberately absent from
`files.list`, so `setup kde apply` will never overwrite a hand-made panel.

| File | What it is |
|---|---|
| `plasma-appletsrc.pre-rice.20260729_184804` | Plasma's stock panel, captured before any scripted change. Currently restored and live. |
| `plasma-appletsrc.claude-rice.20260729_200324` | The scripted layout (Arch, kara, global menu, plasmusic, tray, volume/bt/net, settings, clock). Kept for reference only. |
| `panels.js.unused` | The scripting-API layout that produced the above. Not wired up: `setup kde panels` now errors out because `dots/kde/panels.js` no longer exists. |

## Restoring one of these

plasmashell rewrites this file from memory on exit, so it must be stopped first
or the copy is silently thrown away:

```bash
systemctl --user stop plasma-plasmashell.service
cp <backup> ~/.config/plasma-org.kde.plasma.desktop-appletsrc
systemctl --user start plasma-plasmashell.service
```

## Capturing a hand-made panel later

Two options, once the panel is how you want it:

1. **Track the file.** Add `.config/plasma-org.kde.plasma.desktop-appletsrc` to
   `files.list` and run `setup kde save`. Simplest, but the file mixes layout with
   machine state (screen mapping, generated applet IDs), so it is not portable to
   another machine.
2. **Regenerate a script from it.** Read the live layout and widget configs, then
   write them back out as a `panels.js`. Portable, but has to be redone whenever
   the panel changes.
