---
title: Branding
description: Replace the dashboard's favicon and logo by dropping files into your images directory.
---

Two pieces of the dashboard's look can be replaced without touching any code:
the browser **favicon**, which starts out as the Zonai mark, and the **logo**
shown in the sidebar and above the sign-in card, which starts out as a tile
bearing the first letter of your app name.

Both are plain files read from your project's images directory — the same
`imagesPath` that holds [photo uploads](/schemas/photo-tables), which defaults
to `.zonai/data/images`. Drop a file in, reload, done. Neither requires a
recompile, a config field, or a server restart.

| File | Served at | Default |
| --- | --- | --- |
| `<imagesPath>/favicon.ico` | `/favicon.ico` | Zonai mark, seeded at project init |
| `<imagesPath>/logo.png` | `/logo.png` | None — falls back to a letter tile |

<Info>

If you changed `imagesPath` in [`zonai.yaml`](/configuration/zonai-yaml), both
files follow it. The paths below assume the default.

</Info>

## Favicon

`zonai dev` writes a default `favicon.ico` — the Zonai mark — when it scaffolds
a new project. That scaffolding step runs **only when there is no `zonai.yaml`
yet**, so once your project is initialized, `zonai dev` never touches the file
again and your own favicon is safe.

To use your own, replace the file:

```bash
cp my-icon.ico .zonai/data/images/favicon.ico
```

Reload the dashboard and the browser tab picks it up. You may need a hard
refresh — browsers cache favicons aggressively.

The file must be a real `.ico`. It is served with `Content-Type:
image/x-icon`, and browsers find it by the root-path convention rather than a
`<link>` tag in the page, so the name and location are not negotiable.

If you delete the file, `/favicon.ico` returns 404 and the browser falls back to
its generic page icon. Re-running `zonai dev` will **not** bring it back — the
scaffolding step is skipped for an initialized project. Copy an `.ico` into
place yourself to restore it.

## Logo

The dashboard shows a logo in two places: the sidebar header next to your app
name, and above the card on the sign-in screen.

By default this is not artwork — it is a rounded tile containing the first
letter of `appName` from your [app config](/configuration/app-config), drawn in
your theme's primary color. Nothing is seeded on disk, and that absence is what
selects the letter tile.

To replace it, add a `logo.png`:

```bash
cp my-logo.png .zonai/data/images/logo.png
```

Reload the dashboard. Both places switch to your image; the letter tile is not
shown anywhere once the file exists.

### Choosing an image

- **PNG only.** The filename is fixed and the route serves
  `Content-Type: image/png`. An SVG or JPEG renamed to `logo.png` will not
  render.
- **Square.** The tile is 32×32 CSS pixels in the sidebar and 52×52 on the
  sign-in screen. The image is drawn with `object-fit: cover`, so a
  non-square file is center-cropped rather than stretched.
- **Supply it at 2×.** A 128×128 source keeps the mark crisp on high-density
  displays.
- **Bring your own background.** The primary-color fill behind the letter tile
  is removed when an image is present, so a transparent PNG sits directly on
  the sidebar. Use an opaque image if you want a filled tile.

<Info>

Zonai does not resize or re-encode `logo.png` — it is streamed to the browser
exactly as it sits on disk. Compress it before dropping it in.

</Info>

## Both files in production

`zonai build` copies whichever of the two exist into the build bundle's images
directory, so a binary carries the branding that was present when you built it.
Neither file is required — a build with neither is perfectly valid and simply
falls back to the browser's default icon and the letter tile.

Because both are read off disk at request time, you can also replace them on a
deployed server without rebuilding: write the new file into the running
server's images directory and reload.

<Warning>

The images directory is also where photo uploads live. If your deployment
mounts it as a volume, make sure the branding files land in the mounted path —
otherwise a redeploy that resets the container filesystem takes them with it.

</Warning>

## Related

- [Dashboard Overview](/dashboard/overview) — reaching the dashboard and signing in
- [zonai.yaml](/configuration/zonai-yaml) — where `imagesPath` is configured
- [App Config](/configuration/app-config) — `appName`, which drives the letter tile
- [Photo Tables](/schemas/photo-tables) — the other user of the images directory
