#!/bin/bash

set -e

RGROUP="${RGROUP:-demo-rg}"
LOC="${LOC:-westus}"
AKS="${AKS:-demo}"

function on_error {
  echo $1
  exit 1
}

[[ ! -z "$SP_ID" ]]     || on_error "SP_ID is not set"
[[ ! -z "$SP_PWD" ]]    || on_error "SP_PWD is not set"
[[ ! -z "$TENANT_ID" ]] || on_error "TENANT_ID is not set"
[[ ! -z "$KV_NAME" ]]   || on_error "KV_NAME is not set"

function create_cluster {
  echo "Create cluster"
  az group create -n $RGROUP -l $LOC

  az aks create \
    --resource-group $RGROUP \
    --name $AKS \
    --service-principal ${SP_ID} \
    --client-secret ${SP_PWD} \
    --ssh-key-value /Users/dima/.ssh/id_rsa_test.pub \
    --node-count 1 \
    --vm-set-type VirtualMachineScaleSets

  az aks get-credentials -g $RGROUP -n $AKS -f ~/${AKS}.kconfig

  kubectl --kubeconfig ~/${AKS}.kconfig create ns csi
  helm --kubeconfig ~/${AKS}.kconfig repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
  helm --kubeconfig ~/${AKS}.kconfig -n csi install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure
  kubectl --kubeconfig ~/${AKS}.kconfig -n csi get po

  kubectl --kubeconfig ~/${AKS}.kconfig create secret generic secrets-store-creds --from-literal clientid=${SP_ID} --from-literal clientsecret=${SP_PWD}
}

function create_keys {
  local openssl="docker run --rm -it -v $PWD:/data alpine/openssl"

  echo "Create symmetric key"
  $openssl rand -base64 128 > symkey.bin

  echo "Create self-signed certificate"
  $openssl req -x509 -newkey rsa:4096 -keyout /data/key.pem -out /data/cert.pem -days 365 -nodes -subj "/C=US/ST=WA/L=Seattle/O=Company/OU=Org/CN=www.example.com"
  $openssl x509 -pubkey -noout -in /data/cert.pem > pubkey.pem

  echo "Wrap symmetric key"
  $openssl rsautl -encrypt -inkey /data/pubkey.pem -pubin -in /data/symkey.bin -out /data/symkey.bin.enc

  echo "Encrypt secret data"
  $openssl enc -e -aes-256-cbc -salt -a -md sha512 -pbkdf2 -iter 100000 -pass file:/data/symkey.bin -in /data/secret.txt -out /data/secret.txt.enc
}

function bootstrap_cluster {
  cat > ./deployment/configmap.yml <<EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: data
data:
  run-test.sh: |
    #!/bin/bash
    set -e
    base64 -d /opt/secrets-store/symkey-wrap | openssl rsautl -decrypt -inkey /opt/data/key.pem -out /tmp/symkey.bin
    openssl enc -d -aes-256-cbc -salt -a -md sha512 -pbkdf2 -iter 100000 -pass file:/tmp/symkey.bin -in /opt/data/secret.txt.enc -out /tmp/secret.dec.txt
  key.pem: |
$(awk '{print "    ", $0}' ./key.pem)
  secret.txt.enc: |
$(awk '{print "    ", $0}' ./secret.txt.enc)
EOF

  os=$(uname -s)
  if [ "$os" = "Darwin" ]; then
    sed -i'.bak' "s/keyvaultName:.*/keyvaultName: \"$KV_NAME\"/g" ./deployment/secretproviderclass.yml
    sed -i'.bak' "s/tenantId:.*/tenantId: \"$TENANT_ID\"/g" ./deployment/secretproviderclass.yml
  else
    sed -i "s/keyvaultName:.*/keyvaultName: \"$KV_NAME\"/g" ./deployment/secretproviderclass.yml
    sed -i "s/tenantId:.*/tenantId: \"$TENANT_ID\"/g" ./deployment/secretproviderclass.yml
  fi

  echo "Store wrapped symmetric key in KV"
  az keyvault secret set --vault-name ${KV_NAME} --name "symkey-wrap" --value "$(base64 symkey.bin.enc)"

  echo "Deploy in Kubernetes"
  kubectl --kubeconfig ~/${AKS}.kconfig apply -f ./deployment/secretproviderclass.yml
  kubectl --kubeconfig ~/${AKS}.kconfig apply -f ./deployment/configmap.yml
  kubectl --kubeconfig ~/${AKS}.kconfig apply -f ./deployment/user-pod.yml
}

function run_test {
  echo "Run test"
  kubectl --kubeconfig ~/${AKS}.kconfig exec -it demo-pod -- /bin/bash -c \
    'cp /opt/data/run-test.sh /tmp && chmod 755 /tmp/run-test.sh && /tmp/run-test.sh'
  kubectl --kubeconfig ~/${AKS}.kconfig cp default/demo-pod:/tmp/secret.dec.txt ./secret.dec.txt
  if cmp secret.txt secret.dec.txt; then
    echo "Test passed"
  else
    echo "Test failed"
  fi
}

function delete_cluster {
  echo "Delete cluster"
  rm -f ~/${AKS}.kconfig
  az group delete -n $RGROUP -y --no-wait
}

while getopts ":ckbtd" opt; do
  case $opt in
    c)
      create_cluster
      ;;
    k)
      create_keys
      ;;
    b)
      bootstrap_cluster
      ;;
    t)
      run_test
      ;;
    d)
      delete_cluster
      ;;
    *)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done
