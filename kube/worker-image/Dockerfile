ARG BASE_IMAGE=ubuntu:24.04@sha256:786a8b558f7be160c6c8c4a54f9a57274f3b4fb1491cf65146521ae77ff1dc54
FROM ${BASE_IMAGE}

ARG CURSOR_INSTALL_URL=https://cursor.com/install

# Minimal worker image: Cursor CLI, git, and common shell tools.
# Secrets are mounted or injected at runtime, never baked into the image.
# libatomic1 is required by recent Node Linux binaries.
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

RUN useradd -m -u 10001 worker && \
  mkdir -p /workspace && \
  chown -R worker:worker /workspace /home/worker

USER worker
ENV HOME=/home/worker
ENV PATH=/home/worker/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Override CURSOR_INSTALL_URL to use an internally mirrored installer when required.
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
