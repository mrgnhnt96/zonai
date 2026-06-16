# Favicon

Zonai serves the app's favicon at `GET /favicon.ico`. The file is read directly from disk on every request, so replacing it takes effect immediately without a restart.

## Default location

The favicon lives in your app's **images directory** (`imagesPath` in `zonai.yaml`, defaulting to `.zonai/data/images`):

```text
.zonai/data/images/favicon.ico
```

When you run `dart run zonai dev` for the first time, a placeholder `favicon.ico` is written to this path automatically. Replace it with your own icon at any time.

## Supplying a custom favicon

Drop your `favicon.ico` file into the images directory:

```bash
cp my-icon.ico .zonai/data/images/favicon.ico
```

No restart is needed — the next request to `/favicon.ico` serves the updated file.

## Changing the images directory

If you want the favicon (and all uploaded images) to live elsewhere, set `imagesPath` in `zonai.yaml`:

```yaml
imagesPath: assets/images
```

Then place your favicon at `assets/images/favicon.ico`. The server resolves the path relative to the directory where you run `dart run zonai`.

## Behavior when the file is missing

If `favicon.ico` is absent from the images directory, the endpoint returns **404**. Re-running `dart run zonai dev` will not re-create the file once it has been deleted — copy it back manually or restore it from your placeholder:

```bash
cp path/to/backup/favicon.ico .zonai/data/images/favicon.ico
```
