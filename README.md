# Seguridad EF — Topología Cusco/Lima con NAT, VPN IPsec y Firewalls

Laboratorio con Docker que simula dos sedes (Cusco y Lima) unidas por una VPN
IPsec, cada una detrás de su propio firewall con NAT/PAT (Overload), DNAT para
publicar servicios, y un cliente externo (`user1`) detrás de su propio router
doméstico con NAT.

## 0. Requisitos (VM de GCP)

Instalar Docker Engine (no hace falta Docker Desktop, la VM de GCP corre Linux nativo):

```sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Para no tener que usar sudo en cada comando docker
sudo usermod -aG docker $USER
newgrp docker

docker --version
```

## 1. Obtener el proyecto en la VM

```sh
git clone https://github.com/pieros7/seguridad-ef.git
cd seguridad-ef
chmod +x start.sh test.sh clean.sh purge.sh
```

## 2. Levantar toda la topología

Crea las redes, construye las imágenes, despliega los 10 contenedores,
configura rutas estáticas, levanta el túnel IPsec y aplica las reglas de
iptables (filtrado + NAT) en ambos firewalls y en `router-usuario`.

```sh
bash start.sh
```

Verificar que los 10 contenedores estén `Up`:

```sh
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

Verificar que el túnel VPN quedó establecido:

```sh
docker exec fw-cusco ipsec status
docker exec fw-lima ipsec status
```

## 3. Correr toda la batería de pruebas

```sh
bash test.sh
```

Recorre 7 bloques: LAN↔DMZ Lima, DMZ↔WAN (FTP vía DNAT / MySQL oculto),
WAN↔LAN Lima, VPN Lima↔Cusco, Web Cusco vía DNAT, rutas de `router-central`
y las tablas NAT/filter completas de ambos firewalls.

## 4. Pruebas puntuales (para sustentar en vivo)

### Tabla de ruteo (en Linux es `ip route`, no `ipconfig`)

```sh
docker exec router-central ip route show
docker exec fw-cusco ip route show
docker exec fw-lima ip route show
docker exec router-usuario ip route show
```

### Reglas de filtrado (iptables)

```sh
docker exec fw-cusco iptables -L -n -v
docker exec fw-lima iptables -L -n -v
```

### Reglas NAT (SNAT/PAT y DNAT)

```sh
docker exec fw-cusco iptables -t nat -L -n -v
docker exec fw-lima iptables -t nat -L -n -v
docker exec router-usuario iptables -t nat -L -n -v
```

### Estado de la VPN IPsec

```sh
docker exec fw-cusco ipsec status
docker exec fw-lima ipsec status
```

### Acceso público a los servicios expuestos (vía DNAT)

```sh
# Web server de Cusco por la IP pública del firewall (192.168.10.2)
docker exec user1 nc -zv 192.168.10.2 80
docker exec user1 nc -zv 192.168.10.2 443

# FTP de Lima por la IP pública del firewall (192.168.20.4)
docker exec user1 nc -zv 192.168.20.4 21
```

### Confirmar que las IPs privadas NO son alcanzables desde la WAN

```sh
docker exec user1 ping -c 2 10.10.1.2     # servidor web, IP privada -> debe fallar
docker exec user1 ping -c 2 172.31.1.3    # FTP, IP privada -> debe fallar
docker exec user1 nc -zv -w 2 192.168.20.4 3306   # MySQL: sin DNAT -> debe fallar
```

### Conectividad interna Lima (LAN↔DMZ) y VPN (Lima↔Cusco)

```sh
docker exec cliente1-lima ping -c 2 172.31.1.3
docker exec cliente1-lima nc -zv 172.31.1.3 21
docker exec cliente1-lima ping -c 2 10.10.1.2
docker exec cliente1-lima nc -zv 10.10.1.2 80
```

### Certificado TLS real (Let's Encrypt / ACME vía Pebble, no autofirmado)

El servidor web ya no usa un certificado autofirmado. `start.sh` emite un
certificado real con `certbot` usando el protocolo ACME (HTTP-01) contra
**Pebble**, el CA de prueba oficial de Let's Encrypt — mismo protocolo que el
Let's Encrypt real, sin depender de un dominio público ni de internet. El
dominio de prueba es `web-cusco.lab`, resuelto internamente por
`pebble-challtestsrv`.

```sh
# Ver el certificado que sirve nginx: el emisor debe ser "Pebble Intermediate CA",
# no "O=Seguridad" (que era el autofirmado anterior)
docker exec srv-web-cusco sh -c \
  "openssl s_client -connect localhost:443 -servername web-cusco.lab </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates"

# Confirmar que se ve igual a través del DNAT público del firewall
docker exec user1 curl -sk -v https://192.168.10.2 -H "Host: web-cusco.lab" 2>&1 | grep -E "issuer:|HTTP/"
```

**¿Por qué no un Let's Encrypt real de verdad?** El reto ACME (HTTP-01/DNS-01)
exige que los servidores reales de Let's Encrypt alcancen tu dominio por
internet. Eso solo es posible si corres esto en la VM de GCP con una IP
pública real y un dominio propio apuntándole (abriendo 80/443 al internet
real) — algo que no aplica en este laboratorio de práctica. Pebble usa
exactamente el mismo protocolo y el mismo flujo de `certbot`, así que
demuestra el mecanismo real sin esa exposición.

## 5. Limpieza

```sh
bash clean.sh   # borra contenedores y redes (conserva las imágenes ya construidas)
bash purge.sh   # además borra las imágenes y hace docker volume prune
```

## Topología (resumen de IPs)

| Zona | Host | IP |
|---|---|---|
| Cusco LAN | srv-web-cusco | 10.10.1.2 |
| Cusco LAN | pebble (CA de prueba ACME) | DNS interno |
| Cusco LAN | pebble-challtestsrv (DNS falso) | DNS interno |
| Cusco LAN | fw-cusco (LAN) | 10.10.1.3 |
| Cusco WAN | fw-cusco (WAN / pública) | 192.168.10.2 |
| Backbone | router-central | 192.168.10.3 / 192.168.20.3 |
| Backbone | router-usuario (WAN) | 192.168.10.5 |
| Home user1 | router-usuario (home) | 192.168.100.1 |
| Home user1 | user1 | 192.168.100.2 |
| Lima WAN | fw-lima (WAN / pública) | 192.168.20.4 |
| Lima DMZ | fw-lima (DMZ) | 172.31.1.4 |
| Lima DMZ | srv-mysql-lima | 172.31.1.2 |
| Lima DMZ | srv-ftp-lima | 172.31.1.3 |
| Lima LAN | fw-lima (LAN) | 172.32.1.4 |
| Lima LAN | cliente1-lima | 172.32.1.2 |
| Lima LAN | cliente2-lima | 172.32.1.3 |

## Prompt para actualizar el diagrama de topología (IA de imágenes)

El diagrama original del enunciado tiene un solo router y `user1` colgado
directo de `192.168.10.0/24`. Este prompt describe los cambios para reflejar
el rediseño con NAT/PAT, DNAT y `router-usuario` — pégalo en la IA de
imágenes junto con la imagen original del enunciado como referencia:

```
Recrea este mismo diagrama de topología de red (mismo estilo: iconos de
servidor, firewall como muro de ladrillos, router como cilindro azul con
flechas, PCs, nubes de zona con colores pastel, flechas grises de doble
punta para conexiones, flecha verde gruesa para "VPN - IPsec"), manteniendo
exactamente las tres zonas CUSCO (celeste), LIMA (rosa/amarillo con DMZ) y
la leyenda inferior, pero con estos cambios en la zona WAN/INTERNET central:

1. Agregar un segundo router entre user1 y el router central, etiquetado
   "Router Usuario (CPE doméstico)", dibujado más pequeño, a la izquierda
   de user1.
2. Nueva subred aislada para user1, en un recuadro propio etiquetado
   "RED HOGAR USER1 — 192.168.100.0/24", separada de la nube "INTERNET".
3. Las IPs del nuevo segmento:
   - router-usuario, lado WAN (hacia el router central): 192.168.10.5/24
   - router-usuario, lado LAN (hacia user1): 192.168.100.1/24
   - user1: 192.168.100.2/24 (ya no 192.168.10.4)
4. Sobre la flecha entre router-usuario y el router central, agregar la
   etiqueta pequeña "NAT/PAT" (indicando que el router doméstico traduce
   la IP privada de user1 a su propia IP pública).
5. Sobre las flechas que salen de cada Firewall (Cusco y Lima) hacia la
   nube INTERNET, agregar también la etiqueta "NAT/PAT + DNAT" en letra
   pequeña junto a las IPs 192.168.10.2/24 y 192.168.20.4/24, indicando
   que cada firewall hace NAT de salida y publica sus servicios (80/443
   en Cusco, 21 en Lima) mediante DNAT.
6. El router central mantiene sus IPs 192.168.10.3/24 y 192.168.20.3/24
   sin cambios, pero se puede agregar debajo un texto pequeño: "Sin rutas
   a redes privadas RFC1918".
7. Todo lo demás (Servidor Web, Firewall Cusco, VPN, DMZ Lima con
   MySQL/FTP, LAN Lima con cliente1/cliente2) queda igual al diagrama
   original.
```
