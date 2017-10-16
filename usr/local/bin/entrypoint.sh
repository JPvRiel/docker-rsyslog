#!/usr/bin/env bash
set -e
[ "$ENTRYPOINT_DEBUG" == 'true' ] && set -x

# Term colour escape codes
T_DEFAULT='\e[0m'
T_RED_BOLD='\e[1;31m'
T_YELLOW_BOLD='\e[1;33m'
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
  report_info 'Terminating rsyslog process.'
  kill -SIGTERM "$rsyslog_pid"
}

function sighup_handler() {
  # This is typically only needed for log rotate
  report_info 'HUP signal sento to rsyslog to close all open files and flush buffers'
  kill -SIGHUP "$(cat /var/run/rsyslogd.pid)"
}

function sigusr1_handler() {
  report_info 'Toggle rsyslog debug if enabled (only works if rsyslogd was started with debug enabled).'
  kill -SIGUSR1 "$(cat /var/run/rsyslogd.pid)"
}

trap 'sigterm_handler' SIGTERM SIGINT SIGQUIT
trap 'sighup_handler' SIGHUP
trap 'sigusr1_handler' SIGUSR1

if [[ -n "${1}" ]]; then
  # Allow arguments to be passed to rsyslog
  if [[ "${1:0:1}" == '-' ]]; then
    EXTRA_ARGS=( "$@" )
  # Don't allow custom rsyslogd exec
  # Need to intercept custom rsyslogd command in order to apply confd template
  elif [[ "${1}" == rsyslogd || "${1}" == /usr/sbin/rsyslogd ]]; then
    EXTRA_ARGS=( "${@:2}" )
  else
    exec "$@"
  fi
fi

# Check TLS key
warn_insecure=false
if [[ -z "$rsyslog_server_key_file" ]]; then
  report_error 'rsyslog_server_key_file not set (assertion failure).'
  exit 1
elif ! [[ -f "$rsyslog_server_key_file" ]]; then
  if [[ "$rsyslog_server_key_file" == '/etc/pki/rsyslog/key.pem' ]]; then
    report_warning "No key found at default location \"$rsyslog_server_key_file\"."
    rsyslog_server_key_file=/usr/local/etc/pki/test/test_syslog_server.key.pem
    warn_insecure=true
  else
    report_error "No key found at custom location \"$rsyslog_server_key_file\". Aborting."
    exit 1
  fi
fi
# Check TLS Cert
if [[ -z "$rsyslog_server_cert_file" ]]; then
  report_error 'rsyslog_server_cert_file not set (assertion failure).'
  exit 1
elif ! [[ -f "$rsyslog_server_cert_file" ]]; then
  if [[ "$rsyslog_server_cert_file" == '/etc/pki/rsyslog/cert.pem' ]]; then
    report_warning "No certficate found at default location \"$rsyslog_server_cert_file\"."
    rsyslog_server_cert_file=/usr/local/etc/pki/test/test_syslog_server.cert.pem
    warn_insecure=true
  else
    report_error "No certficate found at custom location \"$rsyslog_server_cert_file\". Aborting."
    exit 1
  fi
fi
if [[ "$warn_insecure" == 'true' ]]; then
  report_warning 'Insecure built-in TLS key or certifcate in use. DO NOT run in produciton.'
fi
report_info "Using $rsyslog_server_key_file as the prviate key."
report_info "Using $rsyslog_server_cert_file as the certficate."

# Apply config templates
/usr/local/bin/confd -onetime -backend env -log-level warn

# Config sanity check options - handle and augment config checking
if [[ -n ${EXTRA_ARGS[*]} ]]; then
  for a in "${EXTRA_ARGS[@]}"; do
    if [[ "${a:0:2}" == '-E' ]]; then
      report_info 'Expanding config files.'
      /usr/local/bin/rsyslog_config_expand.py
      exit
    fi
    if [[ "${a:0:2}" == '-N' ]]; then
      report_info 'Explicit config check.'
      exec rsyslogd "${EXTRA_ARGS[@]}"
    fi
  done
fi
# Rsyslog config problems occur often, so run a config check by default
report_info 'Implicit config check.'
if ! rsyslogd -N1; then
  report_error 'Rsyslog configuration corrupt! Aborting. Run with -E to output a flattend configuration for inspection.'
  exit 1
fi

# Run rsyslog in the background
if [[ -n ${EXTRA_ARGS[*]} ]]; then
  report_info "Running rsyslogd with extra arguments \"${EXTRA_ARGS[*]}\"."
  rsyslogd -n "${EXTRA_ARGS[@]}" 1>> /dev/stdout 2>> /dev/stderr & pid=$!
  #TODO: catch exit code case where incorrect argument passed
else
  report_info 'Running rsyslogd.'
  rsyslogd -n 1>> /dev/stdout 2>> /dev/stderr & pid=$!
fi

# Notes:
# - While one could simply exec rsyslogd and let it handle signals directly, do note that rsyslog source code makes use of fork() - and is therefore might create child processes.
# - Rsyslog does accept and handle SIGCHLD to reap child processes, but most users (and docker stop) use SIGTERM.
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

# Check the exit code
if [[ -n $rsyslog_exit_status ]]; then
  # 128+15 = 143 (143 indicates processing was stoped via a SIGTERM signal)
  if [[ ! ($rsyslog_exit_status == 0 || $rsyslog_exit_status == 143) ]]; then
    report_error "rsyslog stopped abnormally! Exit code = $rsyslog_exit_status."
  else
    report_info "rsyslog stopped normally. Exit code = $rsyslog_exit_status."
  fi
  exit $rsyslog_exit_status
else
  report_error 'Unknown rsyslog exit status.'
  exit 1
fi
