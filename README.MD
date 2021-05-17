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

Install the following packages:

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- [yq](https://mikefarah.gitbook.io/yq/)
- [Docker](https://docs.docker.com/engine/install/)

Run the following command to setup the Ansble runner on a new or existing Project.

```yaml
./setup.sh
```

A menu appear with a set of options, option `1` is for setting up the project and pushes a base ansible image to the container registry. 

***Note: Option `1` must be executed before options `2` and `3`. After option `1` has completed, options `2` and `3` can be repeated.***

```
Enter a Project ID (ctrl^c to exit): new-project-id
   _             _ _     _          ___       _ _     _           
  /_\  _ __  ___(_) |__ | | ___    / __\_   _(_) | __| | ___ _ __ 
 //_\\| '_ \/ __| | '_ \| |/ _ \  /__\// | | | | |/ _` |/ _ \ '__|
/  _  \ | | \__ \ | |_) | |  __/ / \/  \ |_| | | | (_| |  __/ |   
\_/ \_/_| |_|___/_|_.__/|_|\___| \_____/\__,_|_|_|\__,_|\___|_|   
                                                                  
Version: 0.01
WARNING: The project ID entered does not exist, it will be created.

     1. Setup
     2. Build Ansible
     3. Run Ansible
     0. Exit

     enter choice [ 1 | 2 | 3 | 0 ]: 0
```

# Operations
## Building Ansible
Within the root of the directory run the following to build the Ansible container image.

```sh
export PROJECT_ID="<PROJECT_ID>"
export SHORT_SHA=$(git rev-parse --short HEAD)

bash setup.sh
```

## Running Ansible
Within the root of the directory run the following to build the Ansible container image.

```sh
export PROJECT_ID="<PROJECT_ID>"

bash setup.sh yaml_substitutions
bash setup.sh run_ansible
```
