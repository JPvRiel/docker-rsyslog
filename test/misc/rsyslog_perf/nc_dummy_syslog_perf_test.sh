#!/usr/bin/env bash
c=2
m=100000
for p in 'none' 'tcp' 'udp'; do
    echo -e "\n# $p"
    /usr/bin/time -f "cpu_tot=%S cpu_usr=%U cpu_sys=%S max_res_mem=%M" ./nc_dummy_syslog_server.sh &
    SYSLOG_PROTO="$p" N_CLIENTS=$c N_MSG=$m ./nc_dummy_syslog_client.sh
    sleep 2
    killall nc
    wait
    sleep 2
done