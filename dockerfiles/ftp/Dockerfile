FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    vsftpd iproute2 iputils-ping netcat-openbsd net-tools \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -d /home/ftpuser -s /usr/sbin/nologin ftpuser \
    && echo "ftpuser:FtpPass2026" | chpasswd \
    && chmod 755 /home/ftpuser
COPY vsftpd.conf /etc/vsftpd.conf
EXPOSE 21
CMD ["/usr/sbin/vsftpd", "/etc/vsftpd.conf"]
