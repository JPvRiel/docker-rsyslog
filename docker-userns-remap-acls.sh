#!/usr/bin/env bash
set -e

# Set to anything other than 'false' to enable
: "${ADD_USERNS_REMAP_USER_AND_GROUP_NAMES:=false}"

# Get the base/root rempped UID and GID
dockremap_root_uid=$(grep dockremap /etc/subuid | cut -d ':' -f 2)
dockremap_root_gid=$(grep dockremap /etc/subuid | cut -d ':' -f 2)
# Calculate the remapped standard normal user
user_uid=1000
user_gid=1000
dockremap_user_uid=$((dockremap_root_uid + user_uid))
dockremap_user_gid=$((dockremap_root_gid + user_gid))
# Ensure the parent dir premits the remapped root UID with rX access or else a stat while mounting rootfs can run into "permission denied: unknown."
setfacl --modify "u:$dockremap_root_uid:X,g:$dockremap_root_gid:X" .
# Set ACL to permit read and/or write access to remapped docker root user
setfacl --recursive --modify "u:$dockremap_root_uid:rX,g:$dockremap_root_gid:rX" ./test/
setfacl --recursive --default --modify "u:$dockremap_root_uid:rX,g:$dockremap_root_gid:rX" ./test/
setfacl --recursive --modify "u:$dockremap_root_uid:rwX,g:$dockremap_root_gid:rwX" ./test/config_check/
setfacl --recursive --default --modify "u:$dockremap_root_uid:rwX,g:$dockremap_root_gid:rwX" ./test/config_check/
# Set ACL to permit read and/or write access to remapped docker normal user (uid 1000)
setfacl --recursive --modify "u:$dockremap_user_uid:rX,g:$dockremap_user_gid:rX" ./test/
setfacl --recursive --default --modify "u:$dockremap_user_uid:rX,g:$dockremap_user_gid:rX" ./test/
setfacl --recursive --modify "u:$dockremap_user_uid:rwX,g:$dockremap_user_gid:rwX" ./test/behave/reports/
setfacl --recursive --default --modify "u:$dockremap_user_uid:rwX,g:$dockremap_user_gid:rwX" ./test/behave/reports/
# Ensure own user has access
setfacl --recursive --modify "u:$(id -u):rwX,g:$(id -u):rwX" ./test/
setfacl --recursive --default --modify "u:$(id -u):rwX,g:$(id -u):rwX" ./test/
# Set ownership to the remapped docker root UID
sudo chown --recursive "$dockremap_root_uid:$dockremap_root_gid" ./test/
# Make remapped uids and gids recongnisable on the host?
if [ "$ADD_USERNS_REMAP_USER_AND_GROUP_NAMES" != 'false' ]; then
    if ! getent passwd dockremap-root; then
        sudo groupadd --system --gid "$dockremap_root_gid" dockremap-root
        sudo useradd --system --no-create-home --home-dir "/var/lib/docker/$dockremap_root_uid.$dockremap_root_gid" --shell /bin/false --uid "$dockremap_root_uid" --gid "$dockremap_root_gid" --comment 'userns remap for docker root' dockremap-root
    fi
    if ! getent passwd dockremap-user; then
        sudo groupadd --system --gid "$dockremap_user_gid" dockremap-user
        sudo useradd --system --no-create-home --home-dir "/var/lib/docker/$dockremap_root_uid.$dockremap_root_gid" --shell /bin/false --uid "$dockremap_user_uid" --gid "$dockremap_user_gid" --comment 'userns remap for docker user' dockremap-user
    fi
fi