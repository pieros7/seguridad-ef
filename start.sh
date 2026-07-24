#!/bin/sh

# Evita que Git Bash (MSYS) reescriba argumentos tipo "/etc/..." como rutas de Windows
# al pasarlos a docker.exe (no tiene efecto en Linux/GCP).
export MSYS_NO_PATHCONV=1

# 1. Limpieza de contenedores y redes existentes
docker rm -f srv-web-cusco fw-cusco user1 router-usuario router-central fw-lima srv-mysql-lima srv-ftp-lima cliente1-lima cliente2-lima pebble pebble-challtestsrv 2>/dev/null || true
docker network rm net_lan_cusco net_wan_cusco net_home_user1 net_wan_lima net_dmz_lima net_lan_lima net_cusco_lan net_cusco_wan net_lima_lan net_lima_wan 2>/dev/null || true

# 2. Creación de redes personalizadas con sus subredes
# enable_ip_masquerade=false: el NAT real lo hacen nuestros propios firewalls/routers
# (dentro de los contenedores). Sin esto, Docker aplica su propio MASQUERADE por-red a
# nivel de host y le hace "hairpin NAT" al tráfico que un contenedor-router reenvía entre
# dos redes bridge distintas, reescribiendo el origen antes de que lo vean nuestras reglas.
docker network create --subnet=10.10.1.0/24 --opt com.docker.network.bridge.enable_ip_masquerade=false net_lan_cusco
docker network create --subnet=192.168.10.0/24 --opt com.docker.network.bridge.enable_ip_masquerade=false net_wan_cusco
docker network create --subnet=192.168.100.0/24 --gateway=192.168.100.254 --opt com.docker.network.bridge.enable_ip_masquerade=false net_home_user1
docker network create --subnet=192.168.20.0/24 --opt com.docker.network.bridge.enable_ip_masquerade=false net_wan_lima
docker network create --subnet=172.31.1.0/24 --opt com.docker.network.bridge.enable_ip_masquerade=false net_dmz_lima
docker network create --subnet=172.32.1.0/24 --opt com.docker.network.bridge.enable_ip_masquerade=false net_lan_lima

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
docker run -d --name srv-web-cusco --hostname srv-web-cusco --network net_lan_cusco --ip 10.10.1.2 --cap-add NET_ADMIN --sysctl net.ipv6.conf.all.disable_ipv6=1 web
docker run -d --name fw-cusco --hostname fw-cusco --network net_lan_cusco --ip 10.10.1.3 --privileged --sysctl net.ipv6.conf.all.disable_ipv6=1 firewall-cusco
docker network connect --ip 192.168.10.2 net_wan_cusco fw-cusco

# Pebble: CA de prueba oficial de Let's Encrypt (mismo protocolo ACME real,
# sin depender de internet ni de un dominio público). Vive en la misma LAN
# que el servidor web solo para la emisión del certificado; no participa del
# filtrado/NAT que se está evaluando.
docker run -d --name pebble-challtestsrv --hostname pebble-challtestsrv --network net_lan_cusco ghcr.io/letsencrypt/pebble-challtestsrv -defaultIPv6 "" -defaultIPv4 10.10.1.2
# httpPort=80 en la config de Pebble: por defecto Pebble valida HTTP-01 contra el
# puerto 5002 (pensado para su propio mock de pruebas). Como acá validamos contra
# el nginx real, se sobreescribe la config para que valide contra el puerto 80.
docker create --name pebble --hostname pebble --network net_lan_cusco -e PEBBLE_VA_NOSLEEP=1 ghcr.io/letsencrypt/pebble -config /test/config/pebble-config.json -dnsserver pebble-challtestsrv:8053
docker cp dockerfiles/pebble/pebble-config.json pebble:/test/config/pebble-config.json
docker start pebble

# Zona WAN troncal ("Internet" / backbone entre Cusco y Lima)
docker run -d --name router-central --hostname router-central --network net_wan_cusco --ip 192.168.10.3 --privileged --sysctl net.ipv6.conf.all.disable_ipv6=1 router
docker network connect --ip 192.168.20.3 net_wan_lima router-central

# Zona usuario externo (user1 detrás de su propio router/CPE con NAT, no colgado del backbone)
docker run -d --name router-usuario --hostname router-usuario --network net_wan_cusco --ip 192.168.10.5 --privileged --sysctl net.ipv6.conf.all.disable_ipv6=1 router
docker network connect --ip 192.168.100.1 net_home_user1 router-usuario
docker run -d --name user1 --hostname user1 --network net_home_user1 --ip 192.168.100.2 --cap-add NET_ADMIN --sysctl net.ipv6.conf.all.disable_ipv6=1 cliente

# Zona Lima
docker run -d --name fw-lima --hostname fw-lima --network net_wan_lima --ip 192.168.20.4 --privileged --sysctl net.ipv6.conf.all.disable_ipv6=1 firewall-lima
docker network connect --ip 172.31.1.4 net_dmz_lima fw-lima
docker network connect --ip 172.32.1.4 net_lan_lima fw-lima

docker run -d --name srv-mysql-lima --hostname srv-mysql-lima --network net_dmz_lima --ip 172.31.1.2 --cap-add NET_ADMIN --sysctl net.ipv6.conf.all.disable_ipv6=1 -e MARIADB_ROOT_PASSWORD=RootSecure2026 -e MARIADB_DATABASE=seguridad_db -e MARIADB_USER=seguridad_user -e MARIADB_PASSWORD=SecurePass2026 mysql
docker run -d --name srv-ftp-lima --hostname srv-ftp-lima --network net_dmz_lima --ip 172.31.1.3 --cap-add NET_ADMIN --sysctl net.ipv6.conf.all.disable_ipv6=1 ftp
docker run -d --name cliente1-lima --hostname cliente1-lima --network net_lan_lima --ip 172.32.1.2 --cap-add NET_ADMIN --sysctl net.ipv6.conf.all.disable_ipv6=1 cliente
docker run -d --name cliente2-lima --hostname cliente2-lima --network net_lan_lima --ip 172.32.1.3 --cap-add NET_ADMIN --sysctl net.ipv6.conf.all.disable_ipv6=1 cliente

# 5. Habilitar reenvío de IP (ip_forward)
docker exec fw-cusco sysctl -w net.ipv4.ip_forward=1
docker exec router-central sysctl -w net.ipv4.ip_forward=1
docker exec router-usuario sysctl -w net.ipv4.ip_forward=1
docker exec fw-lima sysctl -w net.ipv4.ip_forward=1

# 6. Configuración de enrutamiento estático en los nodos
docker exec srv-web-cusco ip route replace default via 10.10.1.3
docker exec fw-cusco ip route replace default via 192.168.10.3

# router-central es el backbone: NO conoce ni rutea hacia direccionamiento
# privado (RFC1918) de las organizaciones (10.10.1.0/24, 172.31.1.0/24,
# 172.32.1.0/24). Cada firewall hace NAT/PAT hacia su propia IP WAN
# (192.168.10.2 y 192.168.20.4), que sí son redes conectadas del backbone.
# No se agregan rutas estáticas adicionales en router-central.

# router-usuario actúa como router doméstico/CPE de user1: NAT hacia el backbone
docker exec router-usuario ip route replace default via 192.168.10.3
docker exec user1 ip route replace default via 192.168.100.1

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
docker exec fw-cusco iptables -t nat -F
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

# WAN pública -> Servidor Web Cusco, vía DNAT a la IP pública del firewall (puertos 80, 443)
docker exec fw-cusco iptables -A FORWARD -i eth1 -d 10.10.1.2 -p tcp -m multiport --dports 80,443 -j ACCEPT

# --- NAT en Firewall Cusco (PAT/Overload en la interfaz WAN eth1 = 192.168.10.2) ---
# Excluir del NAT el tráfico que va cifrado por el túnel IPsec hacia Lima
docker exec fw-cusco iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -d 172.31.1.0/24 -j ACCEPT
docker exec fw-cusco iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -d 172.32.1.0/24 -j ACCEPT
# PAT (NAPT/Overload) para el resto del tráfico de la LAN Cusco hacia la WAN
docker exec fw-cusco iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -o eth1 -j MASQUERADE
# DNAT: expone el Servidor Web (80/443) a través de la IP pública del firewall
docker exec fw-cusco iptables -t nat -A PREROUTING -i eth1 -p tcp -m multiport --dports 80,443 -j DNAT --to-destination 10.10.1.2

# --- Reglas de Firewall Lima ---
docker exec fw-lima iptables -F
docker exec fw-lima iptables -X
docker exec fw-lima iptables -t nat -F
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

# Regla 2: DMZ Lima <-> WAN (Solo el servidor FTP tiene acceso bidireccional, vía DNAT/PAT)
docker exec fw-lima iptables -A FORWARD -s 172.31.1.3 -d 192.168.10.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.31.1.3 -d 192.168.20.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.10.0/24 -d 172.31.1.3 -p tcp --dport 21 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.10.0/24 -d 172.31.1.3 -p icmp --icmp-type echo-request -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.20.0/24 -d 172.31.1.3 -p tcp --dport 21 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 192.168.20.0/24 -d 172.31.1.3 -p icmp --icmp-type echo-request -j ACCEPT

# Regla 3: WAN <-> LAN Lima (Solo cliente1 tiene acceso de salida hacia la WAN, vía PAT)
docker exec fw-lima iptables -A FORWARD -s 172.32.1.2 -d 192.168.10.0/24 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.32.1.2 -d 192.168.20.0/24 -j ACCEPT

# Regla 4: Conectividad Cusco <-> Lima (VPN)
# Cusco LAN -> DMZ Lima
docker exec fw-lima iptables -A FORWARD -s 10.10.1.0/24 -d 172.31.1.0/24 -j ACCEPT
# LAN Lima -> Cusco Web Server (puertos 80, 443 y ping)
docker exec fw-lima iptables -A FORWARD -s 172.32.1.0/24 -d 10.10.1.2 -p tcp -m multiport --dports 80,443 -j ACCEPT
docker exec fw-lima iptables -A FORWARD -s 172.32.1.0/24 -d 10.10.1.2 -p icmp --icmp-type echo-request -j ACCEPT

# --- NAT en Firewall Lima (PAT en la interfaz WAN eth0 = 192.168.20.4) ---
# Excluir del NAT el tráfico que va cifrado por el túnel IPsec hacia Cusco
docker exec fw-lima iptables -t nat -A POSTROUTING -s 172.31.1.0/24 -d 10.10.1.0/24 -j ACCEPT
docker exec fw-lima iptables -t nat -A POSTROUTING -s 172.32.1.0/24 -d 10.10.1.0/24 -j ACCEPT
# PAT solo para los hosts a los que el filtrado ya les permite salir a la WAN
docker exec fw-lima iptables -t nat -A POSTROUTING -s 172.31.1.3 -o eth0 -j MASQUERADE
docker exec fw-lima iptables -t nat -A POSTROUTING -s 172.32.1.2 -o eth0 -j MASQUERADE
# DNAT: expone el Servidor FTP (puerto 21) a través de la IP pública del firewall.
# No se hace DNAT de ICMP: bajo PAT puro no hay "puerto" para distinguir a qué host
# interno dirigir un ping; el firewall responde el ping en su propia IP pública
# (regla de INPUT) y solo el puerto explícitamente redirigido expone el servicio real.
docker exec fw-lima iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 21 -j DNAT --to-destination 172.31.1.3

# --- NAT en router-usuario (CPE doméstico de user1, PAT en la interfaz WAN eth0 = 192.168.10.5) ---
docker exec router-usuario iptables -t nat -F
docker exec router-usuario iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o eth0 -j MASQUERADE

# 9. Certificado real vía Let's Encrypt (ACME) usando Pebble como CA de prueba
# Esperar a que Pebble levante su directorio ACME (https://pebble:14000/dir)
sleep 3

# Confiar en la CA raíz de prueba de Pebble para que certbot valide la conexión TLS al ACME server
PEBBLE_CA_TMP="$(mktemp)"
docker cp pebble:/test/certs/pebble.minica.pem "$PEBBLE_CA_TMP"
docker cp "$PEBBLE_CA_TMP" srv-web-cusco:/etc/pebble.minica.pem
rm -f "$PEBBLE_CA_TMP"

# Emitir el certificado real (protocolo ACME, validación HTTP-01) para web-cusco.lab
docker exec -e REQUESTS_CA_BUNDLE=/etc/pebble.minica.pem srv-web-cusco certbot certonly \
  --webroot -w /usr/share/nginx/html \
  -d web-cusco.lab \
  --server https://pebble:14000/dir \
  --non-interactive --agree-tos -m admin@web-cusco.lab --no-eff-email

# Apuntar nginx al certificado emitido por Pebble y recargar
docker exec srv-web-cusco sed -i \
  -e 's#ssl_certificate /etc/nginx/ssl/nginx.crt;#ssl_certificate /etc/letsencrypt/live/web-cusco.lab/fullchain.pem;#' \
  -e 's#ssl_certificate_key /etc/nginx/ssl/nginx.key;#ssl_certificate_key /etc/letsencrypt/live/web-cusco.lab/privkey.pem;#' \
  /etc/nginx/conf.d/default.conf
docker exec srv-web-cusco nginx -s reload
