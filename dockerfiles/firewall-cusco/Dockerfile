FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iptables iputils-ping netcat-openbsd net-tools tcpdump \
    strongswan strongswan-starter libcharon-extra-plugins libstrongswan-extra-plugins \
    && rm -rf /var/lib/apt/lists/*
COPY ipsec.conf /etc/ipsec.conf
COPY ipsec.secrets /etc/ipsec.secrets
RUN chmod 600 /etc/ipsec.secrets
CMD ["sleep", "infinity"]
