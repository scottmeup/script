# Jellyfin Library Pruner

`jellyfin-library-pruner.sh` cleans Jellyfin media folders when trickplay images and sidecars are stored beside media files on HDD-backed library paths.

## Files

- `jellyfin-library-pruner.sh`: cleanup script.
- `jellyfin-library-pruner.env.example`: example dotenv config.
- `jellyfin-library-pruner.json`: validation details, file sizes, and checksums.

## Implemented cleanup logic

### Movies

1. If a movie media file is present anywhere inside a movie folder, the movie folder and all contents are preserved.
2. If a movie media file is not present anywhere inside a movie folder, the movie root folder is deleted when `DRY_RUN_MODE=false`.

### Shows

1. If an episode media file is present in a retained season folder, that episode file and associated sidecars are preserved.
2. If an episode media file is absent but associated sidecars remain in a retained season folder, matching subtitle, `.nfo`, thumbnail, and `.trickplay` entries are deleted when `DRY_RUN_MODE=false`.
3. If a season folder has at least one video file, the season folder is preserved.
4. If a season folder has no video files, the season folder is deleted recursively when `DRY_RUN_MODE=false`.
5. After season cleanup, if a show root has no videos recursively, the show root folder is deleted when `DRY_RUN_MODE=false`.
6. After season cleanup, if a show root has at least one video recursively, the show root folder is preserved.

## Dry-run mode

`DRY_RUN_MODE=true` means no deletions take place. A separate deletion-list file is created at `DRY_RUN_OUTPUT_FILE` and contains every path that would be deleted if `DRY_RUN_MODE=false`.

`CREATE_FORCE_RESCAN` is independent of `DRY_RUN_MODE`. If `CREATE_FORCE_RESCAN=true`, marker files are created even during dry-run mode.

## Logging

Logging can go to terminal, a file, or both:

```bash
LOG_TO_TERMINAL=true
LOG_TO_FILE=false
LOG_DIR=./logs
LOG_MAX_FILES=10
```

When file logging is enabled, log files are named like `jellyfin-library-pruner-YYYYMMDDTHHMMSSZZZZ.log` and contain a local ISO 8601 `generated_at` timestamp. If `LOG_MAX_FILES` is greater than `0`, the oldest matching log files are deleted first so only the newest configured number remains.

## About `SEASON_DIR_GLOB="Season *"`

The asterisk is intentional. It is a `find -name` pattern that matches folders such as `Season 1`, `Season 01`, and `Season 10`. The quotes are included because the value contains a space.

## Usage

```bash
cp jellyfin-library-pruner.env.example .env
```

Edit `.env`:

```bash
MOVIE_PATHS=/mnt/media/movies
SHOW_PATHS=/mnt/media/shows
DRY_RUN_MODE=true
```

Run dry run:

```bash
ENV_FILE=.env bash jellyfin-library-pruner.sh
```

Review the terminal/log output and the file at `DRY_RUN_OUTPUT_FILE`. If the planned deletions are correct, set:

```bash
DRY_RUN_MODE=false
```

Then run again:

```bash
ENV_FILE=.env bash jellyfin-library-pruner.sh
```

## Revert

There is no automatic undo for deleted filesystem content. Use `DRY_RUN_MODE=true` first, review the output, and take a filesystem snapshot or backup before running with `DRY_RUN_MODE=false`.
