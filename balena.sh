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

# 1. AWS
# 2. DigitalOcean
# 3. Azure
# 4. Equinix
metadata_urls=(
  'http://169.254.169.254/latest/user-data'
  'http://169.254.169.254/metadata/v1/user-data'
  'http://169.254.169.254/metadata/instance/compute/userData?api-version=2023-07-01&format=text;-H Metadata:true'
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

function config_from_metadata() {
    #shellcheck disable=SC2034,SC2039 # /bin/sh is a symbolic link to bash on balenaOS
    for metadata_url in "${metadata_urls[@]}"; do
        url="$(echo "${metadata_url}" | awk -F';' '{print $1}')"
        headers="$(echo "${metadata_url}" | awk -F';' '{print $2}')"
        response="$(curl_with_opts ${headers} "${url}")"

        user_data="${response}"       
        # Only the response from Azure is base64 encoded                  
        if [[ "${url}" =~ metadata/instance/compute/userData ]]; then
            user_data="$(echo "${response}" | base64 -d)"
        fi    
        
        if [ -n "${user_data}" ] && echo "${user_data}" | jq -e . > /dev/null; then
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
    cleanup "${tmpmnt}" && balena-idle
fi
