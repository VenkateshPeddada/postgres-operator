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
setup(){

	echo "Ensuring project dependencies..."
	EVTDIR="/home/default/operator/bin/pgo-event"

	mkdir $GOPATH
	chmod 775 $GOPATH
	
	mkdir $GOBIN
	chmod 775 $GOBIN
	
	# Precondition checks
	if [ "$GOPATH" = "" ]; then
		# Alternatively, take dep approach of go env GOPATH later in the process
		echo "GOPATH not defined, exiting..." >&2
		exit 1
	fi
	if ! (echo $PATH | egrep -q "$GOPATH/bin") ; then
		echo '$GOPATH/bin not part of $PATH, exiting...' >&2
		exit 2
	fi


	# Idempotent installations
#	if (yum repolist | egrep -q '^epel/') ; then
#		echo "Confirmed EPEL repo exists..."
#	else
#		echo "=== Installing EPEL ==="
		# Prefer distro-managed epel-release if it exists (e.g. CentOS)
#		if (yum -q list epel-release 2>/dev/null); then
#			sudo yum -y install epel-release
#		else
#			sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
#		fi
#	fi

	if which go; then
		echo -n "  Found: " && go version
	else
		echo "=== Installing golang ==="
		 yum -y install golang
	fi

	if ! [ -f $EVTDIR/nsqd -a -f $EVTDIR/nsqadmin ]; then
		echo "=== Installing NSQ binaries ==="
		NSQ=nsq-1.1.0.linux-amd64.go1.10.3
		curl -o $NSQ.tar.gz https://s3.amazonaws.com/bitly-downloads/nsq/$NSQ.tar.gz
		tar xz -f nsq-1.1.0.linux-amd64.go1.10.3.tar.gz -C $EVTDIR
		rm -rf nsq-1.1.0.linux-amd64.go1.10.3.tar.gz
		cd $EVTDIR
		mv $NSQ/bin/* .
		rm -rf $NSQ
		
	fi

#	if which docker; then
		# Suppress errors for this call, as docker returns non-zero when it can't talk to the daemon
#		set +e
#		echo -n "  Found: " && docker version --format '{{.Client.Version}}' 2>/dev/null
#		set -e
#	else
#		echo "=== Installing docker ==="
#		if [ -f /etc/centos-release ]; then
#			sudo yum -y install docker
#		else
#			sudo yum -y install docker --enablerepo=rhel-7-server-extras-rpms
#		fi
#	fi

#	if which buildah; then
#		echo -n "  Found: " && buildah --version
#	else
#		echo "=== Installing buildah ==="
#		if [ -f /etc/centos-release ]; then
#			sudo yum -y install buildah
#		else
#			sudo yum -y install buildah --enablerepo=rhel-7-server-extras-rpms
#		fi
#	fi

	if which dep; then
		echo -n "  Found: " && (dep version | egrep '^ version')
	else
		echo "=== Installing dep ==="
		curl -S https://raw.githubusercontent.com/golang/dep/master/install.sh | sh
	fi

	if which expenv; then
		echo "  Found expenv"
	else
		echo "=== Installing expenv ==="
		yum install -y git
		# TODO: expenv uses Go modules, could retrieve specific version
		go get github.com/blang/expenv
	fi

}

installrbac(){

	DIR="/home/default/operator/deploy"
	
	#$DIR/cleanup-rbac.sh
	cleanup_rbac
	
	# see if CRDs need to be created
	#kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get crd pgclusters.crunchydata.com > /dev/null
	#if [ $? -eq 1 ]; then
	#	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} create -f $DIR/crd.yaml
	#fi

	# create the initial pgo admin credential
	#$DIR/install-bootstrap-creds.sh
	install_bootstrap_creds

	# create the cluster roles one time for the entire Kube cluster
	expenv -f $DIR/configmap-yaml/cluster-roles.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} create -f -


	# create the Operator service accounts
	expenv -f $DIR/configmap-yaml/service-accounts.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create -f -

	if [ -r "$PGO_IMAGE_PULL_SECRET_MANIFEST" ]; then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE create -f "$PGO_IMAGE_PULL_SECRET_MANIFEST"
	fi

	if [ -n "$PGO_IMAGE_PULL_SECRET" ]; then
		patch='{"imagePullSecrets": [{ "name": "'"$PGO_IMAGE_PULL_SECRET"'" }]}'

		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE patch --type=strategic --patch="$patch" serviceaccount/postgres-operator
	fi

	# create the cluster role bindings to the Operator service accounts
	# postgres-operator and pgo-backrest, here we are assuming a single
	# Operator in the PGO_OPERATOR_NAMESPACE env variable
	expenv -f $DIR/configmap-yaml/cluster-role-bindings.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create -f -

	expenv -f $DIR/configmap-yaml/roles.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE create -f -
	expenv -f $DIR/configmap-yaml/role-bindings.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE create -f -

	# create the keys used for pgo API
	source $DIR/gen-api-keys.sh

	# create the sshd keys for pgbackrest repo functionality
	source $DIR/gen-sshd-keys.sh

}

cleanup_rbac(){
	
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE get serviceaccount postgres-operator  > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE delete serviceaccount postgres-operator
	fi

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get clusterrole pgo-cluster-role   > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} delete clusterrole pgo-cluster-role 
	fi

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get clusterrolebinding pgo-cluster-role   > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} delete clusterrolebinding pgo-cluster-role  > /dev/null 2> /dev/null
	fi

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE get role pgo-role   > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE delete role pgo-role 
	fi

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE get rolebinding pgo-role   > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} -n $PGO_OPERATOR_NAMESPACE delete rolebinding pgo-role  > /dev/null
	fi

	sleep 5
}

install_bootstrap_creds(){
	DIR="/home/default/operator/deploy"
	# fill out these variables if you want to change the
	# default pgo bootstrap user and role
	export PGOADMIN_USERNAME=pgoadmin
	export PGOADMIN_PASSWORD=pgoadmin
	export PGOADMIN_ROLENAME=pgoadmin
	export PGOADMIN_PERMS="*"

	# see if the bootstrap pgorole Secret exists or not, deleting it if found
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get secret pgorole-$PGOADMIN_ROLENAME -n $PGO_OPERATOR_NAMESPACE 2> /dev/null > /dev/null
	if [ $? -eq 0 ]; then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} delete secret pgorole-$PGOADMIN_ROLENAME -n $PGO_OPERATOR_NAMESPACE
	fi

	expenv -f $DIR/configmap-yaml/pgorole-pgoadmin.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} create -f -

	# see if the bootstrap pgouser Secret exists or not, deleting it if found
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get secret pgouser-$PGOADMIN_USERNAME -n $PGO_OPERATOR_NAMESPACE  2> /dev/null > /dev/null
	if [ $? -eq 0 ]; then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} delete secret pgouser-$PGOADMIN_USERNAME -n $PGO_OPERATOR_NAMESPACE
	fi
	expenv -f $DIR/configmap-yaml/pgouser-admin.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} create -f -
}


setupnamespaces(){

	if [ -z $PGO_OPERATOR_NAMESPACE ];
	then
		echo "error: \$PGO_OPERATOR_NAME must be set"
		exit 1
	fi

	if [ -z $PGO_INSTALLATION_NAME ];
	then
		echo "error: \$PGO_INSTALLATION_NAME must be set"
		exit 1
	fi

	echo "creating "$PGO_OPERATOR_NAMESPACE" namespace to deploy the Operator into..."
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get namespace $PGO_OPERATOR_NAMESPACE > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		echo namespace $PGO_OPERATOR_NAMESPACE is already created
	else
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} create namespace $PGO_OPERATOR_NAMESPACE > /dev/null
		echo namespace $PGO_OPERATOR_NAMESPACE created
	fi

	IFS=', ' read -r -a array <<< "$NAMESPACE"

	echo ""
	echo "creating namespaces for the Operator to watch and create PG clusters into..."
	for ns in "${array[@]}"
	do
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get namespace $ns > /dev/null 2> /dev/null

		if [ $? -eq 0 ]
		then
			echo namespace $ns already exists, updating...
			$PGOROOT/deploy/add-targeted-namespace.sh $ns > /dev/null
		else
			echo namespace $ns creating...
			$PGOROOT/deploy/add-targeted-namespace.sh $ns > /dev/null
		fi
	done

}

deployoperator(){

	DIR="/home/default/operator/deploy"
	

	$DIR/cleanup.sh

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get clusterrole pgo-cluster-role 2> /dev/null > /dev/null
	if [ $? -ne 0 ]
	then
		echo ERROR: pgo-cluster-role was not found 
		echo Verify you ran install-rbac.sh
		exit
	fi

	#
	# credentials for pgbackrest sshd 
	#
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create secret generic pgo-backrest-repo-config \
		--from-file=config=$PGOROOT/conf/pgo-backrest-repo/config \
		--from-file=sshd_config=$PGOROOT/conf/pgo-backrest-repo/sshd_config \
		--from-file=aws-s3-credentials.yaml=$PGOROOT/conf/pgo-backrest-repo/aws-s3-credentials.yaml \
		--from-file=aws-s3-ca.crt=$PGOROOT/conf/pgo-backrest-repo/aws-s3-ca.crt

	#
	# credentials for pgo-apiserver TLS REST API
	#
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE get secret pgo.tls > /dev/null 2> /dev/null
	if [ $? -eq 0 ]
	then
		kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE delete secret pgo.tls
	fi

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create secret tls pgo.tls --key=$PGOROOT/conf/postgres-operator/server.key --cert=$PGOROOT/conf/postgres-operator/server.crt

	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create configmap pgo-config \
		--from-file=$PGOROOT/conf/postgres-operator \
		--from-file=pgo.yaml=$PGOROOT/conf/postgres-operator/configmap-yaml/pgo.yaml


	#
	# check if custom port value is set, otherwise set default values
	#

	if [[ -z ${PGO_APISERVER_PORT} ]]
	then
			echo "PGO_APISERVER_PORT is not set. Setting to default port value of 8443."
			export PGO_APISERVER_PORT=8443
	fi

	#
	# create the postgres-operator Deployment and Service
	#
	expenv -f $DIR/configmap-yaml/deployment.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create -f -
	expenv -f $DIR/configmap-yaml/service.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create -f -

	expenv -f $DIR/configmap-yaml/pgo-client.yaml | kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} --namespace=$PGO_OPERATOR_NAMESPACE create -f -
}

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
export PGO_CMD=kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN}
export PGOROOT=/home/default/operator
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
	#setup;
	#/home/default/operator/bin/get-deps.sh
	#echo setup is called
	cd /
	#cd /home/default/operator/deploy && ./setupnamespaces.sh
	setupnamespaces;
	echo setupnamespaces is called
	cd /
	#cd /home/default/operator/deploy && ./install-rbac.sh
	installrbac;
	echo installrbac is called
	cd /
	#cd /home/default/operator/deploy && ./deploy.sh
	deployoperator;
	echo deployoperator is called
	cd /

    # Ensure operator pod is running before proceeding
    if ! operator_pod_running;
    then
	exit 1
    fi
	
	sleep 20
    
	# Apply Cluster
    echo RUN PGO command in ${KUBERNETES_NAMESPACE} namespace
    #kubectl_token apply -f /home/default/operator/cr.yaml
	pod_name=`kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} get pod -l name=pgo-client -o jsonpath="{.items[0].metadata.name}" -n ${KUBERNETES_NAMESPACE}`
	kubectl --token=${BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN} exec  ${pod_name} -n ${KUBERNETES_NAMESPACE} -- pgo create cluster ${CLUSTER_NAME}
	
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
    kubectl_token apply -f /home/default/operator/backup.yaml
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
    kubectl_token apply -f /home/default/operator/restore.yaml
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
    kubectl_token delete -f /home/default/operator/cr.yaml
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

