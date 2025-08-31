#!/usr/bin/env bash

set -ex

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

function get_device() {
    local label
    label=${1-resin-boot}
    devices="$(blkid | grep "${label}" | awk -F':' '{print $1}' | tr '\n' ' ')"
    for device in $devices; do
        if [[ "${device}" == *mapper* ]]; then
            continue
        else
            echo "${device}"
        fi
    done
}

function mount_host() {
    local tmpmnt
    tmpmnt="$(mktemp -d)"
    local device
    device="${1:-$(get_device)}"
    mount "${device}" "${tmpmnt}"
    echo "${tmpmnt}"
}

function curl_with_opts() {
    args=("$@")
    curl --silent --connect-timeout 3 "${args[@]}"
}

function config_from_metadata() {
    # shellcheck disable=SC2034,SC2039 # /bin/sh is a symbolic link to bash on balenaOS
    for metadata_url in "${metadata_urls[@]}"; do
        local token  # IMDSv2
        token="$(curl_with_opts --fail -X PUT "http://169.254.169.254/latest/api/token" \
          -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"

        local url
        url="$(echo "${metadata_url}" | awk -F';' '{print $1}')"

        local headers
        headers="$(echo "${metadata_url}" | awk -F';' '{print $2}')"

        if [[ -n "$token" ]]; then
            # shellcheck disable=SC2206
            headers=(${headers} -H "X-aws-ec2-metadata-token: ${token}")
        fi

        response="$(curl_with_opts --fail "${headers[@]}" "${url}" || echo '{}')"

        # only Azure responses are (currently) base64 encoded
        if [[ "${url}" =~ metadata/instance/compute/userData ]]; then
            user_data="$(echo "${response}" | base64 -d)"
        else
            user_data="${response}"
        fi

        openssh_key="$(aws_openssh_key_from_metadata)"
        if [[ -n "$openssh_key" ]]; then
            user_data="$(echo "${user_data}" | jq -re --arg pub_key "${openssh_key}" '.os.sshKeys += [$pub_key]')"
        fi

        if [ -n "${user_data}" ] && echo "${user_data}" | jq -e . >/dev/null; then
            echo "${user_data}" | jq -r '.cloudConfig="done"'
            break
        fi
    done
}

# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/building-shared-amis.html#public-amis-install-credentials
# https://docs.aws.amazon.com/marketplace/latest/userguide/product-and-ami-policies.html#ami-security
function aws_openssh_key_from_metadata() {
    tmpkey="$(mktemp)"

    # try IMDSv2?
    local token
    token="$(curl_with_opts --fail -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")"

    curl_with_opts http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key \
      -H "X-aws-ec2-metadata-token: $token" >"${tmpkey}"

    if [[ -s "$tmpkey" ]] ; then
        cat <"${tmpkey}"
    else
        # .. IMDSv1
        curl_with_opts http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key
    fi
    rm -f "${tmpkey}"
}


tmpmnt="$(mount_host)"
tmpconf="$(mktemp)"
config_from_metadata >"${tmpconf}"

if [[ -f "${tmpmnt}/config.json" ]] && [[ -f "${tmpconf}" ]]; then
    status="$(cat <"${tmpmnt}/config.json" | jq -r '.cloudConfig')"
    if ! [[ "${status}" =~ ^done$ ]]; then
        cat <"${tmpconf}" >"${tmpmnt}/config.json"
    fi
    cleanup "${tmpmnt}" && balena-idle
fi
