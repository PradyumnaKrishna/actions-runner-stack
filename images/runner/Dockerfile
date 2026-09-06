# Pinned: the patch below targets exact bytes, and GitHub rejects deprecated
# runner versions. Keep current.
FROM ghcr.io/actions/actions-runner:2.337.0@sha256:e5496277be5d09bc968b3d64911b74e219ac4a3f2edce956a3ecf9271bea1ef4

USER root

ENV DEBIAN_FRONTEND=noninteractive \
    CUSTOM_ACTIONS_RESULTS_URL=http://localhost:3000

# Install Development Tools
RUN apt-get update && \
    apt-get install -y ca-certificates sudo curl lsb-release apt-transport-https software-properties-common && \
    update-ca-certificates;

RUN apt install -y clang cmake build-essential gcc;

ENV CC=/usr/bin/clang \
    CXX=/usr/bin/clang++

RUN apt install -y fuse libfuse2 libpq-dev libyaml-dev iptables libharfbuzz0b libfribidi0;

# The runner bundles its own Node in externals/ for JS actions. Workflows
# needing a language runtime should use setup-node / setup-ruby.
RUN apt install -y python3 python3-dev;

# Patch ACTION_RESULTS_URL for custom cache server.
# sed exits 0 on no match, so verify rather than ship an unpatched runner.
RUN sed -i \
      's/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x55\x00\x52\x00\x4C\x00/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x4F\x00\x52\x00\x4C\x00/g' \
      /home/runner/bin/Runner.Worker.dll; \
    test "$(strings -e l /home/runner/bin/Runner.Worker.dll | grep -c '^ACTIONS_RESULTS_ORL$')" = 1 && \
    test "$(strings -e l /home/runner/bin/Runner.Worker.dll | grep -c '^ACTIONS_RESULTS_URL$')" = 0

# Fix permissions
RUN mkdir -p /opt/hostedtoolcache; \
    chown -R runner:runner /opt/hostedtoolcache;

RUN chmod 777 /usr/local/bin;

RUN echo 'runner ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/runner
RUN chmod 0440 /etc/sudoers.d/runner

# Clean up APT cache
RUN rm -rf /var/lib/apt/lists/*

USER runner
