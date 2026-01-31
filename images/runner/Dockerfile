FROM ghcr.io/actions/actions-runner:latest

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

# Install node and yarn
RUN apt install -y nodejs npm && \
    npm install -g yarn;

# Install ruby and python
RUN apt install -y ruby ruby-dev python3 python3-dev;

# Patch ACTION_RESULTS_URL for custom cache server
RUN sed -i \
      's/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x55\x00\x52\x00\x4C\x00/\x41\x00\x43\x00\x54\x00\x49\x00\x4F\x00\x4E\x00\x53\x00\x5F\x00\x52\x00\x45\x00\x53\x00\x55\x00\x4C\x00\x54\x00\x53\x00\x5F\x00\x4F\x00\x52\x00\x4C\x00/g' \
      /home/runner/bin/Runner.Worker.dll;

# Fix permisisons
RUN mkdir -p /opt/hostedtoolcache; \
    chown -R runner:runner /opt/hostedtoolcache;

RUN chmod 777 /usr/local/bin;

RUN echo 'runner ALL=(ALL) NOPASSWD:ALL' | tee /etc/sudoers.d/runner
RUN chmod 0440 /etc/sudoers.d/runner

# Clean up APT cache
RUN rm -rf /var/lib/apt/lists/*

USER runner
