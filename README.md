# cloud-config
> balenaCloud app which is usually preloaded into a balenaOS image to automatically join devices to the cloud using `config.json` data passed in from supported provider metadata service

## create keys
> [update](https://github.com/product-os/balena-concourse/tree/master/provision/app/console) local GPG keyring with public keys from GitHub

	git secret whoknows && git secret reveal -f

	[ -f .balena/secrets/id_ed25519 ] \
	  || ssh-keygen -o -a 100 -t ed25519 -f .balena/secrets/id_ed25519 -C 'os-config' -N ''

	PRIKEY_ED25519=$(cat .balena/secrets/id_ed25519 | openssl base64 | tr -d '\n')

	PUBKEY_ED25519=$(cat .balena/secrets/id_ed25519.pub)
	
	git secret add .balena/secrets/id_ed25519
	
	git secret hide


## deploy (manually)
> (e.g) staging

    git secret reveal -f

    image="$(yq e '.docker.builds[] | select(.args[]=="*staging*").docker_repo' .resinci.yml)"

    for ev in "$(yq e '.docker.builds[] | select(.args[]=="*staging*").args[]' .resinci.yml | sed 's/"/\\"/g')"; do eval export "${ev}"; done

    docker build -t ${image} \
      --build-arg "BALENA_APPS=${BALENA_APPS}" \
      --build-arg RESINRC_RESIN_URL \
      --secret id=balena-api-token,src=.balena/secrets/staging/balena_api_token.txt .
