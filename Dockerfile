## Postgres Operator CI
FROM docker-release-local.artifactory-lvn.broadcom.net/broadcom-images/redhat/ubi-minimal:8

# Switch to root. Ensure entrypoint uses 1010 (inherited from the ubi standard image)
USER root

## Define build arguments and environment variables
# Note: Using kubectl version consistent with stable Kubernetes version used by GKE
# Download instructions at https://kubernetes.io/docs/tasks/tools/install-kubectl
ARG KUBECTL_VERSION="v1.15.5"
ARG KUBECTL_BINARY="/usr/local/bin/kubectl"
ENV OPERATOR_COMMAND=${OPERATOR_COMMAND}
ENV OPERATOR_IMAGES=${OPERATOR_IMAGES}
ENV OPERATOR_POD=${OPERATOR_POD}
ENV BACKUP_NAME=${BACKUP_NAME}
ENV CLUSTER_NAME=${CLUSTER_NAME}
ENV OPERATOR_IMAGES=${OPERATOR_IMAGES}
ENV RUN_TIME=${RUN_TIME}
ENV KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE}
ENV BASE_KUBERNETES_NAMESPACE=${BASE_KUBERNETES_NAMESPACE}
ENV BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT}
ENV BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN}
ENV GOPATH=/odev
ENV GOBIN=$GOPATH/bin
ENV PATH=$PATH:$GOBIN

# Install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && mv ./kubectl ${KUBECTL_BINARY}

# Add necessary files
ADD entrypoint.sh /entrypoint.sh
RUN mkdir -p /home/default/operator && chown -R 1010:1010 /home/default/operator && mkdir -p /odev && chown -R 1010:1010 /odev && \
	mkdir -p /odev/bin && chown -R 1010:1010 /odev/bin && \
    touch /home/default/operator/rbac.yml && touch /home/default/operator/secret-backrest.yaml && touch /home/default/operator/secret-pgo-user.yaml && \
	touch /home/default/operator/deployment.yaml && touch /home/default/operator/service.yaml && touch /home/default/operator/pgo.yaml && touch /home/default/operator/pgo-client.yaml

# Copy other dependency files
RUN mkdir -p /home/default/operator/conf && mkdir -p /home/default/operator/bin && \
	mkdir -p /home/default/operator/deploy 

ADD conf /home/default/operator/conf
ADD bin /home/default/operator/bin
ADD deploy /home/default/operator/deploy
ADD Makefile /Makefile


# Define appropriate file ownership and permissions
RUN chmod +x /entrypoint.sh && chmod ugo+rwx /home/default/operator/rbac.yml && chmod ugo+rwx /home/default/operator/secret-backrest.yaml && \
    chmod ugo+rwx /home/default/operator/secret-pgo-user.yaml && chmod ugo+rwx /home/default/operator/deployment.yaml && chmod ugo+rwx /home/default/operator/service.yaml && \
    chmod ugo+rwx /home/default/operator/pgo.yaml && chmod ugo+rwx /home/default/operator/pgo-client.yaml && \
	chown -R 1010:1010 /home/default/operator/conf && chown -R 1010:1010 /home/default/operator/bin && chown -R 1010:1010 /home/default/operator/deploy && \
	chmod -R ugo+rwx /home/default/operator/conf/* && chmod -R ugo+rwx /home/default/operator/bin/* && chmod -R ugo+rwx /home/default/operator/deploy/* && \
    chmod ugo+rwx /Makefile && \
	chmod ugo+rwx /home/default/operator/deploy/crd.yaml && chmod ugo+rwx /home/default/operator/deploy/pgorole-pgoadmin.yaml && \
	chmod ugo+rwx /home/default/operator/deploy/pgouser-admin.yaml && chmod ugo+rwx /home/default/operator/deploy/cluster-roles.yaml && \
	chmod ugo+rwx /home/default/operator/deploy/service-accounts.yaml && chmod ugo+rwx /home/default/operator/deploy/cluster-role-bindings.yaml && \
	chmod ugo+rwx /home/default/operator/deploy/roles.yaml && chmod ugo+rwx /home/default/operator/deploy/role-bindings.yaml && \
	chmod ugo+rwx /home/default/operator/deploy/gen-api-keys.sh && chmod ugo+rwx /home/default/operator/deploy/gen-sshd-keys.sh


# Install Dependecies
RUN microdnf install golang 

# Manually included in /home/default/operator/bin/pgo-event
#	curl -S https://s3.amazonaws.com/bitly-downloads/nsq/nsq-1.1.0.linux-amd64.go1.10.3.tar.gz | \
#	tar xz --strip=2 -C /home/default/operator/bin/pgo-event/ '*/bin/*' 
	
RUN	curl -S https://raw.githubusercontent.com/golang/dep/master/install.sh | sh && \
	microdnf install git && \
	go get github.com/blang/expenv

# Use the default user with UID of 1010 (inherited from the Broadcom base image)
USER 1010

# Set working directory
WORKDIR /

# Run entrypoint
ENTRYPOINT [ "/entrypoint.sh" ]
