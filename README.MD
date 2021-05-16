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

# Setup

Create an environment variable named PROJECT_ID
```sh
export PROJECT_ID="<YOUR_PROJECT_ID>"
```

Install the following packages:
- [yq](https://mikefarah.gitbook.io/yq/)
- [Docker](https://docs.docker.com/engine/install/)

Run the following command to setup the Ansble runner on a new or existing Project.

```yaml
./setup.sh
```

# Building Locally

Ensure the user/service account executing the pipeline has the required permissions. Storage Admin is for pushing and pulling images from GCR, as well as creating an image if it doesn't already exist.

  - Cloud Build Service Account `not applicable to cloud-build-local`
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

Within the root of the directory run the following to build the Ansible container image.
```sh
bash setup.sh build_ansible
```

# Running Locally

Within the root of the directory run the following command to execute playbooks.

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
