#!/bin/bash
# Runs before every job. Clears what a crashed or cancelled job may have left
# in this runner, so each job starts like on a fresh GitHub VM. Docker images
# stay, so pulls are cached.
docker ps -aq | xargs -r docker rm -f > /dev/null 2>&1 || true
docker volume ls -q | xargs -r docker volume rm > /dev/null 2>&1 || true
docker network prune -f > /dev/null 2>&1 || true
find /tmp -mindepth 1 -maxdepth 1 -user runner -exec rm -rf {} + 2> /dev/null || true
