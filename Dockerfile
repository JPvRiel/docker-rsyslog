FROM centos
MAINTAINER jp.vanriel@gmail.com
LABEL vendor='Jean-Pierre van Riel' \
  version='0.0.8' \
  release-date='2017-08-21'
ENV container=docker

# Setup repos, etc
# Disable fast mirror plugin to better leverage upstream proxy caching (or use specific repos)
RUN sed 's/enabled=1/enabled=0/g' -i /etc/yum/pluginconf.d/fastestmirror.conf
# Switch yum config to use a consitant base url (useful if not caching docker build, but relying on an upstream proxy)
RUN sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/CentOS-Base.repo && \
  sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/CentOS-Base.repo
# Note, some rsyslog modules have dependancies in epel
RUN yum --setopt=timeout=120 -y update && \
  yum -y install epel-release
# Also switch yum config to use a base url for epel repo
RUN sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/epel.repo && \
  sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/epel.repo

# Install Rsyslog. For http://rpms.adiscon.com/v8-stable/rsyslog.repo
# - It has gpgcheck=0
# - Adiscon doens't offer an HTTPS endpoint for the above file :-/
# - The GPG key is at http://rpms.adiscon.com/RPM-GPG-KEY-Adiscon, so also not secure to download and trust directly
# Therefore, prebundle our own local copy of the repo and GPG file
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon /etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon
COPY etc/yum.repos.d/rsyslog.repo /etc/yum.repos.d/rsyslog.repo
RUN yum --setopt=timeout=120 -y update && \
  yum --setopt=timeout=120 -y --enablerepo=epel install \
  rsyslog \
  rsyslog-gnutls \
  rsyslog-kafka \
  rsyslog-relp \
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

# Embed custom org CA into image
COPY etc/pki/ca-trust/source/anchors /etc/pki/ca-trust/source/anchors
RUN update-ca-trust

# Copy rsyslog config templates (for confd)
COPY etc/confd /etc/confd

# Copy rsyslog config files and create folders for template config
COPY etc/rsyslog.conf /etc/rsyslog.conf
COPY etc/rsyslog.d/input /etc/rsyslog.d/input
COPY etc/rsyslog.d/output /etc/rsyslog.d/output
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
# - For production, avoid insecure default by providing an /etc/pki/tls/rsyslog volume provisioned with your own keys and certficates
COPY etc/pki/tls/private/default_self_signed.key.pem /etc/pki/tls/private
COPY etc/pki/tls/certs/default_self_signed.cert.pem /etc/pki/tls/certs

# Default ENV vars for rsyslog config
# global
ENV rsyslog_global_ca_file='/etc/pki/tls/certs/ca-bundle.crt'
ENV rsyslog_server_cert_file='/etc/pki/rsyslog/cert.pem'
ENV rsyslog_server_key_file='/etc/pki/rsyslog/key.pem'
# input
ENV rsyslog_module_imtcp_stream_driver_auth_mode='anon'
  # 'anon' or 'x509/certvalid' or 'x509/name'
ENV rsyslog_tls_permitted_peer='["*"]'
ENV rsyslog_module_impstats_interval='300'

# metadata, filtering and output flags
ENV rsyslog_metadata_enabled=false
ENV rsyslog_filtering_enabled=false
ENV rsyslog_omfile_enabled=true
ENV rsyslog_omkafka_enabled=false
ENV rsyslog_omfwd_enabled=false
ENV rsyslog_forward_extra_enabled=false

#TODO: check how not to lose/include orginal host if events are relayed
#TODO: check if it's possible to add/tag 5424 with metadata about syslog method used (e.g. strong auth, just SSL sever, weak udp security)
#TODO: 5424 format (rfc5424micro)?

# Note, output config will probably be highly varied, so instead of trying to template it, we allow for that config to be red from a volume and managed by simply picking up from a forward ruleset

#TODO: understand which "stateful" runtime directories rsyslog should have in order to perist accross errors/container runs
# Volumes required
VOLUME /var/log/remote \
  /var/spool/rsyslog \
  /etc/pki/rsyslog
# Extra optional volumes that could be supplied at runtime
# - /etc/rsyslog.d/output/forward_extra
# - /etc/rsyslog.d/filter

# Ports to expose
EXPOSE 514/udp
  #UDP
EXPOSE 514/tcp
  #TCP
EXPOSE 6514/tcp
  #TCP Secure
EXPOSE 2514/tcp
  #RELP
EXPOSE 7514/tcp
  #RELP Secure
EXPOSE 8514/tcp
  #RELP Secure with strong client auth

#TODO: also, decide if we will accept the signal to reload config without restarting the container

COPY rsyslog.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/rsyslog.sh

ENTRYPOINT ["/usr/local/bin/rsyslog.sh"]
