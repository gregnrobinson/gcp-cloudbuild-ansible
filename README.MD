# Immutable Ansible Deployments

## Ansible Builder Pipeline

The `pipeline/builder` folder of this project contains the required files to build the Ansible builder image that will be the base container for executing `/usr/bin/ansible-playbook` on runtime.

The `pipeline/builder/cloudbuild.yaml` file has the following available substitutions.

```yaml
substitutions:
    _IMG_DEST: gcr.io/<PROJECT_ID>/ansible
```

## Ansible Runner Pipeline
Once the image has been created and stored in the container registry, it is sourced by the `cloudbuild.yaml` file in the `pipeline/runner` folder to execute ansible scripts against targets.

The `pipeline/runner/cloudbuild.yaml` file has the following available substitutions.

```yaml
substitutions:
    _PROJECT_ID: <PROJECT_ID>
    _LOCATION: northamerica-northeast1
    _BASE_IMG: gcr.io/<PROJECT_ID>/ansible
    _GCP_CRED_KIND: serviceaccount
    _KEY_RING: ansible-keyring #See Manage Credentials step
    _SSH_KEY: ansible-ssh-key #See Manage Credentials step
    _SA_KEY: ansible-sa-key #See Manage Credentials step
```

# Prerequisites

Create an environment variable named PROJECT_ID
```sh
export PROJECT_ID="<YOUR_PROJECT_ID>"
```

Install yq from [here](https://mikefarah.gitbook.io/yq/).

Run the `./setup.sh` script to replace the project ID in all the neccesary yaml files.

```yaml
./setup.sh
```

Enable the required API's so we can build and push images using CloudBuild.

```sh
gcloud services enable cloudbuild.googleapis.com --project ${PROJECT_ID}
gcloud services enable containerregistry.googleapis.com --project ${PROJECT_ID}
gcloud services enable storage.googleapis.com --project ${PROJECT_ID}
```

## Create KMS for Ansible Control Node

```sh
PROJECT_NUMBER=$(gcloud projects list --filter="$PROJECT_ID" --format="value(PROJECT_NUMBER)")
LOCATION="northamerica-northeast1"
KEY_RING="ansible-keyring"


gcloud kms keyrings create $KEY_RING \
    --location $LOCATION

# Grant access to the key ring from Cloud Build Service Account
gcloud kms keys add-iam-policy-binding key \
    --keyring $KEY_RING \
    --location $LOCATION \
    --member `${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com` \
    --role roles/cloudkms.cryptoKeyDecrypter
```

## Create and Encrypt Service Account with KMS

```sh
LOCATION="northamerica-northeast1"
KEY_RING="ansible-keyring"
KEY="ansible-sa-key"
SA_ACCOUNT_ID="ansible-automation"
SA_DESCRIPTION="Used for executing Ansible scripts against"
SA_KEY_PATH="./config/credentials/service_account.json"

gcloud iam service-accounts create $SA_ACCOUNT_ID \
    --description=$DESCRIPTION \
    --display-name=$SA_ACCOUNT_ID
    
gcloud iam service-accounts keys create $SA_KEY_PATH \
    --iam-account=${SA_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:${SA_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/editor

gcloud kms keys create $KEY \
    --keyring $KEY_RING \
    --location $LOCATION \
    --purpose "encryption"

gcloud kms encrypt \
    --key $KEY  \
    --keyring $KEY_RING \
    --location $LOCATION  \
    --plaintext-file $SA_KEY_PATH \
    --ciphertext-file $SA_KEY_PATH.enc

rm -rf $SA_KEY_PATH
```

## Create and Encrypt SSH Private Key with KMS

```sh
LOCATION="northamerica-northeast1"
KEY_RING="ansible-keyring"
KEY="ansible-ssh-key"
SSH_KEY="ansible_rsa"
SSH_KEY_PATH="~/.ssh"

gcloud kms keys create $KEY \
    --keyring $KEY_RING \
    --location $LOCATION \
    --purpose "encryption"

ssh-keygen -t rsa -f $SSH_KEY -C ansible
chmod 400 $SSH_KEY

gcloud kms encrypt \
    --key ansible-ssh-key \
    --keyring $KEY_RING \
    --location $LOCATION  \
    --plaintext-file $SSH_KEY \
    --ciphertext-file $SSH_KEY.enc

PUBLIC_KEY=$(cat $SSH_KEY.pub)
echo "ansible:$PUBLIC_KEY" >> ./config/credentials/public_keys

mv ansible_rsa.enc ./config/credentials
rm -rf ansible_rsa.pub ansible_rsa
```
# Building Locally

Install the `cloud-build-local` package with the following command.

```sh
gcloud components install cloud-build-local
```

Ensure the user/service account executing the pipeline has the required permissions. Storage Admin is for pushing and pulling images from GCR, as well as creating an image if it doesn't already exist.

  - Cloud Build Service Account
  - Storage Admin
  - KMS Key Decrypter

```sh
TYPE="user"
EMAIL="user@example.com"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member ${TYPE}:${SA_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/storage.admin

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member ${TYPE}:${SA_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/cloudbuild.builds.editor  
    
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member ${TYPE}:${SA_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/cloudkms.cryptoKeyEncrypterDecrypter
```

## Build the Ansible Builder Docker image.

Within the root of the directory run the following to build the image.

```sh
SHORT_SHA=$(git rev-parse --short HEAD)

cloud-build-local --config=./pipeline/builder/cloudbuild-local.yaml --substitutions _SHORT_SHA=$SHORT_SHA --dryrun=false --push .
```

## Run Ansible with the Ansible Builder Docker image.

Within the root of the directory run the following to build the image.

```sh
gcloud components install cloud-build-local

cloud-build-local --config=./pipeline/runner/cloudbuild.yaml --dryrun=false .
```

For debugging, the following flag can be applied to `cloud-build-local`

```sh
--write-workspace=./pipeline
```
