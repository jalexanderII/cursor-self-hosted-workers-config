ARG BASE_IMAGE=ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54
FROM ${BASE_IMAGE}

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=dev
ARG CURSOR_INSTALL_URL=https://cursor.com/install

LABEL org.opencontainers.image.title="Cursor self-hosted Cloud Agent worker" \
      org.opencontainers.image.description="Minimal customer-managed worker image for Cursor Self-Hosted Pools" \
      org.opencontainers.image.source="https://github.com/jalexanderII/cursor-self-hosted-workers-config" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}"

# Worker image strategy:
# - The Cursor Kubernetes controller manages worker lifecycle and auth tokens.
# - This image only needs the tools every worker pod should have at startup:
#   Cursor agent CLI, git, curl/CA certificates, and repo-specific build tools.
# - Do not bake secrets into the image. Kubernetes Secrets are mounted/injected
#   at runtime by the WorkerDeployment.
# - libatomic1 is required by recent Node Linux binaries; without it, Node can
#   install but fail at runtime with "libatomic.so.1: cannot open shared object".
RUN apt-get update && apt-get install -y --no-install-recommends \
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
ENV PATH=/home/worker/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cursor's official installer is the supported distribution mechanism. Keep the
# URL overridable so regulated environments can mirror the installer internally.
RUN curl --proto '=https' --tlsv1.2 -fsSL "${CURSOR_INSTALL_URL}" -o /tmp/install-cursor.sh && \
  bash /tmp/install-cursor.sh && \
  rm -f /tmp/install-cursor.sh && \
  agent --version

USER root
COPY start-worker.sh /usr/local/bin/start-worker
RUN chmod 755 /usr/local/bin/start-worker
USER worker

WORKDIR /workspace
CMD ["/usr/local/bin/start-worker"]
