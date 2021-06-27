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
  if [ -e "$crond_pid_file" ]; then
    report_info 'Terminating crond process (runs logrotate).'
    kill -SIGTERM "$(cat "$crond_pid_file")"
  fi
  report_info 'Terminating rsyslog process.'
  kill -SIGTERM "$(cat "$rsyslog_pid_file")"
}

function sighup_handler() {
  # This is typically only needed for log rotate
  report_info 'HUP signal sent to rsyslog to close all open files, flush buffers and open new files.'
  kill -SIGHUP "$(cat "$rsyslog_pid_file")"
}

function sigusr1_handler() {
  report_info 'Toggle rsyslog debug if enabled (only works if rsyslogd was started with debug enabled).'
  kill -SIGUSR1 "$(cat "$rsyslog_pid_file")"
}

trap 'sigterm_handler' SIGTERM SIGINT SIGQUIT
trap 'sighup_handler' SIGHUP
trap 'sigusr1_handler' SIGUSR1

# Check if PID file env var is set
if [[ -z "$rsyslog_pid_file" ]]; then
  # Assume CentOS7 syslog 8 default
  rsyslog_pid_file='/var/run/syslogd.pid'
fi
if [[ -z "$crond_pid_file" ]]; then
  # Assume CentOS7 syslog 8 default
  crond_pid_file='/var/run/crond.pid'
fi

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
report_info "Using $rsyslog_server_key_file as the private key."
report_info "Using $rsyslog_server_cert_file as the certficate."

# Apply config templates
/usr/local/bin/confd -onetime -backend env -log-level warn

# Sanity check conifg options - handle and augment config checking features
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
  report_warning 'Rsyslog configuration issue found. Run with -E to output a flattend configuration for inspection.'
  exit 1
fi

# Check for stale PID files because rsyslog will refuse to start, but docker policy might be in the habit of just trying to restart a container after failure
if [[ -f "$rsyslog_pid_file" ]]; then
  old_pid=$(cat "$rsyslog_pid_file")
  report_error "A previous PID file '$rsyslog_pid_file' already exists with PID $old_pid, indicating a restart after an abnormal exit."
  if [ -n "$old_pid" -a -e "/proc/$old_pid" ]; then
    report_error "PID $old_pid still appears to be active, so '$0' aborting"
    exit 1
  fi
  report_warning "Removing stale PID file $rsyslog_pid_file"
  rm -f "$rsyslog_pid_file"
fi

# As a dependency for built-in log rotate, run cron in the forground, redirect output to stdout and stderr, and then background it.
# logrotate_enabled will normally be set by env calling the conainer.
: "${logrotate_enabled:=on}"
if [ "${logrotate_enabled,,}" = 'on' ] || [ "${logrotate_enabled,,}" = 'true' ]; then
  # Use of docker userns-remap while forcing the container to run in the host namespace may cause cron files to be owned by a UID other than 0 and cause crond root checks to fail.
  chown -R root:root /etc/logrotate.conf /etc/crontab /etc/cron.* /usr/local/bin/rsyslog-rotate.sh
  chmod -R 0644 /etc/logrotate.conf /etc/crontab /etc/cron.d/*
  chmod 0744 /usr/local/bin/rsyslog-rotate.sh
  # FIXME: crond on CentOS/RHEL7 does not have the `-L`, so cannot redirect to stdout of the container. `-s`, the syslog option, will silently drop cron logs given /dev/log does not normally exist in a container. crond doesn't outout to console.
  crond -m off -n 1>> /dev/stdout 2>> /dev/stderr &
  cron_pid=$!
  report_info "Running crond for logrotate (PID $cron_pid)."
fi

# Run rsyslog in the background
if [[ -n ${EXTRA_ARGS[*]} ]]; then
  rsyslogd -n "${EXTRA_ARGS[@]}" 1>> /dev/stdout 2>> /dev/stderr &
  pid=$!
  report_info "Running rsyslogd with extra arguments \"${EXTRA_ARGS[*]}\" (PID $pid)."
  #TODO: catch exit code case where incorrect argument passed? Tricky for a background job...
else
  rsyslogd -n 1>> /dev/stdout 2>> /dev/stderr &
  pid=$!
  report_info "Running rsyslogd (PID $pid)."
fi

# Notes:
# - While one could simply exec rsyslogd and let it handle signals directly, do note that rsyslog source code makes use of fork() - and is therefore might create child processes.
# - Rsyslog does accept and handle SIGCHLD to reap child processes, but most users (and docker stop) use SIGTERM.
# - Hopefully no orphined defunct / 'zombie' processes should result when rsylog terminates (cleanly via TERM).
# - Regardless, wait again in case rsyslog managed to spawn child processes it didn't clean up, given pid 1 is meat to reap all children.
# - Waiting within a loop is necessary becuse traping SIGUSR1 or SIGINT for rsyslog causes wait to return with exit code = 128 + <SIGNAL int>
# - When wait returns with a non-zero exit code due to async signal hanlding, it needs to be wrapped in set +e, or else this script terminates due to set -e
set +e
while [ -e /proc/$pid ]; do
  wait $pid
  rsyslog_exit_status=$?
done
set -e

# Check if logrotate had issues
if [[ -e '/var/log/logrotate.err.log' ]]; then
  report_error "logrotate may have failed. State kept in /var/lib/logrotate/logrotate.status may help understand when last files were tracked."
  cat /var/log/logrotate.err.log
fi
# Check the exit code of rsyslog
if [[ -n $rsyslog_exit_status ]]; then
  # 128+15 = 143 (143 indicates processing was stoped via a SIGTERM signal)
  if [[ ! ($rsyslog_exit_status == 0 || $rsyslog_exit_status == 143) ]]; then
    report_error "rsyslog stopped abnormally! Exit code = $rsyslog_exit_status."
    exit 1
  else
    report_info "rsyslog stopped normally. Exit code = $rsyslog_exit_status."
  fi
  exit $rsyslog_exit_status
else
  report_error 'Unknown rsyslog exit status.'
  exit 1
fi
