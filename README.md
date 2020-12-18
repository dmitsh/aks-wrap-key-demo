# Demo: wrapped key in AKS with AKV

### Use case

* A user wraps (encrypts) a symmetric key with a public key
* The wrapped key is stored in AKV
* The user deploys AKS cluster and provisions corresponding private key in the container (to be implemented by SKR)
* The wrapped key is mounted using [Azure Secrets Store CSI](https://docs.microsoft.com/en-us/azure/key-vault/general/key-vault-integrate-kubernetes)
* The application flow within the contained unwraps the symetric key and decrypts data

### Prerequisites
* Running docker engine
* An Azure Service Principal
* An AKV instance configured to allow acces for the Service Principal

### Demo
Initialize environment:
- export service principal id and password (SP_ID, SP_PWD)
- export tenant id (TENANT_ID)
- export keyvault name (KV_NAME)
- optionally, export resource group name (RGROUP), deployment location (LOC), and AKS cluster name (AKS)
```sh
export SP_ID=<service principal id>
export SP_PWD=<service principal password>
export TENANT_ID=<tenant id>
export KV_NAME=<keyvault name>
```

Create AKS cluster:
```sh
make create-cluster
```

Generate keys and encrypt data:
```sh
make create-keys
```

Deploy dependencies and user application:
```sh
make bootstrap-cluster
```

Run the test scenario:
```sh
make test
```

You should expect the following output:
```sh
$ make test
./scripts/demo.sh -t
Run test
Test passed
```

Clean up:
```sh
make delete-cluster
make clean
```
