#!/usr/bin/env bash

set -e

for i in rocky8 ubuntu22; do
    echo "### Build and start container for $i"
    docker build -f "Dockerfile-$i" -t "jpvriel/rsyslog-kafka-debug:$i" .
    docker run -d --rm --name "rsyslog-kafka-debug-$i" "jpvriel/rsyslog-kafka-debug:$i"
done

for i in rocky8 ubuntu22; do
    echo "### Check for bug in docker logs for $i"
    docker logs "rsyslog-kafka-debug-$i" | grep 'imkafka: error creating kafka handle: Failed to create thread: No such file or directory (2)'
    echo "### Kill $i"
    docker kill "rsyslog-kafka-debug-$i"
done
