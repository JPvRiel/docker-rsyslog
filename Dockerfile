FROM centos
MAINTAINER jp.vanriel@gmail.com

ENV container=docker

# Disable fast mirror plugin to better leverage upstream proxy caching
RUN sed 's/enabled=1/enabled=0/g' -i /etc/yum/pluginconf.d/fastestmirror.conf
# Switch yum config to use a consitant base url (useful if not caching docker build, but relying on an upstream proxy)
RUN sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/CentOS-Base.repo && \
  sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/CentOS-Base.repo
# Note, some rsyslog modules have dependancies in epel
RUN yum -y install epel-release
# Also switch yum config to use a base url for epel repo
RUN sed 's/^mirrorlist/#mirrorlist/g' -i /etc/yum.repos.d/epel.repo && \
  sed 's/^#baseurl/baseurl/g' -i /etc/yum.repos.d/epel.repo
RUN yum --setopt=timeout=120 -y update && \
  yum clean all

# Install Rsyslog. For http://rpms.adiscon.com/v8-stable/rsyslog.repo
# - It has gpgcheck=0
# - Adiscon doens't offer an HTTPS endpoint for the above file :-/
# - The GPG key is at http://rpms.adiscon.com/RPM-GPG-KEY-Adiscon, so also not secure to download and trust
# Therefore, prebundle our own local copy of the repo and GPG file
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon /etc/pki/rpm-gpg/RPM-GPG-KEY-Adiscon
COPY etc/yum.repos.d/rsyslog.repo /etc/yum.repos.d/rsyslog.repo
RUN yum --setopt=timeout=120 -y --enablerepo=epel install rsyslog rsyslog-relp rsyslog-kafka && \
  yum clean all && \
  rm -r /etc/rsyslog.d/ && \
  rm /etc/rsyslog.conf

# Install confd
ENV CONFD_VER='0.11.0'
#ADD https://github.com/kelseyhightower/confd/releases/download/v${CONFD_VER}/confd-${CONFD_VER}-linux-amd64 /usr/local/bin/confd
COPY usr/local/bin/confd-0.11.0-linux-amd64 /usr/local/bin/confd
  # Use bundled file to avoid downloading all the time
RUN chmod +x /usr/local/bin/confd && \
  mkdir -p /etc/confd/conf.d && \
  mkdir -p /etc/confd/templates

# Embed custom org CA
COPY etc/pki/ca-trust/source/anchors /etc/pki/ca-trust/source/anchors
RUN update-ca-trust

# Copy rsyslog config templates (for confd)
COPY etc/confd /etc/confd

# Copy rsyslog config files
COPY etc/rsyslog.conf /etc/rsyslog.conf
COPY etc/rsyslog.d /etc/rsyslog.d

#TODO: default ENV vars for rsyslog config
# global
ENV rsyslog_global_ca_file='/etc/pki/tls/certs/ca-bundle.crt'
# input
ENV rsyslog_module_imtcp_stream_driver_auth_mode='anon'
  # 'anon' or 'x509/certvalid' or 'x509/name'
ENV rsyslog_module_imtcp_permitted_peer='["*"]'
ENV rsyslog_module_impstats_interval='300'

# output flags
ENV rsyslog_omfile_enabled=false
#ENV rsyslog_omkafka_enabled=true
#ENV rsyslog_omfwd=true
#TODO: check how not to lose/include orginal host if events are relayed
#TODO: check if it's possible to add/tag 5424 with metadata about syslog method used (e.g. strong auth, just SSL sever, weak udp security)
#TODO: 5424 format (rfc5424micro)?

# Note, forwarding config will probably be highly varied, so instead of trying to template it, we allow for that config to be red from a volume and managed by simply picking up from a forward ruleset

#TODO: understand which "stateful" runtime directories rsyslog should have in order to perist accross errors/container runs
VOLUME ['/var/log', '/var/spool/rsyslog', '/etc/pki/tls/rsyslog/', '/etc/rsyslog.d/forward', '/etc/rsyslog.d/file']
#TODO TLS folder
#TODO: which ports to expose
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

#TODO: entrypoint which first runs confd, validates rsyslog config, and then runs rsyslog
#TODO: also, decide if we will accept the signal to reload config without restarting the container

#confd -onetime -backend env
#rsyslogd -N1
COPY rsyslog.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/rsyslog.sh

ENTRYPOINT ["/usr/local/bin/rsyslog.sh"]
