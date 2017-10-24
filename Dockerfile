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
COPY etc/pki/ca-trust/source/anchors/* /etc/pki/ca-trust/source/anchors/
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
RUN yum --setopt=timeout=120 -y update && \
  yum -y install --setopt=timeout=120 --setopt=tsflags=nodocs epel-release
# Also switch to a base url for epel repo
RUN if [ "$DISABLE_YUM_MIRROR" != true ]; then exit; fi && \
  sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/epel.repo && \
  sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/epel.repo

# Install Rsyslog. For http://rpms.adiscon.com/v8-stable/rsyslog.repo
# - It has gpgcheck=0
# - Adiscon doens't offer an HTTPS endpoint for the above file :-/
# - The GPG key is at http://rpms.adiscon.com/RPM-GPG-KEY-Adiscon, so also not secure to download and trust directly
# Therefore, prebundle our own local copy of the repo and GPG file
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon /etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon
COPY etc/yum.repos.d/rsyslog.repo /etc/yum.repos.d/rsyslog.repo
RUN yum --setopt=timeout=120 -y update && \
  yum --setopt=timeout=120 --setopt=tsflags=nodocs -y install \
  rsyslog \
  rsyslog-gnutls \
	adisconbuild-librdkafka1 \
  rsyslog-kafka \
  rsyslog-relp \
  lsof \
  && yum clean all
RUN rm -r /etc/rsyslog.d/ \
  && rm /etc/rsyslog.conf

# Install confd
ENV CONFD_VER='0.13.0'
#ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VER}/confd-${CONFD_VER}-linux-amd64 /usr/local/bin/confd
COPY usr/local/bin/confd-0.13.0-linux-amd64 /usr/local/bin/confd
  # Use bundled file to avoid downloading all the time
RUN chmod +x /usr/local/bin/confd && \
  mkdir -p /etc/confd/conf.d && \
  mkdir -p /etc/confd/templates

# Copy rsyslog config templates (for confd)
COPY etc/confd /etc/confd

# Copy rsyslog config files and create folders for template config
COPY etc/rsyslog.conf /etc/rsyslog.conf
COPY etc/rsyslog.d/input/ /etc/rsyslog.d/input/
COPY etc/rsyslog.d/output/ /etc/rsyslog.d/output/
# Directories intended as optional v0lume mounted config
RUN mkdir -p \
  /etc/rsyslog.d/filter \
  /etc/rsyslog.d/output/forward_extra
# Note:
# - rsyslog.d/output/extra is a volume used for unforseen custom outputs
# - rsyslog.d/filter is a volume used for unforseen custom input filters
# - filters that apply to a specific forwarder should rather be done within that forwarders ruleset

# Copy a default self-signed cert and key - this is INSECURE and for testing/build purposes only
# - To help handle cases when the rsyslog tls volume doesn't have expected files present
# - rsyslog.sh entrypoint script will symlink and use these defaults if not provided in a volume
# - For production, avoid insecure default by providing an /etc/pki/rsyslog volume provisioned with your own keys and certficates
RUN mkdir -p usr/local/etc/pki/test
COPY usr/local/etc/pki/test/test_ca.cert.pem /usr/local/etc/pki/test
COPY usr/local/etc/pki/test/test_syslog_server.key.pem /usr/local/etc/pki/test
COPY usr/local/etc/pki/test/test_syslog_server.cert.pem /usr/local/etc/pki/test

# Default ENV vars for rsyslog config

# TLS related globals
ENV rsyslog_global_ca_file='/etc/pki/tls/certs/ca-bundle.crt' \
  rsyslog_server_cert_file='/etc/pki/rsyslog/cert.pem' \
  rsyslog_server_key_file='/etc/pki/rsyslog/key.pem'

# Inputs and parsing inputs
ENV rsyslog_support_metadata_formats='off' \
  rsyslog_mmpstrucdata='off' \
  rsyslog_pmrfc3164_force_tagEndingByColon='off' \
  rsyslog_pmrfc3164_remove_msgFirstSpace='off' \
  rsyslog_global_parser_permitslashinprogramname='off' \
  rsyslog_global_preservefqdn='on' \
  rsyslog_global_maxmessagesize=65536 \
  rsyslog_input_filtering_enabled='off' \
  rsyslog_module_impstats_interval='300' \
  rsyslog_global_action_reportSuspension='on' \
  rsyslog_global_senders_keeptrack='on' \
  rsyslog_global_senders_timeoutafter='86400' \
  rsyslog_global_senders_reportgoneaway='on' \
  rsyslog_module_imtcp_stream_driver_auth_mode='anon' \
  rsyslog_tls_permitted_peer='["*"]'
# Note 'anon' or 'x509/certvalid' or 'x509/name' for ...auth_mode

# Outputs
# See 60-output_format.conf.tmpl
ENV rsyslog_omfile_enabled='on' \
  rsyslog_omfile_split_files_per_host='off' \
  rsyslog_omfile_template='RSYSLOG_TraditionalFileFormat' \
  rsyslog_omkafka_enabled='off' \
  rsyslog_omkafka_broker='' \
  rsyslog_omkafka_confParam='' \
  rsyslog_omkafka_topic='syslog' \
  rsyslog_omkafka_dynatopic='off' \
  rsyslog_omkafka_topicConfParam='' \
  rsyslog_omkafka_template='TmplJSON' \
  rsyslog_omfwd_syslog_enabled='off' \
  rsyslog_omfwd_syslog_host='' \
  rsyslog_omfwd_syslog_port=514 \
  rsyslog_omfwd_syslog_protocol='tcp' \
  rsyslog_omfwd_syslog_template='TmplRFC5424' \
  rsyslog_omfwd_json_enabled=off \
  rsyslog_omfwd_json_host='' \
  rsyslog_omfwd_json_port=5000 \
  rsyslog_omfwd_json_template='TmplJSON' \
  rsyslog_om_action_queue_maxdiskspace=1073741824 \
  rsyslog_om_action_queue_size=2097152 \
  rsyslog_om_action_queue_discardmark=1048576 \
  rsyslog_om_action_queue_discardseverity=6 \
  rsyslog_forward_extra_enabled='off'
# Several globals are defined via rsyslog_global_* inlcuding reporting stats
#
# rsyslog_support_metadata_formats and the appropriate template choice must both be used to allow including validation checks on syslog headers, hostnames and tags for RFC3164. The metadata template choices are:
# - TmplRFC5424Meta
# - TmplJSONRawMeta
#
# Notes for the pre-canned outputs (kafka, JSON, syslog)
# - each pre-canned output can have it's own template applied, e.g.
# - rsyslog_om_action_queue_* is set for all outputs (sort of a global)
# - rsyslog_om_action_queue_maxdiskspace=1073741824 ~ 1G
# - E.g. if three outputs have ~ 1G file limit for the queue, 3G overall is needed
# - Most rsyslog limits work on number of messages in the queue, so rsyslog_om_action_queue_size and rsyslog_om_action_queue_discardmark need to be adjusted in line with rsyslog_om_action_queue_maxdiskspace
# - E.g. Assuming 512 byte messages, a 1G file can fit ~ 2 million messages, and start discarding at ~ 1 million messages
# - While arithmentic could be used to work backwards from max file sizes to message numbers, unfortunatly confd's arithmetic golang text template functions don't handle dynamic type conversion. See: https://github.com/kelseyhightower/confd/issues/611
# - rsyslog_om_action_queue_discardseverity=6 implies info and debug messages get discarded
#
# Additonal output config will probably be highly varied, so instead of trying to template/pre-can it, we allow for that config to be red from a volume and managed by simply picking up from a `output_extra` ruleset. rsyslog_forward_extra_enabled='on' to enable.


# Volumes required
VOLUME /var/log/remote \
  /var/lib/rsyslog \
  /etc/pki/rsyslog

# Extra optional volumes with config that can be supplied at runtime to inject custom needs
# - /etc/rsyslog.d/output/extra
# - /etc/rsyslog.d/filter

# Ports to expose
# Note: UDP=514, TCP=514, TCP Secure=6514, RELP=2514, RELP Secure=7514, RELP Secure with strong client auth=8514
EXPOSE 514/udp 514/tcp 6514/tcp 2514/tcp 7514/tcp 8514/tcp

#TODO: also, decide if we will accept the signal to reload config without restarting the container

COPY usr/local/bin/entrypoint.sh usr/local/bin/rsyslog_healthcheck.sh usr/local/bin/rsyslog_healthcheck.sh usr/local/bin/rsyslog_config_expand.py /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

HEALTHCHECK CMD /usr/local/bin/rsyslog_healthcheck.sh

# Add build-date at the end to avoid invalidating the docker build cache
ARG BUILD_DATE
LABEL org.label-schema.build-date="${BUILD_DATE}"
