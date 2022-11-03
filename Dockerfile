FROM centos:7
ARG VERSION
LABEL org.label-schema.schema-version=1.0.0-rc1 \
  org.label-schema.name="rsyslog" \
  org.label-schema.description="RSyslog container with pre-canned use-cases controlled by setting environment variables" \
  org.label-schema.version="${VERSION}" \
  org.label-schema.url="http://www.rsyslog.com" \
  org.label-schema.vcs-url="https://github.com/JPvRiel/docker-rsyslog" \
  org.label-schema.distribution-scope=public \
  maintainer='Jean-Pierre van Riel <jp.vanriel@gmail.com>'
# Base CentOS image has a nubmer of labels we don't overwrite and this may cause confusion

ENV container=docker

# Embed custom org CA into image if need be
COPY etc/pki/ca-trust/source/anchors/ /etc/pki/ca-trust/source/anchors/
RUN update-ca-trust

# Setup repos, etc
# Disable fast mirror plugin to better leverage upstream proxy caching (or use specific repos)
# Switch yum config to use a consitant base url (useful if not caching docker build, but relying on an upstream proxy)
ARG DISABLE_YUM_MIRROR=false
RUN if [ "$DISABLE_YUM_MIRROR" != true ]; then exit; fi && \
  sed 's/enabled=1/enabled=0/g' -i /etc/yum/pluginconf.d/fastestmirror.conf && \
  sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/CentOS-Base.repo && \
  sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/CentOS-Base.repo
# Some rsyslog modules have dependancies in epel
# RUN yum --setopt=timeout=120 -y update && \
#   yum -y install --setopt=timeout=120 --setopt=tsflags=nodocs epel-release
# # Also switch to a base url for epel repo
# RUN if [ "$DISABLE_YUM_MIRROR" != true ]; then exit; fi && \
#   sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/epel.repo && \
#   sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/epel.repo

# Install RSyslog and logrotate
# For http://rpms.adiscon.com/v8-stable/rsyslog.repo
# - It has gpgcheck=0
# - Adiscon doens't offer an HTTPS endpoint for the above file :-/
# - The GPG key is at http://rpms.adiscon.com/RPM-GPG-KEY-Adiscon, so also not secure to download and trust directly
# Therefore, prebundle our own local copy of the repo and GPG file
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon /etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon
COPY etc/yum.repos.d/rsyslog.repo /etc/yum.repos.d/rsyslog.repo
ARG RSYSLOG_VERSION='8.2208.0'
RUN yum --setopt=timeout=120 -y update && \
  yum --setopt=timeout=120 --setopt=tsflags=nodocs -y install \
  rsyslog-${RSYSLOG_VERSION} \
  rsyslog-gnutls-${RSYSLOG_VERSION} \
  rsyslog-openssl-${RSYSLOG_VERSION} \
  rsyslog-kafka-${RSYSLOG_VERSION} \
  rsyslog-relp-${RSYSLOG_VERSION} \
  rsyslog-pmciscoios-${RSYSLOG_VERSION} \
  rsyslog-mmjsonparse-${RSYSLOG_VERSION} \
  rsyslog-udpspoof-${RSYSLOG_VERSION} \
  lsof \
  logrotate \
  cronie-noanacron \
  python3 \
  && yum clean all
RUN rm -rf /etc/rsyslog.d/ \
  && rm -f /etc/rsyslog.conf \
  && rm -f /etc/logrotate.conf \
  && find /etc/logrotate.d/ -type f -delete \
  && find /etc/cron.d/ ! -type d -delete

# Install confd
ARG CONFD_VER='0.16.0'
#ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VER}/confd-${CONFD_VER}-linux-amd64 /usr/local/bin/confd
COPY usr/local/bin/confd-${CONFD_VER}-linux-amd64 /usr/local/bin/confd
# Use bundled file to avoid downloading all the time

RUN chmod +x /usr/local/bin/confd && \
  mkdir -p /etc/confd/conf.d && \
  mkdir -p /etc/confd/templates

# Copy rsyslog config templates (for confd)
COPY etc/confd /etc/confd

# Copy cron and logrotate config
COPY etc/cron.d /etc/cron.d
COPY etc/cron.daily /etc/cron.daily
COPY etc/logrotate.conf /etc/logrotate.conf
COPY usr/local/bin/rsyslog-rotate.sh /usr/local/bin/rsyslog-rotate.sh
RUN chmod 0644 /etc/logrotate.conf && \
  chmod 0744 /usr/local/bin/rsyslog-rotate.sh && \
  find /etc/cron.daily -type f -exec chmod 0744 {} \;

# Copy rsyslog config files and create folders for template config
COPY etc/rsyslog.conf /etc/rsyslog.conf
COPY etc/rsyslog.d/input/ /etc/rsyslog.d/input/
COPY etc/rsyslog.d/output/ /etc/rsyslog.d/output/
# Directories intended as optional volume mounted config
RUN mkdir -p \
  /etc/rsyslog.d/input/filters \
  /etc/rsyslog.d/output/filters \
  /etc/rsyslog.d/extra
# Note:
# - rsyslog.d/input/filters is a volume used for addtional input filters that fit into pre-defined templated inputs
# - rsyslog.d/output/filters is a volume used for addtional output filters that fit into pre-defined templated outputs
# - rsyslog.d/extra is a volume used for unforseen custom config

# Copy a default self-signed cert and key - this is INSECURE and for testing/build purposes only
# - To help handle cases when the rsyslog tls volume doesn't have expected files present
# - rsyslog.sh entrypoint script will symlink and use these defaults if not provided in a volume
# - For production, avoid insecure default by providing an /etc/pki/rsyslog volume provisioned with your own keys and certficates
RUN mkdir -p usr/local/etc/pki/test
COPY usr/local/etc/pki/test/test-ca.cert.pem /usr/local/etc/pki/test
COPY usr/local/etc/pki/test/test-syslog-server.key.pem /usr/local/etc/pki/test
COPY usr/local/etc/pki/test/test-syslog-server.cert.pem /usr/local/etc/pki/test

# Default ENV vars for rsyslog config tuned for high throughput by default and assumes a multi-core system that can handle several worker threads.
# - See: https://www.rsyslog.com/doc/v8-stable/examples/high_performance.html.

# TLS related globals
ENV rsyslog_global_ca_file='/etc/pki/tls/certs/ca-bundle.crt' \
  rsyslog_server_cert_file='/etc/pki/rsyslog/cert.pem' \
  rsyslog_server_key_file='/etc/pki/rsyslog/key.pem'

# Inputs and parsing inputs. Note:
# - Rate limiting is disabled by default (0).
# - UDP recieve buffer size is left as autotune by default (0).
# - UDP FIFO shedular is set to try avoid packet loss.
# - TCP socket backlog is increase to try avoid failed TCP open connection errors (only applies to imptcp).
# - imtcp is used for TCP with TLS while imptcp is used for TCP without TLS.
# - Batch sizes and threads are increased with the aim of handling higher remote server throughput.
# - A 'central' queue is based on a fixed array in-memory queue, so take care when increasing rsyslog_global_maxMessageSize
# - 'anon' or 'x509/certvalid' or 'x509/name' for ...auth_mode does not apply to RELP, only TCP TLS
ENV rsyslog_global_maxMessageSize=65536 \
  rsyslog_parser='["rsyslog.rfc5424", "custom.rfc3164"]' \
  rsyslog_pmrfc3164_force_tagEndingByColon='off' \
  rsyslog_pmrfc3164_remove_msgFirstSpace='on' \
  rsyslog_pmrfc3164_permit_squareBracketsInHostname='off' \
  rsyslog_pmrfc3164_permit_slashInHostname='on' \
  rsyslog_pmrfc3164_permit_atSignsInHostname='off' \
  rsyslog_global_parser_permitSlashInProgramName='on' \
  rsyslog_global_parser_escapeControlCharacterTab='off' \
  rsyslog_global_preserveFQDN='on' \
  rsyslog_mmpstrucdata='on' \
  rsyslog_mmjsonparse='on' \
  rsyslog_mmjsonparse_without_cee='off' \
  rsyslog_support_metadata_formats='off' \
  rsyslog_input_filtering_enabled='on' \
  rsyslog_module_imudp_RcvBufSize=0 \
  rsyslog_module_imudp_BatchSize=128 \
  rsyslog_module_imudp_threads=2 \
  rsyslog_module_imudp_SchedulingPolicy='fifo' \
  rsyslog_module_imudp_SchedulingPriority=10 \
  rsyslog_module_imudp_RateLimit_Interval=0 \
  rsyslog_module_imudp_RateLimit_Burst=262144 \
  rsyslog_module_imptcp_threads=4 \
  rsyslog_module_imptcp_SocketBacklog=128 \
  rsyslog_module_imptcp_ProcessOnPoller='off' \
  rsyslog_module_imptcp_KeepAlive='off' \
  rsyslog_module_imptcp_flowControl='on' \
  rsyslog_module_imptcp_NotifyOnConnectionOpen='off' \
  rsyslog_module_imptcp_NotifyOnConnectionClose='off' \
  rsyslog_module_imptcp_RateLimit_Interval=0 \
  rsyslog_module_imptcp_RateLimit_Burst=262144 \
  rsyslog_module_imtcp_KeepAlive='off' \
  rsyslog_module_imtcp_flowControl='on' \
  rsyslog_module_imtcp_NotifyOnConnectionClose='off' \
  rsyslog_module_imtcp_maxSessions=1000 \
  rsyslog_module_imtcp_streamDriver_authMode='anon' \
  rsyslog_module_imtcp_RateLimit_Interval=0 \
  rsyslog_module_imtcp_RateLimit_Burst=262144 \
  rsyslog_module_imrelp_KeepAlive='off' \
  rsyslog_module_imrelp_authMode='certvalid' \
  rsyslog_tls_permittedPeer='["*"]'

# Metrics. Note:
# - impstats is a special internal input for reporting rsyslog metrics
# - Options to log to syslog and/or a file.
# - Logging metrics within syslog itself could be unreliable as problems can prevent metrics from being processed properly.
# - If logging metrics within syslog, the cee format helps rsyslog expect impstats in a JSON format after the '@cee' cookie in the message.
# - Logging metrics to a file is probably better but should be complimented with log rotate process to avoid filling up storage.
# - Option to enable logging of dynstat incriment errors to a seperate meta file (off by default)
ENV rsyslog_impstats='on' \
  rsyslog_module_impstats_interval=60 \
  rsyslog_module_impstats_resetCounters='on' \
  rsyslog_module_impstats_format='cee' \
  rsyslog_impstats_log_syslog='on' \
  rsyslog_impstats_log_file_enabled='off' \
  rsyslog_impstats_log_file='/var/log/impstats/metrics.log' \
  rsyslog_impstats_ruleset='syslog_stats' \
  rsyslog_dyn_stats='on' \
  rsyslog_dyn_stats_maxCardinality=10000 \
  rsyslog_dyn_stats_unusedMetricLife=86400 \
  rsyslog_dyn_stats_inc_error_reporting='off' \
  rsyslog_dyn_stats_inc_error_reporting_file='/var/log/impstats/dyn_stats_inc_error.log' \
  rsyslog_global_action_reportSuspension='on' \
  rsyslog_global_senders_keepTrack='on' \
  rsyslog_global_senders_timeoutAfter=86400 \
  rsyslog_global_senders_reportGoneAway='on'

# Central queue tuned for higher throughput in a central syslog server:
# - Up to 8 worker threads will be running if the queue gets filled halfway (i.e. 64K messages, 8K messages per worker).
# - FixedArray sacrifices RAM (consumes more static memory) for slightly less CPU overhead.
ENV rsyslog_central_queue_type='FixedArray' \
  rsyslog_central_queue_size=100000 \
  rsyslog_central_queue_dequeueBatchSize=5000 \
  rsyslog_central_queue_minDequeueBatchSize=50 \
  rsyslog_central_queue_minDequeueBatchSize_timeout=100 \
  rsyslog_central_queue_workerThreads=4 \
  rsyslog_central_workerThreadMinimumMessages=20000
# Note - see /etc/confd/60-ruleset.conf.tmpl:
# - Instead of using the default main queue, a 'central' explicitly defined queue is used between inputs and outputs
# - Each input is bound to it's own input ruleset (instead of the rsyslog main queue default)
# - Each input ruleset applies generic or input specific filters
# - Each input ruleset/queue is of type 'direct'
# - Each input ruleset/queue calls the central ruleset
# - The central ruleset acts as a central 'sink' to collate all inputs
# - The central queue applies various parsing checks and data enrichments
# - The central queue can apply a generic output filter before calling other output rulesets
# - The central ruleset/queue is of type 'in-memory'
# - Output specific rulesets, such as fwd_kafka, fwd_syslog, etc have 'disk-assisted' memory queues
# - Output specific rulesets/queues are intended to persist data backlogs the most, and should perist when rsyslog is restarted
# Note futher:
# - The queue.workerThreadMinimumMessages setting defaults to queue.size/queue.workerthreads. This tweaks that to add more threads a little bit earlier, ideally before discard threadholds are reached.
# - The 'fixed array' queue type for the central queue trades off extra memory usage for lower CPU overhead.
#   (See: https://www.rsyslog.com/doc/v8-stable/configuration/global/options/rsconf1_mainmsgqueuesize.html)

# Outputs (action output queues are persistant/disk assisted)
# See 60-output_format.conf.tmpl
ENV rsyslog_output_filtering_enabled='on' \
  rsyslog_omfile_enabled='on' \
  rsyslog_omfile_split_files_per_host='off' \
  rsyslog_omfile_template='RSYSLOG_TraditionalFileFormat' \
  rsyslog_omfile_DirCreateMode='0755' \
  rsyslog_omfile_FileCreateMode='0640' \
  rsyslog_omkafka_enabled='off' \
  rsyslog_omkafka_broker='' \
  rsyslog_omkafka_confParam='' \
  rsyslog_omkafka_topic='syslog' \
  rsyslog_omkafka_dynaTopic='off' \
  rsyslog_omkafka_topicConfParam='' \
  rsyslog_omkafka_template='TmplJSON' \
  rsyslog_omfwd_syslog_enabled='off' \
  rsyslog_omfwd_syslog_host='' \
  rsyslog_omfwd_syslog_port=514 \
  rsyslog_omfwd_syslog_protocol='tcp' \
  rsyslog_omfwd_syslog_template='TmplRFC5424' \
  rsyslog_omudpspoof_syslog_enabled='off' \
  rsyslog_omudpspoof_syslog_host='' \
  rsyslog_omudpspoof_syslog_port=514 \
  rsyslog_omudpspoof_syslog_template='TmplRFC5424' \
  rsyslog_omfwd_json_enabled=off \
  rsyslog_omfwd_json_host='' \
  rsyslog_omfwd_json_port=5000 \
  rsyslog_omfwd_json_template='TmplJSON' \
  rsyslog_om_action_queue_type='LinkedList' \
  rsyslog_om_action_queue_maxDiskSpace=1073741824 \
  rsyslog_om_action_queue_size=100000 \
  rsyslog_om_action_queue_discardMark=95000 \
  rsyslog_om_action_queue_discardSeverity=7 \
  rsyslog_om_action_queue_checkpointInterval=10000 \
  rsyslog_om_action_queue_dequeueBatchSize=5000 \
  rsyslog_om_action_queue_minDequeueBatchSize=50 \
  rsyslog_om_action_queue_minDequeueBatchSize_timeout=100 \
  rsyslog_om_action_queue_workerThreads=4 \
  rsyslog_om_action_queue_workerThreadMinimumMessages=20000 \
  rsyslog_call_fwd_extra_rule='off'
# Several globals are defined via rsyslog_global_* inlcuding reporting stats
#
# rsyslog_support_metadata_formats and the appropriate template choice must both be used to allow including validation checks on syslog headers, hostnames and tags for RFC3164. The metadata template choices are:
# - TmplRFC5424
# - TmplJSONRawMsg
#
# Brief notes for the pre-canned outputs (kafka, JSON, syslog):
# - Each pre-canned output can have it's own template applied.
# - Multiple outputs can be enabled at once.
# - The rsyslog_om_action_queue_type should be either LinkedList or FixedArray.
# - A disk-assisted (DA) queue is setup for the outputs (see: <https://www.rsyslog.com/doc/v8-stable/concepts/queues.html>).
# - NB! The in-memory part is limited the the number of messaegs (rsyslog_om_action_queue_size) and the on-disk part is limited by the disk space usage limit (rsyslog_om_action_queue_maxDiskSpace).
# - rsyslog_om_action_queue_* is set and shared for all output queues, so multiple enabled outputs multiplies the mem and storage resources needed to queue output!
# - rsyslog_om_action_queue_size applies only to the in-memory part of each output queue. Assuming 512 bytes per message, a 100000 size limit implies ~50MB memory use (not counting for other rsyslog overhead).
# - E.g. With 3x enabled outputs, 3x 50MB approx usage per queue, then ~150MB overall could be used, again, not accounting for any other overhead.
# - Memory issues can still result. E.g. Assuming worst case, something loops and floods the queue with junk and the full 64K message size limit, then even with just one output, 100000 x 64K = 6GB+ RAM! Set rsyslog_global_maxMessageSize to a smaller value to mitigate this.
# - rsyslog_om_action_queue_maxDiskSpace=1073741824 ~ 1G max storage space used, but you likely want more?
# - E.g. again, if 3x enabled outputs, 3x 1G storage use limit per output, then 3G overall storage space is needed.
# - NB! Some rsyslog queue parameters are left as deafult or have modified defaults, but are not exposed as env vars and hopefully make sense for DA output queues.
#   - RSyslog's default for highWatermark is 90% vs 80% for discardMark, so discarding happens by default before using disk if discardSeverity is set.
#   - RSyslog's default for lightDelayMark is 70% vs 90% for highWatermark, so it could push upstream inputs like TCP to stop sending with "backpressure" before begining to make use of disk-assited storage. Hence this container's default is to rather disable it and let disk-assited queing do the work.
# - rsyslog_om_action_queue_discardMark is ideally 95% of queue.size, as rsyslog's high watermark for using disk in DA queues is 90% and you would likely not want messaegs discarded before at least attepmting to use disk.
# - rsyslog_om_action_queue_discardSeverity=7 implies debug messages get discarded.
# - While arithmentic could be used to default rsyslog_om_action_queue_discardMark = 0.95 * rsyslog_om_action_queue_size, unfortunatly confd's arithmetic golang text template functions don't handle dynamic type conversion. See: <https://github.com/kelseyhightower/confd/issues/611>.
#
# Additonal output config will probably be highly varied, so instead of trying to template/pre-can it, we allow for that config to be red in
# As above, extra optional volumes with config that can be supplied at runtime
# - /etc/rsyslog.d/input/filters
# - /etc/rsyslog.d/output/filters
# - /etc/rsyslog.d/extra
#
# rsyslog_call_fwd_extra_rule makes the config expect input the user to add a ruleset named fwd_extra somewhere in /etc/rsyslog.d/extra/*.conf

# Built-in log rotation for /var/log/remote and /var/log/impstats
# - This process could be managed externally by a host more aware of volume sizes and Constraints.
# - If managed externally, the HUP signal needs to be sent to the container and the entrypoint script will handle passing it onto rsyslogd.
ENV logrotate_enabled='on' \
  logrotate_remote_period='daily' \
  logrotate_remote_files='42' \
  logrotate_impstats_period='daily' \
  logrotate_impstats_files='42'

# Volumes required
VOLUME /var/log/remote \
  /var/log/impstats \
  /var/lib/rsyslog \
  /etc/pki/rsyslog

# Ports to expose
# Note: UDP=514, TCP=514, TCP=601, TCP Secure=6514, RELP=2514, RELP Secure=7514, RELP Secure with strong client auth=8514
EXPOSE 514/udp 514/tcp 601/tcp 6514/tcp 2514/tcp 7514/tcp 8514/tcp

#TODO: also, decide if we will accept the signal to reload config without restarting the container

COPY usr/local/bin/entrypoint.sh \
  usr/local/bin/rsyslog_healthcheck.sh \
  usr/local/bin/rsyslog_config_expand.py \
  /usr/local/bin/
RUN chmod 0755 usr/local/bin/entrypoint.sh \
  /usr/local/bin/rsyslog_healthcheck.sh \
  /usr/local/bin/rsyslog_config_expand.py

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

HEALTHCHECK CMD /usr/local/bin/rsyslog_healthcheck.sh

# Add build-date at the end to avoid invalidating the docker build cache
ARG BUILD_DATE
LABEL org.label-schema.build-date="${BUILD_DATE}"
