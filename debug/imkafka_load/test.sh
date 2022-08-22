#!/usr/bin/env bash

set -e

image_list='ubuntu22 rocky8 alma8 redhat-ubi8 redhat-ubi7'

for i in $image_list; do
    echo -e "\n### Build and start container for $i"
    docker build -f "Dockerfile-$i" -t "jpvriel/rsyslog-kafka-debug:$i" . > /dev/null
    docker run -d --name "rsyslog-kafka-debug-$i" "jpvriel/rsyslog-kafka-debug:$i" > /dev/null
    echo -e "\n### Check for bug in docker logs for $i"
    if docker logs "rsyslog-kafka-debug-$i" 2>&1 | grep -F 'imkafka: error creating kafka handle: Failed to create thread: No such file or directory (2)'; then
        echo "*** BUG FOUND for $i! ***"
    else
        echo "*** no bug for $i! ***"
    fi
    echo "### Kill $i"
    docker kill "rsyslog-kafka-debug-$i" && sleep 1 && docker rm "rsyslog-kafka-debug-$i" > /dev/null
done
