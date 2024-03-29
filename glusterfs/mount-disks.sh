#!/usr/bin/env bash
set -x

expected_fs='xfs'

mount_and_update_fstab() {
  local dev_name="$1"
  local mount_point="$2"

  sudo mount "/dev/${dev_name}" "${mount_point}"
  sudo mkdir -p "${mount_point}/data"

  fstab_count="$(grep -cF "/dev/${dev_name}" /etc/fstab)"
  if [ "${fstab_count}" -gt 0 ]; then
    # update fstab, remove the same previous entry if exists
    temp_file="$(mktemp)"
    grep -vF "/dev/${dev_name}" /etc/fstab | tee "${temp_file}"
    echo "/dev/${dev_name} ${mount_point} ${expected_fs} defaults,nofail 0" | tee -a "${temp_file}" > /dev/null
    sudo tee /etc/fstab > /dev/null < "${temp_file}"
    rm -f "${temp_file}"
  else
    echo "/dev/${dev_name} ${mount_point} ${expected_fs} defaults,nofail 0" | sudo tee -a /etc/fstab > /dev/null
  fi
}

# mount any available disk
lsblk --json | jq -c '.blockdevices[] | select(.mountpoint == null and .type == "disk" and .children == null) | .name' | jq -r | while read -r dev_name; do
  sleep 1s
  echo "dev_name: ${dev_name}"
  sudo mkdir -p "/gshare/${dev_name}"

  fs="$(sudo blkid "/dev/${dev_name}" -o value -s TYPE)"
  if [ "${fs}" = "${expected_fs}" ]; then
    mount_and_update_fstab "${dev_name}" "/gshare/${dev_name}"
  elif [ -z "$fs" ]; then
    echo "formatting block_device because there is no filesystem detected on block_device: ${dev_name}"
    sudo mkfs -F -t "${expected_fs}" "/dev/${dev_name}"
    mount_and_update_fstab "${dev_name}" "/gshare/${dev_name}"
  else
    echo "skipping block_device: ${dev_name}, unexpected existing filesystem: ${fs}"
  fi
done
