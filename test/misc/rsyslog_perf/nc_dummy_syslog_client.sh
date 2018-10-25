#!/usr/bin/env bash

# Number of messages
n_msg=1000
if [ -n "$N_MSG" ]; then
    n_msg="$N_MSG"
fi

# Number of clients
n_clients=1
if [ -n "$N_CLIENTS" ]; then
    n_clients="$N_CLIENTS"
fi

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

# Syslog protocol
syslog_proto='udp'
output_cmd="nc ${syslog_server} ${syslog_port}"
if [ -n "$SYSLOG_PROTO" ]; then
    case "$SYSLOG_PROTO" in
        'tcp')
            #default
            syslog_proto='tcp'
            ;;
        'udp')
            syslog_proto='udp'
            output_cmd="nc -q 1 -u ${syslog_server} ${syslog_port}"
            ;;
        'none')
            output_cmd="cat > /dev/null"
            ;;
        *)
            echo "ERROR: SYSLOG_PROTO='$SYSLOG_PROTO'. Expects only 'none', 'tcp' or 'udp'" 2>&1
            exit 1
            ;;
    esac
fi

# Use debug severity and user faciltiy
syslog_severity=7
syslog_facility=1
syslog_priority=$((syslog_facility * 8 + syslog_severity))
hostname=$(hostname)
app_name=$(basename "$0")

for ((c=1; c<=n_clients; c++)); do
    {
        # Message identity
        c_pid=$BASHPID
        # Signal message start
        t_start=$(date --iso-8601=ns)
        syslog_header="<$syslog_priority>1 $t_start $hostname $app_name $c_pid"     
        printf "%s - [syslog_perf_test_start client_num=\"%03i\" proto=\"%s\"] performance test start\n" \
            "$syslog_header" $c "$syslog_proto"
        # Reuse header and t_start in the message loop to avoid the cost of date subshell calls
        for ((i=1; i<=n_msg; i++)); do
            printf "%s %03i-%09i [syslog_perf_test_msg client_num=\"%03i\" msg_num=\"%09i\"] performance test message\n" \
                "$syslog_header" $c $i $c $i
        done
        # Signal message end
        t_end=$(date --iso-8601=ns)
        syslog_header="<$syslog_priority>1 $t_end $hostname $app_name $c_pid"
        printf "%s - [syslog_perf_test_end client_num=\"%03i\" proto=\"%s\"] performance test end\n" \
            "$syslog_header" $c "$syslog_proto"
    } | eval "$output_cmd" &
done

echo "Waiting for message spool test with $n_msg message(s) from $n_clients client(s) to complete"
wait
echo "Done!"
