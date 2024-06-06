#!/usr/bin/env bash
set -e

# Check that expected TCP ports are open
for p in u:514 t:601 t:2514 t:6514 t:8514; do
  proto=${p%%:*}
  port=${p#*:}
  # switch statment for u (UDP) or t (TCP)
  case $proto in
    u)
      if ! ss --listening --processes --numeric --udp "sport = $port"| grep --quiet --fixed-strings rsyslogd; then
        exit 1;
      fi
      ;;
    t)
      if ! ss --listening --processes --numeric --tcp "sport = $port" | grep --quiet --fixed-strings rsyslogd; then
        exit 1;
      fi
      ;;
    *)
      exit 1;
      ;;
  esac
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
