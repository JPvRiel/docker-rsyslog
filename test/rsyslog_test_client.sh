#!/usr/bin/env bash
set -e
[ "$DEBUG" == 'true' ] && export RSYSLOG_DEBUG=DebugOnDemand && set -x

# Do a config sanity check
if ! rsyslogd -N1; then
  echo 'Rsyslog configuration corrupt! Aborting.' >&2
  exit 1
fi

# Run rsyslog in the background
rsyslogd -n &
# While /var/run/rsyslogd.pid is createded by rsyslog, the pid file might not be avialbe to read by the time wait is reached.
rsyslog_pid="$!"

# In case the container is stopped before completing processing
trap 'kill $rsyslog_pid' SIGTERM SIGINT SIGQUIT

# Allow rsyslog some time to startup and listen on /dev/log
sleep 1

if [[ -n "${1}" ]]; then
  # Allow arguments to be passed to rsyslog
  if [[ "${1:0:1}" == '-' ]]; then
    # Running logger with extra arguments
    EXTRA_ARGS=( "$@" )
    logger "${EXTRA_ARGS[@]}"
  elif [[ "${1}" == logger || "${1}" == /usr/bin/logger ]]; then
    # Running custom logger command and arguments
    EXTRA_ARGS=( "${@:2}" )
    logger "${EXTRA_ARGS[@]}"
  else
    # Running custom command
    "$@"
    exit $!
  fi
else
  echo 'Sending client test message'
  message="Syslog client test message. $(grep -oP '(?<=PRETTY_NAME=")[^"]+(?=")' /etc/os-release) was running $(rsyslogd -v | grep -oP '^rsyslogd [0-9.]+')"
  logger --id "$message"
fi

wait
