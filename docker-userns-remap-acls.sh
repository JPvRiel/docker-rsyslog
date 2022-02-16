#!/usr/bin/env bash
set -e

# Set to anything other than 'false' to enable
: "${ADD_USERNS_REMAP_USER_AND_GROUP_NAMES:=true}"

# Ensure all files and dirs owned by current host user
sudo chown -R "$(id -u):$(id -g)" ./*

# Get the base/root rempped UID and GID
dockremap_root_uid=$(grep dockremap /etc/subuid | cut -d ':' -f 2)
dockremap_root_gid=$(grep dockremap /etc/subgid | cut -d ':' -f 2)

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
    echo "Docker remapped uids and gids have been made recongnisable on the host with entries in /etc/passwd and /etc/group"
fi

# Calculate the remapped standard normal user
user_uid=1000
user_gid=1000
dockremap_user_uid=$((dockremap_root_uid + user_uid))
dockremap_user_gid=$((dockremap_root_gid + user_gid))
# Ensure all the parent dirs premits the remapped root UID with rX access or else a stat while mounting rootfs can run into "permission denied: unknown."
base_dir="$(pwd)"
parent_dir_chain=(${base_dir//\// })
parent_dirs=()
accum_path=''
for d in ${parent_dir_chain[@]}; do
  accum_path="$accum_path/$d"
  parent_dirs+=("$accum_path")
  if ! sudo -u "#$dockremap_root_uid" test -x "$accum_path"; then
    echo "Adding exec permission for $dockremap_root_uid to '$accum_path'"
    sudo setfacl --modify "u:$dockremap_root_uid:X,g:$dockremap_root_gid:X" "$accum_path"
  fi
done
echo "Exec permissions checked for all parent dirs: ${parent_dirs[*]}"
echo "Validate with the follwoing command: namei -l $(pwd)"
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
echo "Extended ACLs set for various test dirs to permit the bind mounting of host dirs to the remapped docker user namespace subuids."