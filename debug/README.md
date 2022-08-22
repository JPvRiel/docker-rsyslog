# Debug folder

Place to demo issues or limitations containerising rsyslog.

Issues:

- `imkafka_load`: [RHEL 8 OS family error creating kafka handle and thread #4966](https://github.com/rsyslog/rsyslog/issues/4966)
  - Demo's that the same RHEL 8 kafka issue is not AlmaLinux specific, but also and issue with RedHat and Rocky Linux.
  - Ubuntu 22.04 does not have this issue.
