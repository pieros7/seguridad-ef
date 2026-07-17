#!/bin/sh

echo "=== 1) LAN Lima <-> DMZ Lima ==="

docker exec cliente1-lima ping -c 2 -W 2 172.31.1.2
docker exec cliente1-lima ping -c 2 -W 2 172.31.1.3
docker exec srv-mysql-lima ping -c 2 -W 2 172.32.1.2
docker exec srv-ftp-lima ping -c 2 -W 2 172.32.1.2
docker exec cliente1-lima nc -zv -w 2 172.31.1.3 21
docker exec cliente1-lima nc -zv -w 2 172.31.1.2 3306

echo "=== 2) DMZ Lima <-> WAN ==="

docker exec user1 ping -c 2 -W 2 172.31.1.3
docker exec user1 ping -c 2 -W 2 172.31.1.2
docker exec srv-ftp-lima ping -c 2 -W 2 192.168.10.4
docker exec srv-mysql-lima ping -c 2 -W 2 192.168.10.4
docker exec user1 nc -zv -w 2 172.31.1.3 21
docker exec user1 nc -zv -w 2 172.31.1.2 3306

echo "=== 3) WAN <-> LAN Lima ==="

docker exec user1 ping -c 2 -W 2 172.32.1.2
docker exec user1 ping -c 2 -W 2 172.32.1.3
docker exec cliente1-lima ping -c 2 -W 2 192.168.10.4
docker exec cliente2-lima ping -c 2 -W 2 192.168.10.4

echo "=== 4) Lima <-> Cusco ==="

docker exec srv-web-cusco ping -c 2 -W 2 172.32.1.2
docker exec srv-web-cusco ping -c 2 -W 2 172.31.1.2
docker exec cliente1-lima ping -c 2 -W 2 10.10.1.2
docker exec cliente2-lima ping -c 2 -W 2 10.10.1.2
docker exec cliente1-lima nc -zv -w 2 10.10.1.2 80

echo "=== Firewall Cusco (iptables) ==="
docker exec fw-cusco iptables -L -n -v

echo "=== Firewall Lima (iptables) ==="
docker exec fw-lima iptables -L -n -v
