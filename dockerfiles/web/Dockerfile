FROM nginx:stable
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping netcat-openbsd openssl \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=PE/ST=Lima/L=Lima/O=Seguridad/CN=localhost"
COPY default.conf /etc/nginx/conf.d/default.conf
