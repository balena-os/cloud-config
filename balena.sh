#!/usr/bin/env bash

set -ex

device="$(blkid | grep resin-boot | awk -F':' '{print $1}')"

function cleanup() {
   (sync && umount "${1}") || true
}

trap 'cleanup ${device}' SIGINT SIGTERM USR1 USR2 EXIT

function mount_boot() {
    local tmpmnt
    tmpmnt="$(mktemp -d)"
    mount "${1}" "${tmpmnt}"
    echo "${tmpmnt}"
}

metadata_urls=(
  'http://169.254.169.254/latest/user-data'
  'http://169.254.169.254/metadata/v1/user-data'
  'https://metadata.platformequinix.com/userdata'
)

curl_with_opts() {
    curl --fail --silent --connect-timeout 3 "$@"
}

config_from_metadata() {
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
		cat < "${tmpconf}" > "${tmpmnt}/config.json"
	fi
fi

exec balena-idle "$@"
