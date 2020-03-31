## MySQL Operator CI
FROM centos:centos8.1.1911

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
ENV GOPATH=/root/odev
ENV GOBIN=$GOPATH/bin
ENV PATH=$PATH:$GOBIN

# Install kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && mv ./kubectl ${KUBECTL_BINARY}

# Add necessary files
ADD entrypoint.sh /entrypoint.sh
RUN mkdir -p /root/operator && chown -R 0:0 /root/operator && mkdir -p /root/odev && chown -R 0:0 /root/odev && \
	mkdir -p /root/odev/bin && chown -R 0:0 /root/odev/bin && \
    touch /root/operator/rbac.yml && touch /root/operator/secret-backrest.yaml && touch /root/operator/secret-pgo-user.yaml && \
	touch /root/operator/deployment.yaml && touch /root/operator/service.yaml && touch /root/operator/pgo.yaml && touch /root/operator/pgo-client.yaml

# Copy other dependency files
RUN mkdir -p /root/operator/conf && mkdir -p /root/operator/bin && \
	mkdir -p /root/operator/deploy 

ADD conf /root/operator/conf
ADD bin /root/operator/bin
ADD deploy /root/operator/deploy
ADD Makefile /Makefile


# Define appropriate file ownership and permissions
RUN chmod +x /entrypoint.sh && chmod ugo+rwx /root/operator/rbac.yml && chmod ugo+rwx /root/operator/secret-backrest.yaml && \
    chmod ugo+rwx /root/operator/secret-pgo-user.yaml && chmod ugo+rwx /root/operator/deployment.yaml && chmod ugo+rwx /root/operator/service.yaml && \
    chmod ugo+rwx /root/operator/pgo.yaml && chmod ugo+rwx /root/operator/pgo-client.yaml && \
	chown -R 0:0 /root/operator/conf && chown -R 0:0 /root/operator/bin && chown -R 0:0 /root/operator/deploy && \
#	chmod -R ugo+rwx /root/operator/conf/* && chmod -R ugo+rwx /root/operator/bin/* && chmod -R ugo+rwx /root/operator/deploy/* && \
    chmod ugo+rwx /Makefile && \
	chmod ugo+rwx /root/operator/deploy/crd.yaml && chmod ugo+rwx /root/operator/deploy/pgorole-pgoadmin.yaml && \
	chmod ugo+rwx /root/operator/deploy/pgouser-admin.yaml && chmod ugo+rwx /root/operator/deploy/cluster-roles.yaml && \
	chmod ugo+rwx /root/operator/deploy/service-accounts.yaml && chmod ugo+rwx /root/operator/deploy/cluster-role-bindings.yaml && \
	chmod ugo+rwx /root/operator/deploy/roles.yaml && chmod ugo+rwx /root/operator/deploy/role-bindings.yaml && \
	chmod ugo+rwx /root/operator/deploy/gen-api-keys.sh && chmod ugo+rwx /root/operator/deploy/gen-sshd-keys.sh


# Install Dependecies
RUN yum -y install golang && \ 
	curl -S https://s3.amazonaws.com/bitly-downloads/nsq/nsq-1.1.0.linux-amd64.go1.10.3.tar.gz | \
	tar xz --strip=2 -C /root/operator/bin/pgo-event/ '*/bin/*' 
	
RUN	curl -S https://raw.githubusercontent.com/golang/dep/master/install.sh | sh && \
	yum install -y git && \
	go get github.com/blang/expenv

# Use the default user with UID of 1010 (inherited from the Broadcom base image)
USER root

# Set working directory
WORKDIR /

# Run entrypoint
ENTRYPOINT [ "/entrypoint.sh" ]
