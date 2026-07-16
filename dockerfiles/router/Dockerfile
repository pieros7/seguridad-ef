FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iptables iputils-ping netcat-openbsd net-tools \
    && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]
