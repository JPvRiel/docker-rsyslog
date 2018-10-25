#!/usr/bin/env bash
c=2
m=100000
for p in 'none' 'tcp' 'udp'; do
    echo -e "\n# $p"
    ./nc_dummy_syslog_server.sh &
    echo "rsyslog started"
    /usr/bin/time -f "cpu_tot=%S cpu_usr=%U cpu_sys=%S max_res_mem=%M" rsyslogd -f rsyslog_minimal.conf -n -C -i /tmp/test_rsyslog_pid.txt &
    time_pid=$!
    SYSLOG_PROTO="$p" SYSLOG_PORT=20514 N_CLIENTS=$c N_MSG=$m ./nc_dummy_syslog_client.sh
    sleep 1
    kill -HUP "$(cat /tmp/test_rsyslog_pid.txt)"
    sleep 1
    kill -TERM "$(cat /tmp/test_rsyslog_pid.txt)"
    wait "$time_pid"
    echo "rsyslog exited"
    sleep 1
    killall nc
    wait
    echo "netcat processes exited"
    rm -f /tmp/test_rsyslog_pid.txt
    sleep 1
done