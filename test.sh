#!/bin/sh

echo "=== 1) LAN Lima <-> DMZ Lima ==="

docker exec cliente1-lima ping -c 2 -W 2 172.31.1.2
docker exec cliente1-lima ping -c 2 -W 2 172.31.1.3
docker exec srv-mysql-lima ping -c 2 -W 2 172.32.1.2
docker exec srv-ftp-lima ping -c 2 -W 2 172.32.1.2
docker exec cliente1-lima nc -zv -w 2 172.31.1.3 21
docker exec cliente1-lima nc -zv -w 2 172.31.1.2 3306

echo "=== 2) DMZ Lima <-> WAN (probando contra la IP PÚBLICA de fw-lima: 192.168.20.4) ==="

echo "--- user1 hacia el FTP vía DNAT (debe responder) ---"
docker exec user1 ping -c 2 -W 2 192.168.20.4
docker exec user1 nc -zv -w 2 192.168.20.4 21

echo "--- user1 hacia MySQL: no existe DNAT para 3306, MySQL nunca queda expuesto (debe fallar) ---"
docker exec user1 nc -zv -w 2 192.168.20.4 3306

echo "--- Confirmando que las IPs privadas de la DMZ NO son alcanzables directamente desde la WAN (sin ruta pública hacia RFC1918) ---"
docker exec user1 ping -c 2 -W 2 172.31.1.3
docker exec user1 ping -c 2 -W 2 172.31.1.2

echo "--- Egreso DMZ -> WAN: solo el FTP tiene permiso (MySQL debe fallar) ---"
docker exec srv-ftp-lima ping -c 2 -W 2 192.168.10.3
docker exec srv-mysql-lima ping -c 2 -W 2 192.168.10.3

echo "=== 3) WAN <-> LAN Lima ==="

echo "--- Nadie desde la WAN puede llegar a la LAN privada de Lima (no hay DNAT hacia clientes) ---"
docker exec user1 ping -c 2 -W 2 172.32.1.2
docker exec user1 ping -c 2 -W 2 172.32.1.3

echo "--- Egreso LAN Lima -> WAN: solo cliente1 tiene permiso (cliente2 debe fallar) ---"
docker exec cliente1-lima ping -c 2 -W 2 192.168.10.3
docker exec cliente2-lima ping -c 2 -W 2 192.168.10.3

echo "--- Nota: con NAT/PAT correcto, ningún host de Lima puede iniciar un ping hacia user1 (192.168.100.2):"
echo "    user1 vive detrás de su propio router doméstico (router-usuario) y solo recibe tráfico de vuelta"
echo "    de conexiones que él mismo inició. Por eso ya no se prueba ping hacia user1 desde dentro de Lima."

echo "=== 4) Lima <-> Cusco (vía VPN IPsec, tráfico exceptuado del NAT) ==="

docker exec srv-web-cusco ping -c 2 -W 2 172.32.1.2
docker exec srv-web-cusco ping -c 2 -W 2 172.31.1.2
docker exec cliente1-lima ping -c 2 -W 2 10.10.1.2
docker exec cliente2-lima ping -c 2 -W 2 10.10.1.2
docker exec cliente1-lima nc -zv -w 2 10.10.1.2 80

echo "=== 5) Servidor Web Cusco expuesto a la WAN vía DNAT (IP pública fw-cusco: 192.168.10.2) ==="

docker exec user1 nc -zv -w 2 192.168.10.2 80
docker exec user1 nc -zv -w 2 192.168.10.2 443

echo "--- Confirmando que la IP privada del servidor web NO es alcanzable directamente desde la WAN (sin ruta) ---"
docker exec user1 ping -c 2 -W 2 10.10.1.2

echo "--- Certificado real vía ACME (Pebble), no autofirmado: emisor debe ser 'Pebble Intermediate CA', no 'O=Seguridad' ---"
docker exec srv-web-cusco sh -c "openssl s_client -connect localhost:443 -servername web-cusco.lab </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates"
docker exec user1 curl -sk -v https://192.168.10.2 -H "Host: web-cusco.lab" 2>&1 | grep -E "issuer:|HTTP/"

echo "=== 6) router-central (backbone) NO debe tener rutas a subredes privadas RFC1918 de Cusco/Lima ==="

docker exec router-central ip route show

echo "=== 7) Reglas NAT (SNAT/PAT y DNAT) ==="

echo "--- fw-cusco ---"
docker exec fw-cusco iptables -t nat -L -n -v
echo "--- fw-lima ---"
docker exec fw-lima iptables -t nat -L -n -v
echo "--- router-usuario (CPE doméstico de user1) ---"
docker exec router-usuario iptables -t nat -L -n -v

echo "=== Firewall Cusco (iptables filter) ==="
docker exec fw-cusco iptables -L -n -v

echo "=== Firewall Lima (iptables filter) ==="
docker exec fw-lima iptables -L -n -v
