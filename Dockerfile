## MySQL Operator CI
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
ENV PERCONA_API_VERSION=${PERCONA_API_VERSION}
ENV PERCONA_OPERATOR_VERSION=${PERCONA_OPERATOR_VERSION}
ENV OPERATOR_IMAGES=${OPERATOR_IMAGES}
ENV RUN_TIME=${RUN_TIME}
ENV KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE}
ENV BASE_KUBERNETES_NAMESPACE=${BASE_KUBERNETES_NAMESPACE}
ENV BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT}
ENV BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN}

# Install kubectl
RUN microdnf update -y && rm -rf /var/cache/yum && \
    microdnf install -y wget tar gzip findutils && \
    microdnf clean all && rm -rf /var/cache/yum && \
    curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && mv ./kubectl ${KUBECTL_BINARY}

# Add necessary files
ADD entrypoint.sh /entrypoint.sh
RUN mkdir -p /operator && chown -R 1010:0 /operator && \
    touch /operator/rbac.yml && touch /operator/secret-backrest.yaml && touch /operator/secret-pgo-user.yaml && touch /operator/deployment.yaml && touch /operator/service.yaml && touch /operator/pgo.yaml && touch /operator/pgo-client.yaml 
	
# Copy other dependency files
WORKDIR /operator
RUN mkdir -p conf && chown -R 1010:0 conf
ADD conf /operator/conf

WORKDIR /
# Define appropriate file ownership and permissions
RUN chmod +x /entrypoint.sh && chmod ugo+rwx /operator/rbac.yml && chmod ugo+rwx /operator/secret-backrest.yaml && \
    chmod ugo+rwx /operator/secret-pgo-user.yaml && chmod ugo+rwx /operator/deployment.yaml && chmod ugo+rwx /operator/service.yaml && \
    chmod ugo+rwx /operator/pgo.yaml && chmod ugo+rwx /operator/pgo-client.yaml 

# Use the default user with UID of 1010 (inherited from the Broadcom base image)
USER 1010

# Set working directory
WORKDIR /

# Run entrypoint
ENTRYPOINT [ "/entrypoint.sh" ]
