ARG BASE_IMAGE=alpine:edge
FROM ${BASE_IMAGE}

WORKDIR /opt

COPY ./config/ .

ARG ANSIBLE_VERSION=2.7.0-r1

RUN echo "Installing/Updating Ansible"
RUN apk add --update ansible openssh-client py-pip && \
    pip install requests google-auth && \
    rm -rf /var/cache/apk/* && \
    mkdir -p ansible/inventory/ && \
    mkdir -p ansible/roles/

RUN echo "Copy Ansible Config"
RUN cp ansible.cfg ansible/ && \
    cp -r ./inventory/. ./ansible/inventory && \
    cp -r ./roles/. ./ansible/roles && \
    ls -al ./ansible/inventory && \
    chmod -R 755 ansible/ 

ENTRYPOINT ["/usr/bin/ansible-playbook"]