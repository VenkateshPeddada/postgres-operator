#!/bin/sh

#trap revoke_service_account_tokens EXIT

operator_pod_running() {
    CHECK_OPERATOR_SLEEP=10
    CHECK_OPERATOR_RUNNING=1
    while [ ${CHECK_OPERATOR_RUNNING} -lt 30 ];
    do
        OPERATOR_RUNNING=`kubectl_token --namespace ${KUBERNETES_NAMESPACE} get pods | grep ${OPERATOR_POD}- | grep Running | wc -l`
		OPERATOR_CLIENT_RUNNING=`kubectl_token --namespace ${KUBERNETES_NAMESPACE} get pods | grep ${OPERATOR_CLIENT_POD}- | grep Running | wc -l`

        if [ "${OPERATOR_RUNNING}" == "1" ] && [ "${OPERATOR_CLIENT_RUNNING}" == "1" ]
        then
            echo Found the running operator pod in ${KUBERNETES_NAMESPACE}
            return 0
        else
            echo Waiting for the running operator pod in ${KUBERNETES_NAMESPACE}
        fi

        # Wait before checking if the operator pod is running
        sleep ${CHECK_OPERATOR_SLEEP}
        ((CHECK_OPERATOR_RUNNING++))

        if [ "${CHECK_OPERATOR_RUNNING}" == "30" ]
        then
            echo Could not find the running operator pod in ${KUBERNETES_NAMESPACE}
            return 1
        fi
    done

    return 1
}

#revoke_service_account_tokens() {
#    kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get secrets --namespace ${BASE_KUBERNETES_NAMESPACE} | grep ${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT}-token | awk '{print $1}' | xargs -I {} kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} delete secret {} --namespace ${BASE_KUBERNETES_NAMESPACE}
#}

echo Processing ${OPERATOR_COMMAND} request at ${RUN_TIME}

# Authenticate to Kubernetes using provided kubeconfig and serviceaccount token
export KUBECONFIG=/kubeconfig/kubeconfig
alias kubectl_token="kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN}"

export PGOADMIN_USERNAME=pgoadmin
export PGOADMIN_PASSWORD=password
export GOPATH=/odev
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOBIN
export NAMESPACE=pgo
export PGO_INSTALLATION_NAME=dev
export PGO_OPERATOR_NAMESPACE=pgo
export PGO_CMD=kubectl_token
export PGOROOT=/operator
export PGO_IMAGE_PREFIX=crunchydata
export PGO_BASEOS=centos7
export PGO_VERSION=4.2.1
export PGO_IMAGE_TAG=$PGO_BASEOS-$PGO_VERSION
export PGO_APISERVER_PORT=8443
export DISABLE_TLS=false
export TLS_NO_VERIFY=false
export TLS_CA_TRUST=""
export ADD_OS_TRUSTSTORE=false
export NOAUTH_ROUTES=""
export EXCLUDE_OS_TRUST=false
export DISABLE_EVENTING=false
export PGO_CA_CERT=$PGOROOT/conf/postgres-operator/server.crt
export PGO_CLIENT_CERT=$PGOROOT/conf/postgres-operator/server.crt
export PGO_CLIENT_KEY=$PGOROOT/conf/postgres-operator/server.key

echo Testing connection to Kubernetes namespace
kubectl_token get namespace ${KUBERNETES_NAMESPACE}
# If kubectl test not successful, exit
if [ $? -ne 0 ];
then
    echo Could not validate that the Kubernetes namespace ${KUBERNETES_NAMESPACE} can be accessed. Exiting
    exit -1
fi

# Run the relevant Operator command
case "${OPERATOR_COMMAND}" in
'deploy-cluster')
    # Apply secrets Credentials
	cd /
	make setup;
	cd /
	make setupnamespaces;
	cd /
	make installrbac;
	cd /
	make deployoperator;
	cd /

    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply Cluster
    echo RUN PGO command in ${KUBERNETES_NAMESPACE} namespace
    #kubectl_token apply -f /operator/cr.yaml
	pod_name = kubectl get pods -n ${KUBERNETES_NAMESPACE} -o jsonpath="{.items[0].metadata.name}" | grep pgo-client	
	kubectl_token exec  ${pod_name} -n ${KUBERNETES_NAMESPACE} -- pgo create cluster ${CLUSTER_NAME}
	
    sleep 10
;;
'backup-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply backup
    echo Applying backup.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/backup.yaml
    sleep 10

;;
'restore-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply restore
    echo Applying restore.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token apply -f /operator/restore.yaml
    sleep 10
;;
'delete-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Apply delete
    echo Deleting cr.yaml in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token delete -f /operator/cr.yaml
    sleep 10
;;
'list-backups')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # List clusters
    echo Listing mysql clusters in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token get pxc --namespace ${KUBERNETES_NAMESPACE}

    # List backups
    echo Listing backups in ${KUBERETES_NAMESPACE} namespace
    kubectl_token get pxc-backup --namespace ${KUBERNETES_NAMESPACE}
;;
'delete-backup')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Delete backup
    echo Deleting backup ${BACKUP_NAME} in ${KUBERNETES_NAMESPACE} namespace
    kubectl_token delete pxc-backup ${BACKUP_NAME} --namespace ${KUBERNETES_NAMESPACE}
;;
'update-cluster')
    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi

    # Patch the operator deployment with the desired Percona version
    echo Running the following command: kubectl patch deployment percona-xtradb-cluster-operator --namespace ${KUBERNETES_NAMESPACE} \
   -p '{"spec":{"template":{"spec":{"containers":[{"name":"percona-xtradb-cluster-operator","image":"'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator:'${PERCONA_OPERATOR_VERSION}'"}]}}}}'

    kubectl_token patch deployment percona-xtradb-cluster-operator --namespace ${KUBERNETES_NAMESPACE} \
   -p '{"spec":{"template":{"spec":{"containers":[{"name":"percona-xtradb-cluster-operator","image":"'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator:'${PERCONA_OPERATOR_VERSION}'"}]}}}}'

    # Patch the cluster to the desired Percona version. The update strategy of RollingUpdate should ensure pods are restarted
    echo Running the following command: kubectl patch pxc ${CLUSTER_NAME} --type=merge --namespace ${KUBERNETES_NAMESPACE} -p '{
   "metadata": {"annotations":{ "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"pxc.percona.com/'${PERCONA_API_VERSION}'\"}" }},
   "spec": {"pxc":{ "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-pxc:'${PERCONA_OPERATOR_VERSION}'" },
       "proxysql": { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-proxysql:'${PERCONA_OPERATOR_VERSION}'" },
       "backup":   { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-backup:'${PERCONA_OPERATOR_VERSION}'" },
       "pmm":      { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-pmm:'${PERCONA_OPERATOR_VERSION}'" }
   }}'

    kubectl_token patch pxc ${CLUSTER_NAME} --type=merge --namespace ${KUBERNETES_NAMESPACE} -p '{
   "metadata": {"annotations":{ "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"pxc.percona.com/'${PERCONA_API_VERSION}'\"}" }},
   "spec": {"pxc":{ "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-pxc:'${PERCONA_OPERATOR_VERSION}'" },
       "proxysql": { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-proxysql:'${PERCONA_OPERATOR_VERSION}'" },
       "backup":   { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-backup:'${PERCONA_OPERATOR_VERSION}'" },
       "pmm":      { "image": "'${OPERATOR_IMAGES}'/percona-xtradb-cluster-operator-pmm:'${PERCONA_OPERATOR_VERSION}'" }
   }}'

;;
*)
    echo "Sorry, we can't process ${OPERATOR_COMMAND} request"
;;
esac
