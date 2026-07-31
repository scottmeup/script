# Jellyfin library pruner

This bundle cleans Jellyfin media folders when trickplay images are stored beside media files on HDD-backed library paths.

Do a dry run with `DELETE_MODE=false` first, review the output, and take a filesystem snapshot or backup before running with `DELETE_MODE=true`.

## Files

- `jellyfin-library-pruner.sh`: cleanup script.
- `jellyfin-library-pruner.env.example`: example dotenv config.

## Implemented logic

### Movies

1. If a movie media file is present anywhere inside a movie folder, the movie folder and all contents are preserved.
2. If a movie media file is not present anywhere inside a movie folder, the movie root folder is deleted when `DELETE_MODE=true`.

### Shows

1. If an episode media file is present in a retained season folder, that episode file and associated sidecars are preserved.
2. If an episode media file is absent but associated sidecars remain in a retained season folder, matching subtitle, `.nfo`, thumbnail, and `.trickplay` entries are deleted when `DELETE_MODE=true`.
3. If a season folder has at least one video file, the season folder is preserved.
4. If a season folder has no video files, the season folder is deleted recursively when `DELETE_MODE=true`.
5. After season cleanup, if a show root has no videos recursively, the show root folder is deleted when `DELETE_MODE=true`.
6. After season cleanup, if a show root has at least one video recursively, the show root folder is preserved.

## Optional `.forcerescan`

Set `CREATE_FORCE_RESCAN=true` to create `.forcerescan` marker files in configured roots and preserved media locations. The default is `false`.

## Usage

```bash
cp jellyfin-library-pruner.env.example .env
```

Edit `.env`:

```bash
MOVIE_PATHS=/mnt/media/movies
SHOW_PATHS=/mnt/media/shows
DELETE_MODE=false
```

Run dry run:

```bash
ENV_FILE=.env bash jellyfin-library-pruner.sh
```

If the dry-run output is correct, set:

```bash
DELETE_MODE=true
```

Then run again:

```bash
ENV_FILE=.env bash jellyfin-library-pruner.sh
```