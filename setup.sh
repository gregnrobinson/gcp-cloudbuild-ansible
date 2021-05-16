#!/bin/bash
set -o errexit
set -o pipefail

yaml_substitutions(){
    export PROJECT_ID=$PROJECT_ID
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
    echo read "Environment ready... Would you like to build the Ansible Docker image now? (y/n): " yesno
    read yesno

    if [[ $yesno == "y" ]]; then
        SHORT_SHA=$(git rev-parse --short HEAD)

        gcloud components install cloud-build-local || echo "cloud-build-local already installed"

        cloud-build-local --config=./pipeline/builder/cloudbuild-local.yaml --substitutions _SHORT_SHA=$SHORT_SHA --dryrun=false --push .
    else exit 0
    fi
}

run_ansible(){
    echo read "Would you like to execute ansible playbooks? (y/n): " yesno
    read yesno

    if [[ $yesno == "y" ]]; then
        gcloud components install cloud-build-local || echo "cloud-build-local already installed"

        cloud-build-local --config=./pipeline/runner/cloudbuild.yaml --dryrun=false .
    else exit 0
    fi
}

"$@"

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

    gcloud iam service-accounts create $KMS_ACCOUNT_ID \
        --description="$KMS_DESCRIPTION" \
        --display-name=$KMS_ACCOUNT_ID

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
}

create_ssh_key(){
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
}

title="Ansible Runner 0.1"

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
echo "Enter a Project ID (ctrl^c to exit): "
read PROJECT_ID_INPUT

EXISTS=$(gcloud projects list --filter="lifecycleState:${PROJECT_ID_INPUT}" 2>&1)

#if [[ $EXISTS == *"0"* ]]; then
#    echo "This project does not appear to exist, would you like to create it (y/n) :"
#    read yesno
#    if [[ $yesno == "y" ]]; then
#      export PROJECT_ID="$PROJECT_ID_INPUT"
#      NEW_PROJECT="true"
#      setup
#    fi
#else
#  NEW_PROJECT="false"
#  setup
#fi
if [[ $EXISTS == *"0"* ]]; then
    export NEW_PROJECT="true"
    export PROJECT_ID="$PROJECT_ID_INPUT"
    numchoice=1

    while [ $numchoice != 0 ]; do
     
     cat ./config/logo.txt
     echo -n "
     1. First time setup
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
else
  NEW_PROJECT="false"
  setup
fi
}

main_menu
