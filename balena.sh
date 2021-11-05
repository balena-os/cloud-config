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
        [ -n "${user_data}" ] && echo "${user_data}" && break
    done
}

tmpmnt="$(mount_boot "${device}")"
tmpconf="$(mktemp)"
config_from_metadata > "${tmpconf}"

if [[ -f "${tmpmnt}/config.json" ]] && [[ -f "${tmpconf}" ]]; then
    device_api_key="$(cat < "${tmpmnt}/config.json" | jq -r .deviceApiKey)"
    if [[ "${device_api_key}" =~ null|^$ ]]; then
		cat < "${tmpconf}" > "${tmpmnt}/config.json"
	else
		app_id="$(cat < "${tmpconf}" | jq -r .applicationId)"
		if [[ -n "${app_id}" ]]; then
			if [[ "${RESIN_APP_ID}" != "${app_id}" ]]; then
				cat < "${tmpconf}" > "${tmpmnt}/config.json" \
				  && curl -sX POST "${BALENA_SUPERVISOR_ADDRESS}/v1/reboot?apikey=${BALENA_SUPERVISOR_API_KEY}" \
				  --header 'Content-Type:application/json'
			fi
		fi
	fi
fi

exec balena-idle "$@"
