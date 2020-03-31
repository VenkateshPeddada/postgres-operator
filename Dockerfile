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
RUN mkdir -p /operator && chown -R 1010:0 /operator && mkdir -p /odev && chown -R 1010:0 /odev && \
	mkdir -p /odev/bin && chown -R 1010:0 /odev/bin && \
    touch /operator/rbac.yml && touch /operator/secret-backrest.yaml && touch /operator/secret-pgo-user.yaml && \
	touch /operator/deployment.yaml && touch /operator/service.yaml && touch /operator/pgo.yaml && touch /operator/pgo-client.yaml

# Copy other dependency files
RUN mkdir -p /operator/conf && mkdir -p /operator/bin && \
	mkdir -p /operator/deploy 

ADD conf /operator/conf
ADD bin /operator/bin
ADD deploy /operator/deploy
ADD Makefile /Makefile


# Define appropriate file ownership and permissions
RUN chmod +x /entrypoint.sh && chmod ugo+rwx /operator/rbac.yml && chmod ugo+rwx /operator/secret-backrest.yaml && \
    chmod ugo+rwx /operator/secret-pgo-user.yaml && chmod ugo+rwx /operator/deployment.yaml && chmod ugo+rwx /operator/service.yaml && \
    chmod ugo+rwx /operator/pgo.yaml && chmod ugo+rwx /operator/pgo-client.yaml && \
	chown -R 1010:0 /operator/conf && chown -R 1010:0 /operator/bin && chown -R 1010:0 /operator/deploy && \
    chmod ugo+rwx /Makefile && \
	chmod ugo+rwx /operator/deploy/crd.yaml && chmod ugo+rwx /operator/deploy/pgorole-pgoadmin.yaml && \
	chmod ugo+rwx /operator/deploy/pgouser-admin.yaml && chmod ugo+rwx /operator/deploy/cluster-roles.yaml && \
	chmod ugo+rwx /operator/deploy/service-accounts.yaml && chmod ugo+rwx /operator/deploy/cluster-role-bindings.yaml && \
	chmod ugo+rwx /operator/deploy/roles.yaml && chmod ugo+rwx /operator/deploy/role-bindings.yaml && \
	chmod ugo+rwx /operator/deploy/gen-api-keys.sh && chmod ugo+rwx /operator/deploy/gen-sshd-keys.sh


# Install Dependecies
RUN microdnf install golang && \ 
	curl -S https://s3.amazonaws.com/bitly-downloads/nsq/nsq-1.1.0.linux-amd64.go1.10.3.tar.gz | \
	tar xz --strip=2 -C /operator/bin/pgo-event/ '*/bin/*' 
	
RUN	curl -S https://raw.githubusercontent.com/golang/dep/master/install.sh | sh && \
	microdnf install git && \
	go get github.com/blang/expenv

# Use the default user with UID of 1010 (inherited from the Broadcom base image)
USER 1010

# Set working directory
WORKDIR /

# Run entrypoint
ENTRYPOINT [ "/entrypoint.sh" ]
