# One GitHub Actions runner with its own Docker inside (Docker-in-Docker).
# Each runner container has its own ports, /tmp, processes and image cache,
# so E2E legs on one box never clash on ports 80/15432/3005, seed logs or
# `pkill -f 'tool/seed_'`. It runs privileged: its dockerd needs that.
#
# Ubuntu 24.04 on purpose: the E2E job's playwright 1.56 (patrol 4.9)
# refuses to install chromium on 26.04.
FROM ubuntu:24.04

ARG RUNNER_VERSION=2.338.2
ARG PLAYWRIGHT_VERSION=1.56.0

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# What the steps and setup actions expect from a GitHub-hosted runner.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg iptables jq locales lsof procps sudo \
      tzdata unzip xz-utils zip \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# Docker Engine, compose and buildx, for this runner's own dockerd.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# Chromium's system libraries. The GitHub image ships them, and the job
# installs only the browser (npx playwright install chromium, no --with-deps).
# Node runs playwright's installer here and is removed after; the job brings
# its own Node through actions/setup-node.
RUN arch=$(dpkg --print-architecture | sed 's/amd64/x64/') \
 && f=$(curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt | grep -oE "node-v22\.[0-9.]+-linux-${arch}\.tar\.xz" | head -1) \
 && mkdir /opt/node \
 && curl -fsSL "https://nodejs.org/dist/latest-v22.x/${f}" | tar -xJ -C /opt/node --strip-components=1 \
 && PATH=/opt/node/bin:$PATH npx --yes playwright@${PLAYWRIGHT_VERSION} install-deps chromium \
 && rm -rf /opt/node /root/.npm /var/lib/apt/lists/*

# The runner user: passwordless sudo and in the docker group, as on GitHub.
RUN useradd -m -s /bin/bash runner \
 && usermod -aG docker runner \
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner

WORKDIR /home/runner/actions-runner
RUN arch=$(dpkg --print-architecture | sed 's/amd64/x64/') \
 && curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz" | tar -xz \
 && ./bin/installdependencies.sh \
 && rm -rf /var/lib/apt/lists/* \
 && chown -R runner:runner /home/runner

COPY entrypoint.sh job-started.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
