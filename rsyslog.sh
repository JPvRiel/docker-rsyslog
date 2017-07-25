#!/bin/bash
set -e
[ "$DEBUG" == 'true' ] && set -x

# Setup hanlder functions and traps to pass on signals to the rsyslog process
sigterm_handler() {
  rsyslog_pid=$(cat /var/run/rsyslogd.pid)
  echo 'Terminating rsyslog process'
  kill -SIGTERM $rsyslog_pid
  wait
  echo "Exiting gracefully"
  exit 0
}
trap 'term_handler' SIGTERM SIGINT SIGQUIT

sighup_handler() {
  if [ $pid -ne 0 ]; then
    # This is typically only needed for log rotate
    echo 'Instructing rsyslog to close all open files'
    kill -SIGHUP $(cat /var/run/rsyslogd.pid)
  fi
}
trap 'sighup_handler' SIGTERM SIGINT SIGQUIT

sigusr1_handler() {
  echo 'Toggle rsyslog debug if enabled'
  kill -SIGUSR1 $(cat /var/run/rsyslogd.pid)
}
trap 'sigusr1_handler' SIGUSR1

# Apply config templates
/usr/local/bin/confd -onetime -backend env > /dev/null

# Check tls
if !([ -f '/etc/pki/rsyslog/key.pem' ] || [ -f '/etc/tls/rsyslog/cert.pem' ]); then
  echo "WARNING: TLS certficates not found in /etc/pki/rsyslog. Linking to default self-signed certficates, but secure syslog services cannot function properly without a common trusted CA and CA signed server certficates." >&2
  ln -s /etc/pki/tls/private/default_self_signed.key.pem /etc/pki/rsyslog/key.pem
  ln -s /etc/pki/tls/certs/default_self_signed.cert.pem /etc/pki/rsyslog/cert.pem
fi

# Do a config sanity check
if ! rsyslogd -N1; then
  echo "ERROR: Rsyslog configuration corrupt. Aborting." >&2
  exit 1
fi

# Exec rsyslog in foreground
if [[ -n "${1}" ]]; then
  # Allow arguments to be passed to rsyslog
  if [[ "${1:0:1}" == '-' ]]; then
    EXTRA_ARGS="${$@}"
    rsyslogd -n ${EXTRA_ARGS}
  elif [[ "${1}" == rsyslogd || "${1}" == $(which rsyslogd) ]]; then
    EXTRA_ARGS="${@:2}"
    rsyslogd -n ${EXTRA_ARGS}
  else
    echo 'Unexpected argument'
    exit 1
  fi
else
  rsyslogd -n
fi

# Note, rsyslog command is to run in the forground. Hopefully no orphined defunct / 'zombie' processes should result when rsylog terminates as per sigterm_handler above. Just in case, wait here as well if rsyslog managed to spawn child processes (given pid = 0 is meat to reap all child processes)
echo "ERROR: Ungraceful exit (rsyslog died without being signaled via the entrypoint)" >&2
wait
