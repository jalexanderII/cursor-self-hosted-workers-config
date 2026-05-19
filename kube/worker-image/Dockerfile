FROM ubuntu:24.04

# Worker image strategy:
# - The Cursor Kubernetes controller manages worker lifecycle and auth tokens.
# - This image only needs the tools every worker pod should have at startup:
#   Cursor agent CLI, git, curl/CA certificates, and repo-specific build tools.
# - Do not bake secrets into the image. Kubernetes Secrets are mounted/injected
#   at runtime by the WorkerDeployment.
# - libatomic1 is required by recent Node Linux binaries; without it, Node can
#   install but fail at runtime with "libatomic.so.1: cannot open shared object".
RUN apt-get update && apt-get install -y \
  bash \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  libatomic1 \
  openssh-client \
  && rm -rf /var/lib/apt/lists/*

# Use a high UID to avoid colliding with users already present in the base image.
# The worker process does not need root.
RUN useradd -m -u 10001 worker && \
  mkdir -p /workspace && \
  chown -R worker:worker /workspace /home/worker

USER worker
ENV HOME=/home/worker
ENV PATH=/home/worker/.local/share/mise/shims:/home/worker/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cursor's official docs require the agent CLI in the image.
RUN curl -fsSL https://cursor.com/install | bash

# Optional but useful for TypeScript/Node repos. Adjust these versions for your
# repo, or remove mise entirely if your worker image uses another toolchain.
ARG NODE_VERSION=25
ARG PNPM_VERSION=10
RUN curl https://mise.run | sh && \
  /home/worker/.local/bin/mise use -g node@${NODE_VERSION} pnpm@${PNPM_VERSION} && \
  /home/worker/.local/bin/mise install

USER root
COPY start-worker.sh /usr/local/bin/start-worker
RUN chmod 755 /usr/local/bin/start-worker
USER worker

WORKDIR /workspace
CMD ["/usr/local/bin/start-worker"]
