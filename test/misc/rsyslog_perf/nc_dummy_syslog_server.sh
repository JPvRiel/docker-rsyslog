#!/usr/bin/env bash
# A simple psudo syslog listener on UDP and TCP

# Syslog server
syslog_server='localhost'
if [ -n "$SYSLOG_SERVER" ]; then
    syslog_server="$SYSLOG_SERVER"
fi

# Syslog port
syslog_port=10514
if [ -n "$SYSLOG_PORT" ]; then
    syslog_port="$SYSLOG_PORT"
fi

trap 'echo "closing netcat listeners on TCP (PID=${nc_tcp_pid}) and UDP (PID=${nc_udp_pid})"; kill -TERM $nc_tcp_pid $nc_udp_pid' TERM INT

# Note:
# - $(jobs -p) with -p means "List only the process ID of the job’s process group leader" (nc)
# - $! would get the pid of wc process which is not what we want to kill after a signal trap
nc -d -l -k "$syslog_server" "$syslog_port" | tee tcp.txt | wc -l | echo "tcp=$(cat)" &
nc_tcp_pid=$(jobs -p %1)
nc -d -u -l -k "$syslog_server" "$syslog_port" | tee udp.txt | wc -l | echo "udp=$(cat)" &
nc_udp_pid=$(jobs -p %2)
echo "started netcat syslog listener"

wait "$nc_tcp_pid" "$nc_udp_pid"