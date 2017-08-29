#!/bin/bash
set -e
[ "$DEBUG" == 'true' ] && export RSYSLOG_DEBUG=DebugOnDemand && set -x

# Term colour escape codes
T_DEFAULT='\e[0m'
T_RED_BOLD='\e[1;31m'
T_YELLOW_BOLD='\e[1;33m'
T_GREEN='\e[0;32m'
T_BLUE='\e[0;34m'

function report_info() {
  echo -e "${T_BLUE}INFO:${T_DEFAULT} $*"
}

function report_warning() {
  echo -e "${T_YELLOW_BOLD}WARN:${T_DEFAULT} $*" >&2
}

function report_error(){
  echo -e "${T_RED_BOLD}ERROR:${T_DEFAULT} $*" >&2
}

# Setup hanlder functions and traps to pass on signals to the rsyslog process
function sigterm_handler() {
  rsyslog_pid=$(cat /var/run/rsyslogd.pid)
  report_info 'INFO: Terminating rsyslog process.'
  kill -SIGTERM "$rsyslog_pid"
  wait "$rsyslog_pid"
  rsyslog_exit_status=$?
  if [ $rsyslog_exit_status -eq 0 ]; then
    report_info 'rsyslog stopped normally.'
  else
    report_error "rsyslog stopped abnormally! Exit code = $rsyslog_exit_status."
  fi
  exit $rsyslog_exit_status
}

function sighup_handler() {
  # This is typically only needed for log rotate
  report_info 'Instructing rsyslog to close all open files.'
  kill -SIGHUP "$(cat /var/run/rsyslogd.pid)"
}

function sigusr1_handler() {
  report_info 'Toggle rsyslog debug if enabled (only works if rsyslogd was started with debug enabled).'
  kill -SIGUSR1 "$(cat /var/run/rsyslogd.pid)"
}

trap 'sigterm_handler' SIGTERM SIGINT SIGQUIT
trap 'sighup_handler' SIGHUP
trap 'sigusr1_handler' SIGUSR1

# Apply config templates
/usr/local/bin/confd -onetime -backend env -log-level warn

# Check TLS
if ! ([ -f "$rsyslog_server_key_file" ] || [ -f "$rsyslog_server_cert_file" ]); then
  report_warning 'TLS certficates not found in /etc/pki/rsyslog. Linking to default self-signed certficates. Insecure - DO NOT run in produciton.'
  ln -s /etc/pki/tls/private/default_self_signed.key.pem /etc/pki/rsyslog/key.pem
  ln -s /etc/pki/tls/certs/default_self_signed.cert.pem /etc/pki/rsyslog/cert.pem
else
  report_info 'TLS certficates found in /etc/pki/rsyslog.'
  report_info "Using $rsyslog_server_key_file as the prviate key"
  report_info "Using $rsyslog_server_cert_file as the certficate"
fi

# Do a config sanity check
if ! rsyslogd -N1; then
  report_error 'Rsyslog configuration corrupt! Aborting.'
  exit 1
fi

# Run rsyslog in the background
# - We can't simply exec rsyslog because of the zombie PID 1 reping problem...
if [[ -n "${1}" ]]; then
  # Allow arguments to be passed to rsyslog
  if [[ "${1:0:1}" == '-' ]]; then
    report_info 'Running rsyslogd with extra arguments.'
    EXTRA_ARGS=( "$@" )
    rsyslogd -n "${EXTRA_ARGS[@]}" 1>> /dev/stdout 2>> /dev/stderr &
  elif [[ "${1}" == rsyslogd || "${1}" == /usr/sbin/rsyslogd ]]; then
    report_info 'Running custom rsyslogd command and arguments.'
    EXTRA_ARGS=( "${@:2}" )
    rsyslogd -n "${EXTRA_ARGS[@]}" 1>> /dev/stdout 2>> /dev/stderr &
  else
    report_info 'Custom command run (in foreground).'
    "$@"
    exit $!
  fi
else
  report_info 'Running rsyslogd.'
  rsyslogd -n 1>> /dev/stdout 2>> /dev/stderr &
fi
pid=$!

# Notes:
# - While one could simply exec rsyslogd and let it handle signals directly, do note that rsyslog source code makes use of fork() - and is therefore might create child processes.
# - Hopefully no orphined defunct / 'zombie' processes should result when rsylog terminates (gracefully via TERM).
# - Regardless, wait again in case rsyslog managed to spawn child processes it didn't clean up, given pid 1 is meat to reap all children.
# - Waiting within a loop is necessary becuse traping SIGUSR1 or SIGINT for rsyslog causes wait to return with exit code = 128 + <SIGNAL int>
# - When wait returns with a non-zero exit code due to async signal hanlding, it needs to be wrapped in set +e, or else this script terminates due to set -e
set +e
while [ -e /proc/$pid ]; do
  wait $pid
  rsyslog_exit_status=$?
done
set -e
# If not trapped and exited via the term signal handler above, report an error.
report_error "Ungraceful exit - rsyslog died! Exit code = $rsyslog_exit_status."
