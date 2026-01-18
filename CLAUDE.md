# Pipelines

This Repo just manages deployments.

There is nothing other than 

.github -> actions
.github -> workflows

In Workflows, name starting with "base_" are reusable workflows. not triggered directly.

Never trigger prod pipeline, or app publish, without manual intervention. 