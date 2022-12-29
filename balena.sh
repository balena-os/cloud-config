#!/usr/bin/env bash

set -ex

devices="$(blkid | grep resin-boot | awk -F':' '{print $1}' | tr '\n' ' ')"
for device in $devices; do
    if [[ "${device}" == *mapper* ]]; then
        continue
    else
        echo "${device}"
    fi
done

metadata_urls=(
  'http://169.254.169.254/latest/user-data'
  'http://169.254.169.254/metadata/v1/user-data'
  'https://metadata.platformequinix.com/userdata'
)

function cleanup() {
   (sync && umount "${1}") || true
}

trap 'cleanup ${tmpmnt}' EXIT

function mount_boot() {
    local tmpmnt
    tmpmnt="$(mktemp -d)"
    mount "${1}" "${tmpmnt}"
    echo "${tmpmnt}"
}

function curl_with_opts() {
    curl --fail --silent --connect-timeout 3 "$@"
}

function reboot_device() {
    cleanup "${tmpmnt}"

    curl_with_opts --retry 3 \
      -X POST "${BALENA_SUPERVISOR_ADDRESS}/v1/reboot?apikey=${BALENA_SUPERVISOR_API_KEY}" \
      -H 'Content-Type: application/json' | jq -r
}

function config_from_metadata() {
    #shellcheck disable=SC2034,SC2039 # /bin/sh is a symbolic link to bash on balenaOS
    for url in "${metadata_urls[@]}"; do
        user_data="$(curl_with_opts "${url}")"

        if [ -n "${user_data}" ]; then
            echo "${user_data}" | jq -r '.cloudConfig="done"'
            break
        fi
    done
}

tmpmnt="$(mount_boot "${device}")"
tmpconf="$(mktemp)"
config_from_metadata > "${tmpconf}"

if [[ -f "${tmpmnt}/config.json" ]] && [[ -f "${tmpconf}" ]]; then
    cloud_config="$(cat < "${tmpmnt}/config.json" | jq -r '.cloudConfig')"
    if ! [[ "${cloud_config}" =~ ^done$ ]]; then
        cat < "${tmpconf}" > "${tmpmnt}/config.json" && reboot_device
    else
        cleanup "${tmpmnt}" && balena-idle
    fi
fi
