create-cluster:
	./scripts/demo.sh -c

create-keys:
	./scripts/demo.sh -k

bootstrap-cluster:
	./scripts/demo.sh -b

test:
	./scripts/demo.sh -t

delete-cluster:
	./scripts/demo.sh -d

clean:
	rm -f cert.pem key.pem pubkey.pem symkey.bin symkey.bin.enc secret.txt.enc secret.dec.txt deployment/configmap.yml deployment/*.bak

.PHONY: create-cluster create-keys bootstrap-cluster test delete-cluster clean
