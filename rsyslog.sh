#!/bin/bash
set -e
[ "$DEBUG" == 'true' ] && export RSYSLOG_DEBUG=DebugOnDemand && set -x

# Setup hanlder functions and traps to pass on signals to the rsyslog process
function sigterm_handler() {
  rsyslog_pid=$(cat /var/run/rsyslogd.pid)
  echo 'INFO: Terminating rsyslog process.'
  kill -SIGTERM "$rsyslog_pid"
  wait "$rsyslog_pid"
  rsyslog_exit_status=$?
  if [ $rsyslog_exit_status -eq 0 ]; then
    echo 'INFO: rsyslog stopped normally.'
  else
    echo "ERROR: rsyslog stopped abnormally! Exit code = $rsyslog_exit_status." >&2
  fi
  exit $rsyslog_exit_status
}

function sighup_handler() {
  # This is typically only needed for log rotate
  echo 'INFO: Instructing rsyslog to close all open files.'
  kill -SIGHUP "$(cat /var/run/rsyslogd.pid)"
}

function sigusr1_handler() {
  echo 'INFO: Toggle rsyslog debug if enabled (won'\''t work if rsyslog started without debug switch)'
  kill -SIGUSR1 "$(cat /var/run/rsyslogd.pid)"
}

trap 'sigterm_handler' SIGTERM SIGINT SIGQUIT
trap 'sighup_handler' SIGHUP
trap 'sigusr1_handler' SIGUSR1

# Apply config templates
/usr/local/bin/confd -onetime -backend env -log-level warn

# Check TLS
if ! ([ -f '/etc/pki/rsyslog/key.pem' ] || [ -f '/etc/tls/rsyslog/cert.pem' ]); then
  echo "WARNING: TLS certficates not found in /etc/pki/rsyslog. Linking to default self-signed certficates, but secure syslog services cannot function properly without a common trusted CA and CA signed server certficates." >&2
  ln -s /etc/pki/tls/private/default_self_signed.key.pem /etc/pki/rsyslog/key.pem
  ln -s /etc/pki/tls/certs/default_self_signed.cert.pem /etc/pki/rsyslog/cert.pem
fi

# Do a config sanity check
if ! rsyslogd -N1; then
  echo "ERROR: Rsyslog configuration corrupt! Aborting." >&2
  exit 1
fi

# Run rsyslog in the background
# - We can't simply exec rsyslog because of the zombie PID 1 reping problem...
if [[ -n "${1}" ]]; then
  # Allow arguments to be passed to rsyslog
  if [[ "${1:0:1}" == '-' ]]; then
    echo 'INFO: Running rsyslogd with extra arguments.'
    EXTRA_ARGS=( "$@" )
    rsyslogd -n "${EXTRA_ARGS[@]}" 1>> /dev/stdout 2>> /dev/stderr &
  elif [[ "${1}" == rsyslogd || "${1}" == /usr/sbin/rsyslogd ]]; then
    echo 'INFO: Running custom rsyslogd command and arguments.'
    EXTRA_ARGS=( "${@:2}" )
    rsyslogd -n "${EXTRA_ARGS[@]}" 1>> /dev/stdout 2>> /dev/stderr &
  else
    echo 'INFO: Custom command run (in foreground).'
    "$@"
    exit $!
  fi
else
  echo 'INFO: Running rsyslogd.'
  rsyslogd -n 1>> /dev/stdout 2>> /dev/stderr &
fi
pid=$!

# Notes:
# - Hopefully no orphined defunct / 'zombie' processes should result when rsylog terminates as per sigterm_handlers above.
# - Just in case, wait again in case rsyslog managed to spawn child processes, given pid 1 is meat to reap all children.
# - Waiting in a loop is necessairy becuse traping SIGUSR1 or SIGINT for rsyslog causes wait to return with and exit code >= 128
# - When wait returns with a non-zero exit code due to async signal hanlding, it needs to be wrapped in set +e, or else this script terminates due to set -e
set +e
while [ -e /proc/$pid ]; do
  wait $pid
done
set -e
trap - SIGTERM SIGINT SIGQUIT
wait
# If not trapped by a signal handler above, report an error.
echo "ERROR: Ungraceful exit - rsyslog died! Exit code = $?." >&2
