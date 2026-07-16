#!/bin/sh

# 1. Limpieza de contenedores y redes existentes
docker rm -f srv-web-cusco fw-cusco user1 router-central fw-lima srv-mysql-lima srv-ftp-lima cliente1-lima cliente2-lima 2>/dev/null || true
docker network rm net_lan_cusco net_wan_cusco net_wan_lima net_dmz_lima net_lan_lima net_cusco_lan net_cusco_wan net_lima_lan net_lima_wan 2>/dev/null || true

# 2. Creación de redes personalizadas con sus subredes
docker network create --subnet=10.10.1.0/24 net_lan_cusco
docker network create --subnet=192.168.10.0/24 net_wan_cusco
docker network create --subnet=192.168.20.0/24 net_wan_lima
docker network create --subnet=172.31.1.0/24 net_dmz_lima
docker network create --subnet=172.32.1.0/24 net_lan_lima

# 3. Construcción de imágenes Docker utilizando Dockerfiles físicos
docker build -t firewall-cusco dockerfiles/firewall-cusco
docker build -t firewall-lima dockerfiles/firewall-lima
docker build -t router dockerfiles/router
docker build -t cliente dockerfiles/cliente
docker build -t web dockerfiles/web
docker build -t ftp dockerfiles/ftp
docker build -t mysql dockerfiles/mysql


# 4. Despliegue de contenedores y asignación a redes
# Zona Cusco
docker run -d --name srv-web-cusco --hostname srv-web-cusco --network net_lan_cusco --ip 10.10.1.2 --cap-add NET_ADMIN web
docker run -d --name fw-cusco --hostname fw-cusco --network net_lan_cusco --ip 10.10.1.3 --privileged firewall-cusco
docker network connect --ip 192.168.10.2 net_wan_cusco fw-cusco

# Zona WAN
docker run -d --name user1 --hostname user1 --network net_wan_cusco --ip 192.168.10.4 --cap-add NET_ADMIN cliente
docker run -d --name router-central --hostname router-central --network net_wan_cusco --ip 192.168.10.3 --privileged router
docker network connect --ip 192.168.20.3 net_wan_lima router-central

# Zona Lima
docker run -d --name fw-lima --hostname fw-lima --network net_wan_lima --ip 192.168.20.4 --privileged firewall-lima
docker network connect --ip 172.31.1.4 net_dmz_lima fw-lima
docker network connect --ip 172.32.1.4 net_lan_lima fw-lima

docker run -d --name srv-mysql-lima --hostname srv-mysql-lima --network net_dmz_lima --ip 172.31.1.2 --cap-add NET_ADMIN -e MARIADB_ROOT_PASSWORD=RootSecure2026 -e MARIADB_DATABASE=seguridad_db -e MARIADB_USER=seguridad_user -e MARIADB_PASSWORD=SecurePass2026 mysql
docker run -d --name srv-ftp-lima --hostname srv-ftp-lima --network net_dmz_lima --ip 172.31.1.3 --cap-add NET_ADMIN ftp
docker run -d --name cliente1-lima --hostname cliente1-lima --network net_lan_lima --ip 172.32.1.2 --cap-add NET_ADMIN cliente
docker run -d --name cliente2-lima --hostname cliente2-lima --network net_lan_lima --ip 172.32.1.3 --cap-add NET_ADMIN cliente

# 5. Habilitar reenvío de IP (ip_forward)
docker exec fw-cusco sysctl -w net.ipv4.ip_forward=1
docker exec router-central sysctl -w net.ipv4.ip_forward=1
docker exec fw-lima sysctl -w net.ipv4.ip_forward=1

# 6. Configuración de enrutamiento estático en los nodos
docker exec srv-web-cusco ip route replace default via 10.10.1.3
docker exec fw-cusco ip route replace default via 192.168.10.3
docker exec user1 ip route replace default via 192.168.10.3

docker exec router-central ip route replace 10.10.1.0/24 via 192.168.10.2
docker exec router-central ip route replace 172.31.1.0/24 via 192.168.20.4
docker exec router-central ip route replace 172.32.1.0/24 via 192.168.20.4

docker exec fw-lima ip route replace default via 192.168.20.3

docker exec srv-mysql-lima ip route replace default via 172.31.1.4
docker exec srv-ftp-lima ip route replace default via 172.31.1.4
docker exec cliente1-lima ip route replace default via 172.32.1.4
docker exec cliente2-lima ip route replace default via 172.32.1.4

# 7. Configuración de VPN IPsec (strongSwan)
# Iniciar IPsec (los archivos ya están copiados y con permisos 600 dentro de la imagen)
docker exec fw-cusco ipsec start
docker exec fw-lima ipsec start
# Esperar un momento a que inicien los demonios y establezcan el túnel automáticamente (auto=start)
sleep 5

# 8. Reglas de Firewall (Netfilter / iptables)
# --- Reglas de Firewall Cusco ---
docker exec fw-cusco iptables -F
docker exec fw-cusco iptables -X
docker exec fw-cusco iptables -P INPUT DROP
docker exec fw-cusco iptables -P FORWARD DROP
docker exec fw-cusco iptables -P OUTPUT ACCEPT

docker exec fw-cusco iptables -A INPUT -i lo -j ACCEPT
docker exec fw-cusco iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
docker exec fw-cusco iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Permitir IKE/ESP desde Firewall Lima para VPN IPsec
docker exec fw-cusco iptables -A INPUT -p udp -s 192.168.20.4 -m multiport --dports 500,4500 -j ACCEPT
docker exec fw-cusco iptables -A INPUT -p esp -s 192.168.20.4 -j ACCEPT

# Permitir ping al propio Firewall Cusco
docker exec fw-cusco iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# VPN: LAN Cusco -> DMZ Lima
docker exec fw-cusco iptables -A FORWARD -s 10.10.1.0/24 -d 172.31.1.0/24 -j ACCEPT

# VPN: LAN Lima -> Servidor Web Cusco (puertos 80, 443 y ping)
docker exec fw-cusco iptables -A FORWARD -s 172.32.1.0/24 -d 10.10.1.2 -p tcp -m multiport --dports 80,443 -j ACCEPT
docker exec fw-cusco iptables -A FORWARD -s 172.32.1.0/24 -d 10.10.1.2 -p icmp --icmp-type echo-request -j ACCEPT

# --- Reglas de Firewall Lima ---
docker exec fw-lima iptables -F
docker exec fw-lima iptables -X
docker exec fw-lima iptables -P INPUT DROP
docker exec fw-lima iptables -P FORWARD DROP
docker exec fw-lima iptables -P OUTPUT ACCEPT

docker exec fw-lima iptables -A INPUT -i lo -j ACCEPT
docker exec fw-lima iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
docker exec fw-lima iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Permitir IKE/ESP desde Firewall Cusco para VPN IPsec
docker exec fw-lima iptables -A INPUT -p udp -s 192.168.10.2 -m multiport --dports 500,4500 -j ACCEPT
docker exec fw-lima iptables -A INPUT -p esp -s 192.168.10.2 -j ACCEPT

# Permitir ping al propio Firewall Lima
docker exec fw-lima iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Regla 1: Conectividad total bidireccional LAN Lima <-> DMZ Lima
docker exec fw-lima iptables -A FORWARD -s 172.32.1.0/24 -d 172.31.1.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.31.1.0/24 -d 172.32.1.0/24 -j ACCEPT

# Regla 2: DMZ Lima <-> WAN (Solo el servidor FTP tiene acceso bidireccional)
docker exec fw-lima iptables -A FORWARD -s 172.31.1.3 -d 192.168.10.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.31.1.3 -d 192.168.20.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.10.0/24 -d 172.31.1.3 -p tcp --dport 21 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.10.0/24 -d 172.31.1.3 -p icmp --icmp-type echo-request -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.20.0/24 -d 172.31.1.3 -p tcp --dport 21 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.20.0/24 -d 172.31.1.3 -p icmp --icmp-type echo-request -j ACCEPT

# Regla 3: WAN <-> LAN Lima (Solo cliente1 tiene acceso de salida hacia la WAN)
docker exec fw-lima iptables -A FORWARD -s 172.32.1.2 -d 192.168.10.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.32.1.2 -d 192.168.20.0/24 -j ACCEPT

# Regla 4: Conectividad Cusco <-> Lima (VPN)
# Cusco LAN -> DMZ Lima
docker exec fw-lima iptables -A FORWARD -s 10.10.1.0/24 -d 172.31.1.0/24 -j ACCEPT
# LAN Lima -> Cusco Web Server (puertos 80, 443 y ping)
docker exec fw-lima iptables -A FORWARD -s 172.32.1.0/24 -d 10.10.1.2 -p tcp -m multiport --dports 80,443 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.32.1.0/24 -d 10.10.1.2 -p icmp --icmp-type echo-request -j ACCEPT
