#!/bin/bash
set -e

# Apply config templates

# Do a config sanity check
if ! rsyslogd -N1; then
  echo "ERROR: Rsyslog configuration corrupt. Aborting." >&2
  exit 1
fi

# Allow arguments to be passed to rsyslog
if [[ -n ${1} ]]; then
  if [[ ${1:0:1} == '-' ]]; then
    EXTRA_ARGS="$@"
    set --
  elif [[ ${1} == rsyslogd ]]; then
    EXTRA_ARGS="${@:2}"
    set --
  fi
fi

# Default behaviour is to launch rsyslog
if [[ -z ${1} ]]; then
  rsyslogd -n
  rsyslogd -n ${EXTRA_ARGS}
else
  $@ &
fi

# Note, rsyslog command is to run in the forgroung, so hopefully no orphined defunct / 'zombie' processes should result. We don't wrap SIGHUP given rsyslog docs say a service restrart is better

# trap SIGINT or TERM signals and TERM children
trap "echo 'Terminating child processes'; kill -HUP $(cat /var/run/rsyslogd.pid) && sleep 1; [[ -z "$(jobs -p)" ]] || kill $(jobs -p)" 2 3 15

# wait on all children to exit gracefully
wait
echo "Exited gracefully"
