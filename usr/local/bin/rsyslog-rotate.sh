#!/usr/bin/env bash
set -e

if [[ -z "$rsyslog_pid_file" ]]; then
  # Assume CentOS7 syslog 8 default
  rsyslog_pid_file='/var/run/syslogd.pid'
fi

# HUP signal sent to rsyslog to close all open files, flush buffers and open new files
kill -SIGHUP "$(cat "$rsyslog_pid_file")"
