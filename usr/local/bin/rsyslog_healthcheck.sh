#!/usr/bin/env bash
set -e

# Check that expected TCP ports are open
for p in 514 2514 6514 8514; do
  if ! lsof -i tcp:${p} -F c | grep rsyslogd; then
    exit 1;
  fi
done
# Check that crond process is running to support logrotate
if [ -z "$crond_pid_file" ]; then
  # Assume CentOS7 syslog 8 default
  crond_pid_file='/var/run/crond.pid'
fi
if ! [[ -e "$crond_pid_file" && -d "/proc/$(cat "$crond_pid_file")" ]]; then
  exit 1;
fi
# Check if the logrotate cron job script had errors
if [[ -e '/var/log/logrotate.err.log' ]]; then
  exit 1;
fi
