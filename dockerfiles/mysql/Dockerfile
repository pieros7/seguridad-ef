FROM mariadb:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*
