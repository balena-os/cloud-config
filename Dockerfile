# syntax=docker/dockerfile:1

# https://github.com/product-os/ci-images/tree/master/pipelines/balena
FROM resinci/balena-x86_64-ubuntu

ARG BALENA_APPS
ARG RESINRC_RESIN_URL

WORKDIR /tmp/build

COPY . ./

RUN --mount=type=secret,id=balena-api-token set -eu \
    && sha="$(git rev-parse --short HEAD)" \
    && balena login --token "$(cat < /run/secrets/balena-api-token)" \
    && org="$(balena whoami | grep USERNAME | cut -c 11-)" \
    && (echo "${BALENA_APPS}" | jq -r --arg org "${org}" '.[] | .app + " -o " + $org + " --type " + .type' | xargs -n 5 balena app create || true) \
    && echo "${BALENA_APPS}" | jq -r --arg org "${org}" --arg sha "${sha}" '.[] | $org + "/" + .app + " --release-tag git-commit " + $sha' | xargs -n 4 balena push
