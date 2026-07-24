#!/bin/sh

docker rm -f srv-web-cusco fw-cusco user1 router-usuario router-central fw-lima srv-mysql-lima srv-ftp-lima cliente1-lima cliente2-lima pebble pebble-challtestsrv 2>/dev/null || true
docker network rm net_lan_cusco net_wan_cusco net_home_user1 net_wan_lima net_dmz_lima net_lan_lima net_cusco_lan net_cusco_wan net_lima_lan net_lima_wan 2>/dev/null || true
