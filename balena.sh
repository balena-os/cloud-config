#!/usr/bin/env bash

set -xa

metadata_urls=( \
  'http://169.254.169.254/latest/user-data' \
  'http://169.254.169.254/metadata/v1/user-data' \
  'https://metadata.platformequinix.com/userdata' \
)

curl_with_opts() {
    curl --fail --silent --connect-timeout 3 "$@"
}

ssh_with_opts() {
    ssh -p 22222 \
      "root@$(ip route | awk '/balena0|br-[0-9a-fA-F]/ { print $7 }' | head -n 1)" \
      -o 'StrictHostKeyChecking=no' \
      -o 'UserKnownHostsFile=/dev/null' \
      -o 'PasswordAuthentication=no' \
      -o 'ConnectTimeout=60' \
      "$@"
}

config_from_metadata() {
    #shellcheck disable=SC2034,SC2039 # /bin/sh is a symbolic link to bash on balenaOS
    for url in "${metadata_urls[@]}"; do
        user_data="$(curl_with_opts "${url}")"
        [ -n "${user_data}" ] && echo "${user_data}" && break
    done
}

if ssh_with_opts -t; then
    # requires SSH private key to be preloaded in the image (faster)
    uuid="$(ssh_with_opts "cat /mnt/boot/config.json | jq -r .uuid")"

    if [[ -z ${uuid} ]]; then
        ssh_with_opts "os-config join '$(config_from_metadata)'"
    fi
else
	# open fleet flow requires a reboot (slower)
    tmpmnt="$(mktemp -d)"
    device="$(blkid | grep resin-boot | awk -F':' '{print $1}')"
    mount "${device}" "${tmpmnt}"

    tmpconf="$(mktemp)"
    config_from_metadata > "${tmpconf}"
    app_id="$(cat < "${tmpconf}" | jq -r .applicationId)"

    if [[ "${RESIN_APP_ID}" != "${app_id}" ]]; then
        cat < "${tmpconf}" > "${tmpmnt}/config.json" \
          && sync \
          && umount "${device}" \
          && curl -X POST "${BALENA_SUPERVISOR_ADDRESS}/v1/reboot?apikey=${BALENA_SUPERVISOR_API_KEY}" \
          --header 'Content-Type:application/json'
    fi
fi

exec balena-idle "$@"
