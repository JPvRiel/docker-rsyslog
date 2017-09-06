#!/usr/bin/env bash
set -e
# check that expected TCP ports are open
for p in 514 2514 6514 8514; do
  if ! lsof -i tcp:${p} -F c | grep rsyslogd; then
    exit 1;
  fi
done
