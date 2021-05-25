#!/usr/bin/env bash

set -e

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
      "$@"
}

config_from_metadata() {
    #shellcheck disable=SC2034,SC2039 # /bin/sh is a symbolic link to bash on balenaOS
    for url in "${metadata_urls[@]}"; do
        user_data="$(curl_with_opts "${url}")"
        [ -n "${user_data}" ] && echo "${user_data}" && break
    done
}

ssh_with_opts "os-config join '$(config_from_metadata)'"

exec balena-idle "$@"
