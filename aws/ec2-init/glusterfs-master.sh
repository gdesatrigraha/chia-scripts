#!/usr/bin/env bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -x

sudo apt update
sudo apt install -y git unzip jq

if [ -n "${aws_region}" ]; then
  echo "${aws_region}" | tee "${HOME}/aws_region"
fi

git clone 'https://github.com/dijedodol/chia-scripts.git' "${HOME}/chia-scripts"
(sudo crontab -u "${USER}" -l ; echo '0 * * * * cd "${HOME}/chia-scripts"; git fetch origin master; git checkout master; git merge origin/master') | sudo crontab -u "${USER}" -
cd "${HOME}/chia-scripts"
. constants.sh

# prepare ssh for inter glusterfs server comm
tee -a "${HOME}/.ssh/config" > /dev/null <<EOF
Host *
    StrictHostKeyChecking no
EOF
tee -a "${HOME}/.ssh/authorized_keys" > /dev/null < ssh-keys/glusterfs/id_rsa.pub
cp -f ssh-keys/glusterfs/id_rsa "${HOME}/.ssh/id_rsa"
chmod 600 "${HOME}/.ssh/config" "${HOME}/.ssh/authorized_keys"
chmod 400 "${HOME}/.ssh/id_rsa"

glusterfs/install.sh
glusterfs/mount-disks.sh

sudo systemctl enable glusterd
sudo systemctl start glusterd
sudo systemctl status glusterd

(sudo crontab -u "${USER}" -l ; echo '* * * * * cd "${HOME}/chia-scripts"; glusterfs/mount-disks.sh cron') | sudo crontab -u "${USER}" -

sudo hostnamectl set-hostname glusterfs-master

# TODO: GOTTA HANDLE WHEN VM WAS STARTING, BUT THERE IS NO DISK ATTACHED YET
sudo mkdir -p /tmp-gshare/data
sudo gluster volume create gv-chia "${glusterfs_master_host}:/tmp-gshare/data" force
sudo gluster volume set gv-chia storage.owner-uid 1000
sudo gluster volume set gv-chia storage.owner-gid 1000
sudo gluster volume start gv-chia

for gshare_dir in /gshare/*; do
  sudo gluster volume add-brick gv-chia "${glusterfs_master_host}:${gshare_dir}/data" force
done
volume remove-brick gv-chia "${glusterfs_master_host}:/tmp-gshare/data" start
sleep 10s
volume remove-brick gv-chia "${glusterfs_master_host}:/tmp-gshare/data" commit
