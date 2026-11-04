# Pipelines

This Repo just manages deployments.

There is nothing other than 

.github -> actions
.github -> workflows

In Workflows, name starting with "base_" are reusable workflows. not triggered directly.

The 0_* pipelines can also be called with `tests_only: true`: their test jobs run and every deploy or store job is skipped. 1_Branch_Check does this to test a wonderWhy branch without deploying it; its folder map is `.github/actions/branch_stacks/branch_stacks.sh` (tests next to it). A new deploy job in a 0_* pipeline needs `if: ${{ !inputs.tests_only }}`.

Never trigger prod pipeline, or app publish, without manual intervention. 