#!/bin/bash
set -o errexit
set -o pipefail

yaml_substitutions(){
    export PROJECT_ID=$PROJECT_ID_INPUT
    export IMG_DEST="gcr.io/${PROJECT_ID}/ansible"

    echo "Setting up inventory files..."
    yq eval '.projects[0] |= ''"'$PROJECT_ID'"' -i ./config/inventory/gcp.yaml
    yq eval '.gcp_project |= ''"'$PROJECT_ID'"' -i ./config/inventory/group_vars/all.yaml

    echo "Setting up builder pipeline files..."
    yq eval '.substitutions._IMG_DEST |= ''"'$IMG_DEST'"' -i ./pipeline/builder/cloudbuild-local.yaml
    yq eval '.substitutions._IMG_DEST |= ''"'$IMG_DEST'"' -i ./pipeline/builder/cloudbuild.yaml

    echo "Setting up runner pipeline files..."
    yq eval '.substitutions._PROJECT_ID |= ''"'$PROJECT_ID'"' -i ./pipeline/runner/cloudbuild.yaml
    yq eval '.substitutions._BASE_IMG |= ''"'$IMG_DEST'"' -i ./pipeline/runner/cloudbuild.yaml
}

build_ansible(){
    export PROJECT_ID=$PROJECT_ID_INPUT
    SHORT_SHA=$(git rev-parse --short HEAD)

    if [[ -e "./config/credentials/*.enc" ]] && [[ -e "./config/credentials/*.json.enc" ]]; then
        echo "Encrypted credetials found..."
        echo "Building Ansible Container..."
        gcloud components install cloud-build-local || echo "cloud-build-local already installed"
        cloud-build-local --config=./pipeline/builder/cloudbuild-local.yaml --substitutions _SHORT_SHA=$SHORT_SHA --dryrun=false --push .
    else
        echo "Encrypted credetials not found in ./config/credentials folder... creating..."
        echo "Creating new encrypted SSH private key..."
        create_sa_key
        create_ssh_key
        echo "Building Ansible Container..."
        gcloud components install cloud-build-local || echo "cloud-build-local already installed"
        cloud-build-local --config=./pipeline/builder/cloudbuild-local.yaml --substitutions _SHORT_SHA=$SHORT_SHA --dryrun=false --push .
    fi
}

run_ansible(){
    export PROJECT_ID=$PROJECT_ID_INPUT
    gcloud components install cloud-build-local || echo "cloud-build-local already installed"
    cloud-build-local --config=./pipeline/runner/cloudbuild.yaml --dryrun=false .
}

create_kms_keyring(){
    LOCATION="northamerica-northeast1"
    KEY_RING="ansible-keyring"

    gcloud kms keyrings create $KMS_KEY_RING \
        --location $LOCATION
}

export LOCATION="northamerica-northeast1"  
export KMS_ACCOUNT_ID="ansible-automation"
export KMS_DESCRIPTION="Used for executing Ansible scripts against"
export KMS_KEY_RING="ansible-keyring"
export KMS_SA_KEY="ansible-sa-key"
export KMS_SSH_KEY="ansible-ssh-key"
export SSH_KEY="ansible_rsa"

create_sa_key(){
    KMS_SA_KEY_PATH="./config/credentials/service_account.json"

    EXISTS=$(gcloud iam service-accounts list --filter=$KMS_ACCOUNT_ID 2>&1)

    if [[ $EXISTS == *"Listed 0 items"* ]]; then
    echo "No service account found... creating..."

    gcloud iam service-accounts create $KMS_ACCOUNT_ID \
            --description="$KMS_DESCRIPTION" \
            --display-name=$KMS_ACCOUNT_ID

        if [[ -f "./config/credentials/*.json.enc" ]]; then
        echo "No encrypted service account file found... creating..."
        
        gcloud iam service-accounts keys create $KMS_SA_KEY_PATH \
            --iam-account=${KMS_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com

        gcloud projects add-iam-policy-binding $PROJECT_ID \
            --member serviceAccount:${KMS_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
            --role roles/editor

        gcloud kms keys create $KMS_SA_KEY \
            --keyring $KMS_KEY_RING \
            --location $LOCATION \
            --purpose "encryption"

        gcloud kms encrypt \
            --key $KMS_SA_KEY  \
            --keyring $KMS_KEY_RING \
            --location $LOCATION \
            --plaintext-file $KMS_SA_KEY_PATH \
            --ciphertext-file $KMS_SA_KEY_PATH.enc

        rm -rf $KMS_SA_KEY_PATH
        fi
    else
        echo "Found existing service account and encrypted files"
    fi
}

create_ssh_key(){
    if [[ -e "./config/credentials/*.enc" ]]; then
        gcloud kms keys create $KMS_SSH_KEY \
            --keyring $KMS_KEY_RING \
            --location $LOCATION \
            --purpose "encryption"

        ssh-keygen -t rsa -f $SSH_KEY -C ansible
        chmod 400 $SSH_KEY

        gcloud kms encrypt \
            --key $KMS_SSH_KEY \
            --keyring $KMS_KEY_RING \
            --location $LOCATION  \
            --plaintext-file $SSH_KEY \
            --ciphertext-file $SSH_KEY.enc

        PUBLIC_KEY=$(cat $SSH_KEY.pub)
        echo "ansible:$PUBLIC_KEY" >> ./config/credentials/public_keys

        mv ansible_rsa.enc ./config/credentials 
        rm -rf ansible_rsa.pub ansible_rsa
    else
        echo "Found existing SSH key..."
    fi
}

yaml_substitutions(){
    export IMG_DEST="gcr.io/${PROJECT_ID}/ansible"

    echo "Setting up inventory files..."
    yq eval '.projects[0] |= ''"'$PROJECT_ID'"' -i ./ansible/config/inventory/gcp.yaml
    yq eval '.gcp_project |= ''"'$PROJECT_ID'"' -i ./ansible/config/inventory/group_vars/all.yaml

    echo "Setting up builder pipeline files..."
    yq eval '.substitutions._IMG_DEST |= ''"'$IMG_DEST'"' -i ./ansible/pipeline/builder/cloudbuild-local.yaml
    yq eval '.substitutions._IMG_DEST |= ''"'$IMG_DEST'"' -i ./ansible/pipeline/builder/cloudbuild.yaml

    echo "Setting up runner pipeline files..."
    yq eval '.substitutions._PROJECT_ID |= ''"'$PROJECT_ID'"' -i ./ansible/pipeline/runner/cloudbuild.yaml
    yq eval '.substitutions._BASE_IMG |= ''"'$IMG_DEST'"' -i ./ansible/pipeline/runner/cloudbuild.yaml
}

"$@"

title="Ansible Runner 0.1"
#prompt="Would you like to setup Ansible Runner in a new or existing project?"
#options=("1 - New Project" "2 - Existing Project")
setup(){
  export PARENT_ID=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
  export PARENT_TYPE=$(gcloud projects describe ${PARENT_ID} --format="value(parent.type)")
  export BILLING_ACCOUNT=$(gcloud beta billing projects describe ${PARENT_ID} --format="value(billingAccountName)" | sed -e 's/.*\///g')
  export PARENT_FOLDER=$(gcloud projects describe ${PARENT_ID} --format="value(parent.id)")
  export PARENT_ORGANIZATION=$(gcloud organizations list --format="value(ID)")

  if [ "${NEW_PROJECT}" == "true" ]; then
    if [ "${PARENT_TYPE}" == "organization" ]; then
        echo "Creating project [$PROJECT_ID] under [${PARENT_ORGANIZATION}]..."
        gcloud projects create ${PROJECT_ID} --organization=${PARENT_FOLDER} > /dev/null
    else
        echo "Creating project [$PROJECT_ID] under [${PARENT_FOLDER}]..."
        gcloud projects create ${PROJECT_ID} --folder=${PARENT_FOLDER} > /dev/null
    fi

  gcloud beta billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT} > /dev/null

  gcloud services enable cloudbuild.googleapis.com --project ${PROJECT_ID}
  gcloud services enable containerregistry.googleapis.com --project ${PROJECT_ID}
  gcloud services enable storage.googleapis.com --project ${PROJECT_ID}
  gcloud services enable compute.googleapis.com --project ${PROJECT_ID}

  gcloud config set project ${PROJECT_ID}
  else
    echo "Project exists... Setting up environment"
  fi

  yaml_substitutions
  create_kms_keyring
  create_sa_key
  create_ssh_key
  build_ansible

  echo "Setup complete... Execute 'bash setup.sh run_ansible' to deploy Ansible Playbooks..."
}

"$@"

main_menu(){
printf 'Enter a Project ID (ctrl^c to exit): '
read -r PROJECT_ID_INPUT

LOGGED_IN=$(gcloud auth list 2>&1)

if [[ $LOGGED_IN == *"*"* ]]; then
export EXISTS=$(gcloud projects list --filter="${PROJECT_ID_INPUT}" 2>&1)
    if [[ $EXISTS == *"Listed 0 items"* ]]; then
        export NEW_PROJECT="true"
        export INFO="INFO: The project $PROJECT_ID_INPUT does not exist, it will be created..."
    else
        export NEW_PROJECT="false"
        export INFO="INFO: Using project $PROJECT_ID_INPUT..."
    fi
else
    echo "Not logged in... logging in..."
    gcloud auth login --no-launch-browser
    export EXISTS=$(gcloud projects list --filter="${PROJECT_ID_INPUT}" 2>&1)
    if [[ $EXISTS == *"Listed 0 items"* ]]; then
        export NEW_PROJECT="true"
        export INFO="INFO: The project $PROJECT_ID_INPUT does not exist, it will be created..."
    else
        export NEW_PROJECT="false"
        export INFO="INFO: Using project $PROJECT_ID_INPUT..."
    fi
fi

export PROJECT_ID=$PROJECT_ID_INPUT

numchoice=1
while [[ $numchoice != 0 ]]; do
    echo "$(cat ./config/logo.txt)"
    echo "Version: 0.01"
    echo $INFO
    echo -n "
    1. Setup
    2. Build Ansible
    3. Run Ansible
    0. Exit

    enter choice [ 1 | 2 | 3 | 0 ]: "
    read numchoice
    case $numchoice in
        "1" ) setup ;;
        "2" ) build_ansible ;;
        "3" ) run_ansible ;;
        "0" ) break ;;
        * ) echo -n "You entered an incorrect option. Please try again." ;;
    esac
done
}

main_menu