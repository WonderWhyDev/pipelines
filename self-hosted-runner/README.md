# Self-hosted E2E runners

Our own Linux box takes some web E2E legs off GitHub's runners. Each runner is
a container with its own Docker inside, so two legs on one box never clash on
ports (80, 15432, 3005), `/tmp` files or seed process names.

The workflow side is one line in `web_e2e_journey.yml`: a leg named in the
repo variable `E2E_BOX_LEGS` runs on the label `ww-e2e`; every other leg stays
on GitHub.

## What the box needs

- Docker Engine with the compose plugin. Any Linux works; the runner image is
  Ubuntu 24.04.
- Memory: one leg peaked at 8 GB (no_driver leg, Flutter debug build, measured
  21 Nov 2026). So one runner per 12 GB box for now.
- Disk: about 15 GB per runner (Flutter SDK, Docker images, checkout).

## Start a runner

1. Get a registration token. It works for 1 hour.
   `gh api -X POST repos/WonderWhyDev/pipelines/actions/runners/registration-token -q .token`
   (or pipelines > Settings > Actions > Runners > New self-hosted runner).
2. On the box, in this folder:
   `RUNNER_TOKEN=<token> docker compose up -d --build`
3. Check that `docker compose logs -f e2e-1` ends with "Listening for Jobs".

The runner keeps its registration in its volume, so later starts need no
token: `docker compose up -d`.

## Send legs to the box

`gh variable set E2E_BOX_LEGS -R WonderWhyDev/pipelines --body '["operations"]'`

A leg's name is `name` (journeys, `.github/legs/web_journeys.json`) or `leg`
(suites). A leg sent to the box never falls back to GitHub. If the box is
down, send everything back with `--body '[]'`.

## Keep it safe (pipelines is public)

A fork pull request can add a workflow that runs on these runners, and they
run privileged. Make every outside contributor's workflow wait for approval:

`gh api -X PUT repos/WonderWhyDev/pipelines/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors`

Never approve a workflow run from a fork.

## Add a runner

Copy the `e2e-1` block in `compose.yml` as `e2e-2` (its name and both
volumes), get a new token, and run step 2 again.

## Register again

GitHub removes a runner that has been offline for 14 days. Then:

`docker compose down && docker volume rm ww-runners_e2e-1-runner && RUNNER_TOKEN=<token> docker compose up -d`
