# Pipelines

This Repo just manages deployments.

There is nothing other than 

.github -> actions
.github -> workflows

In Workflows, name starting with "base_" are reusable workflows. not triggered directly.

The 0_* pipelines can also be called with `tests_only: true`: their test jobs run and every deploy or store job is skipped. 1_Branch_Check does this to test a wonderWhy branch without deploying it; its folder map is `.github/actions/branch_stacks/branch_stacks.sh` (tests next to it). A new deploy job in a 0_* pipeline needs `if: ${{ !inputs.tests_only }}`.

1_Branch_Check runs only the tests a branch's changes need, down to the job and the E2E leg: backend, web, mobile and web_e2e_journey take an `only` input (empty = everything, so main and manual runs are unchanged). A changed test file runs only the legs that use it, plus its app's lint. A new test job in those pipelines needs an `if:` on `inputs.only` like its neighbours, or it runs on every branch.
The matrix legs live in `.github/legs/*.json` (web journeys, android E2E, backend functional), read by `.github/actions/pick_legs` and by the folder map. Add or change a leg there, not in the workflow.
A path the folder map has no rule for (a new folder) turns the plan red. Ask the user which tests it needs, then add the rule and a test line; never default it to everything.

Never trigger prod pipeline, or app publish, without manual intervention. 
E2E suites: each wonderWhy `functional-test/suites/<suite>.json` becomes a CI leg at run time (`.github/actions/e2e_suites`, tests next to it): web in `web_e2e_journey.yml` (job `suites`), android in `0_deploy_mobile.yml` (job `android_suites`, which the store promotions need). A new suite needs no edit here.
