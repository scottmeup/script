#!/usr/bin/env bash
# /fd/{1 = stdout}, {2 = stderr}
tail -f /proc/`pgrep youtubeuploader`/fd/1