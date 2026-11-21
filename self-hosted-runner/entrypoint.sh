#!/bin/bash
# Starts this runner's own dockerd, registers the runner on its first start,
# then takes jobs until the container stops.
set -euo pipefail

# cgroup v2: move our processes into a child group so the nested dockerd can
# create its own groups (the same step docker:dind's entrypoint does).
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  mkdir -p /sys/fs/cgroup/init
  xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true
  sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
    > /sys/fs/cgroup/cgroup.subtree_control || true
fi

dockerd > /var/log/dockerd.log 2>&1 &
for _ in $(seq 1 60); do
  docker info > /dev/null 2>&1 && break
  sleep 1
done
docker info > /dev/null 2>&1 || { tail -50 /var/log/dockerd.log; exit 1; }

cd /home/runner/actions-runner
if [ ! -f .runner ]; then
  : "${RUNNER_TOKEN:?the first start needs RUNNER_TOKEN, see README.md}"
  sudo -u runner -H ./config.sh --unattended --replace \
    --url "$RUNNER_URL" --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work _work
fi
exec sudo -u runner -H env ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/bin/job-started.sh ./run.sh
