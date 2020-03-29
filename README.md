# mysql-operator (Percona XtraDB MySQL Helm chart)

## Demo

Please view the below recording for a demonstration of the steps documented in this README.

[Watch the QuickTime (.mov) recording (31 mins)](https://drive.google.com/a/broadcom.com/file/d/1QIPyGbRGvXc23c9e4LrvQ3bEyD6xm67x/view?usp=sharing)

## Overview

This README provides instructions to deploy and maintain a MySQL cluster to a GKE Kubernetes namespace using the [Percona](https://github.com/percona/percona-xtradb-cluster-operator) MySQL (XtraDB) Cluster Operator.
 
A prerequesite before using this is that a Kubernetes Cluster Administrator have previously pushed the Percona XtraDB MySQL images to Artifactory, added the Percona XtraDB MySQL Custom Resource Definitions (CRDs) and run the `push` SaaS CD Pipeline to create the `mysql-operator` namespace to facilitate using the Percona operator (see the [master branch](https://github.gwd.broadcom.net/dockcpdev/mysql-operator/blob/master/README.md) for details).

Please read the [Percona documentation](https://www.percona.com/doc/kubernetes-operator-for-pxc/index.html) to gain an understanding of the features of the Operator.

## Prerequsites

In the [deploy-info.yml](./deploy-info.yml), the following base project, operator and team needs to be defined:

```
base_project_name: "mysql-operator"
base_image_pull_service_account: "all"
operator: "true"
operator_service_account: "mysql-operator"
team:
  name: "mysql-operator"
  token: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
```

The token value for the environmentis created and managed by the Saas Ops team. Raise a SaaS ticket if you need to get the token for a specific environment.

## Install and manage the Operator via the SaaS Ops CD pipeline

In your own gitops repo, create a new branch and copy the [/operator](./operator) folder and its yaml contents, [Jenkinsfile](./Jenkinsfile), [deploy-info.yml](./deploy-info.yml), [helm-command.yml](./helm-command.yml) and [values.yaml](./values.yaml) to it from this branch. Ensure your copied `Jenksinfile` is triggering the expected SaaS Ops CD Pipeline code (dev for dockcpdev repos and master for dockcp repos) and edit your copied `deploy-info.yml` to ensure it is deploying to the expected namespace (defined by the `project_name` setting in [deploy-info.yml](./deploy-info.yml) and GKE cluster (defined by the `kubernetes.env.name` setting in [deploy-info.yml](./deploy-info.yml)).

Performing a commit to the branch deploys the `mysql-operator-1.0.0.tgz` helm chart which runs a Kubernetes Job to take the relevant Operator action. When the chart is deployed via the SaasOps CD pipeline, the operator yaml contained in the [operator](./operator) folder is added to a [ConfigMap](./chart/mysql-operator/templates/mysql-operator-configmap.yaml) .The ConfigMap gets mounted to an `/operator` folder in a [Job](./chart/mysql-operator/templates/mysql-operator-job.yaml) and provided with the following environment variables

* **RUN_TIME**: This is auto-generated to ensure each git commit will trigger the job to run
* **KUBERNETES_NAMESPACE**: Taken from the `project_name` field in `deploy-info.yml`
* **BASE_KUBERNETES_NAMESPACE**: Taken from the `base_project_name` field in `deploy-info.yml`. This needs to be `mysql-operator`
* **BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT**: Taken from the `operator_service_account` field in `deploy-info.yml`. This needs to be `mysql-operator`
* **BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT_TOKEN**: This is retrieved and the value set automatically by the SaaS Ops CD pipeline. After each pipeline run it is revoked.
* **OPERATOR_COMMAND**: Taken from the `command` field in `values.yaml`. See below for the list of supported commands for the MySQL operator
* **OPERATOR_IMAGES**: Taken from the `image.repository` field in `values.yaml`. This needs to be `gcr.io/<gcp-project-id>/<env-name>/mysql-operator/mysql-operator
* **OPERATOR_POD**: Taken from the `podName` field in `values.yaml`. This needs to be `percona-xtradb-cluster-operator`
* **BACKUP_NAME**: If the `command` field is `delete-backup`, this needs to be set to the name of the Percona backup object to delete
* **PERCONA_OPERATOR_VERSION**: If the `command` field is `update-cluster`, the Percona version to update the cluster to. The Percona images must be available in the Google Container Registry.
* **PERCONA_API_VERSION**: If the `command` field is `update-cluster`, the Percona API version to update the cluster to. The Percona images must be available in the Google Container Registry.
* **CLUSTER_NAME**: If the `command` field is `update-cluster`, the name of the Percona cluster object to update

## Commands available for the MySQL Operator via the SaaS Ops CD Pipeline

### General Information on the running of commands
When the `mysql-operator` helm chart runs via the Saas Ops CD pipeline, the [Job](./chart/mysql-operator/templates/mysql-operator-job.yaml) with mounted [ConfigMap](./chart/mysql-operator/templates/mysql-operator-configmap.yaml) and associated environment variable values referenced above are run.

The job runs in the GKE Kubernetes cluster using the provided `BASE_KUBERNETES_NAMESPACE_SERVICE_ACCOUNT` serviceaccount token (retrieved automatically from the `mysql-operator` namespace). When the Job completes (whether successful or not), the serviceaccount token is revoked to ensure that a new token is generated; this ensures that no-one can login using that serviceaccount token after the job has run.

## Presteps before you run the Saas Ops CD Pipeline for the first time

* In [values.yaml](./values.yaml), set the `command` field to `deploy-cluster`. Edit the `image.repository` value to use your GCP project ID and env name (as defined in your [deploy-info.yml](./deploy-info.yml).
* Likewise, edit the [/operator/operator.yaml](./operator/operator.yaml) and  [/operator/cr.yaml](./operator/cr.yaml) to ensure any image references use your GCP project ID and the environment name as defined in your [deploy-info.yml](./deploy-info.yml). Essentially, ensure that aywhere you see reference to `gcr.io` that you update to have the path to the images in your projects Container regsistry - i.e. `gcr.io/<gcp-project-id>/<env-name>/mysql-operator`.
* If you want to backup and restore from a Google Storage bucket, you need to provide a HMAC key to [/operator/backup-s3.yaml](./operator/backup-s3.yaml). See [Google HMAC documentation](https://cloud.google.com/storage/docs/authentication/hmackeys) that can authenticate to the Google Storage bucket you will need to have already created.
* You need to add appropriate users and base64 encoded passwords to [/operator/secrets.yaml](./operator/secrets.yaml).
* You need to provide certificates that will be used to secure communication within the cluster. If you don't already have certificates to use, see the [Percona documentation](https://www.percona.com/doc/kubernetes-operator-for-pxc/TLS.html#generate-certificates-manually) on how to create a Certifcate Authority and generated required certificates. Add these to the [/operator/ssl-secrets.yaml](./operator/ssl-secrets.yaml) and [/operator/ssl-internal-secrets.yaml](./operator/ssl-internal-secrets.yaml) respectively.

### deploy-cluster

You need to define the relevant settings for your cluster to the [/operator/cr.yaml](./operator/cr.yaml). If you have not deployed the PMM Server, ensure that the pmm section in [/operator/cr.yaml](./operator/cr.yaml) has `enabled: false`. The example `schedule` settings in the cr.yaml file demonstrate how to backup to Google Persistent Disk storage every day and to a Google Storage Bucket every Saturday.

Trigger the SaaS Ops CD pipeline by making a commit to the github branch. This will then perform a MySQL cluster deployment to the specified namespace by running the following commands:

1. Apply the Google Storage bucket credentials<br/>
   kubetl apply -f [/operator/backup-s3.yaml](./operator/backup-s3.yaml)<br/>
2. Apply role and rolebinding to the local percona-xtradb-cluster-operator serviceaccount<br/>
   kubectl apply -f [/operator/role.yaml](./operator/rbac.yaml)<br/>
   kubectl apply -f [/operator/role-binding.yaml](./operator/role-binding.yaml)<br/>
3. Start the MySQL Operator (if already started, this will be ignored)<br/>
   kubectl apply -f [/operator/operator.yaml](./operator/operator.yaml)<br/>
4. Define users and their passwords for the MySQL cluster<br/>
   kubectl apply -f [/operator/secrets.yaml](./operator/secrets.yaml)<br/>
5. Define SSL certificates for the MySQL cluster<br/>
   kubectl apply -f [/operator/ssl-secrets.yaml](./operator/ssl-secrets.yaml)<br/>
   kubectl apply -f [/operator/ssl-internal-secrets.yaml](./operator/ssl-internal-secrets.yaml)<br/>
6. Perfom the MySQL cluster deployment<br/>
   kubectl apply -f [/operator/cr.yaml](./operator/cr.yaml)

If you have deployed without the PMM Server and with the cr.yaml file settings showing a cluster name of `cluster1`, pxc and proxysql size of `3`, you should see a deployment similar to the following after a number of minutes. Inspect the container logs to ensure you don't see errors.

If you have used the example settings in [/operator/cr.yaml](./operator/cr.yaml) you should see the following objects:

* 1 stateful set `cluster1-proxysql` running 3 pod instances
* 1 stateful set `cluster1-pxc` running 3 pod instances
* 1 cron job for the `daily-backup`
* 1 cron job for the `sat-night-backup`
* 1 completed job `mysql-operator-1-XXXXXXXXX` that performed this action. For subsequent runs, you will see a job per run
* 1 deployment for `percona-xtradb-cluster-operator` that contains the operator functionality

![screenshot1.png](./images/screenshot1.png)

Test the connection by running the percona-client and connect its console output to your terminal (running it may require some time to deploy the corresponding Pod):

```
kubectl --namespace mysql-operator-demo run -i --rm --tty percona-client --image=percona:5.7 --restart=Never -- bash -il
```

Change the namespace value to match your namespace as per the `project_name` setting in your [deploy-info.yml](./deploy-info.yml). It may take a minute or so for a command prompt in the running container to be available.

Now run the mysql tool in the percona-client command shell using the `root` password obtained from base64 decoding the value from [/operator/secrets.yaml](./operator/secrets.yaml). If you are just using the example user password values provided in the secrets.yaml for demo purposes, the example password is `root_password`:

```
mysql -h cluster1-proxysql -uroot -proot_password
```

![screenshot2.png](./images/screenshot2.png)

To scale a cluster, do not use `kubectl scale ...` from the command line or via the GKE Kubernetes Console. Instead, set the relevant `size` value in the pxc or proxysql section(s), as appropriate, and retrigger the SaaS Ops CD pipeline using the `deploy-cluster` command in the values.yaml. If there are other settings you want to update, you would edit the [/operator/cr.yaml](./operator/cr.yaml) accordingly and run a `deploy-cluster` command via the SaasOps CD pipeline. This will perform a Kubernetes rolling update of your MySQL deployment.

### backup-cluster

This performs a backup of a MySQL cluster deployment to either GCP Persistent Disk or a pre-existing Google Storage Bucket (using HMAC credentials mimicing AWS S3).

Presteps to take before you run the SaaS Ops CD Pipeline to perform a backup:

* In [values.yaml](./values.yaml), set the `command` field to `backup-cluster`.
* If backing up to a Google Storage Bucket, you must have the HMAC credentials (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) in the [/operator/backup-s3.yaml](./operator/backup-s3.yaml) and define an appropriate storages sub-section within the backup section in [/operator/cr.yaml](./operator/cr.yaml). For example:   

```
    backup:
      image: gcr.io/<gcp-projectd-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator-backup:1.3.0
      serviceAccountName: percona-xtradb-cluster-operator
      storages:
        s3-us-west:
          type: s3
          podSecurityContext:
            runAsUser: 1001
            runAsGroup: 1001
            fsGroup: 1001
          s3:
            bucket: mysql-operator-demo
            credentialsSecret: mysql-cluster-backup-s3
            region: us-west2
            endpointUrl: https://storage.googleapis.com
```

Replace gcp-project-id with the project ID of your Google Project and the name of your environment as defined in your [deploy-info.yml](./deploy-info.yml).

* If backing up to a Google Persistent disk, you must have defined an appropriate storages sub-section within the backup section in [/operator/cr.yaml](./opertor/cr.yaml). For example:

```
    backup:
      image: gcr.io/<gcp-projectd-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator-backup:1.3.0
      serviceAccountName: percona-xtradb-cluster-operator
      storages:
        fs-pvc:
          type: filesystem
          podSecurityContext:
            runAsUser: 1001
            runAsGroup: 1001
            fsGroup: 1001
          volume:
            persistentVolumeClaim:
              storageClassName: us-east4-a
              accessModes: [ "ReadWriteOnce" ]
              resources:
                requests:
                  storage: 6Gi
```

where the volume definition follows standard Kubernetes terminology.

Replace gcp-project-id with the project ID of your Google Project and the name of your environment as defined in your [deploy-info.yml](./deploy-info.yml).

Ensure the [/operator/backup.yaml](.operator/backup.yaml) refers to the cluster name you want to be backed up and the storage location to backup to.

Trigger the CD pipeline by making a commit to the github branch. This will then perform a MySQL cluster backup as per the settings defined in [/operator/backup.yaml](./operator/backup.yaml) by running the following commands:

1. Ensures the operator pod is running in the namespace (following will return 1 if true)<br/>
   kubectl get pods | grep percona-xtradb-cluster-operator- | grep Running | wc -l<br/>
2. Applies backup<br/>
   kubectl apply -f [/operator/backup.yaml](./operator/backup.yaml)

You will see a backup job (pod) be run and you can review it's logs to see what it has done.

If you want to automate your backups via a cron job, edit the `schedule` section in [/operator/cr.yaml](./operator/cr.yaml). For example, the following will automate a backup of the named cluster in cr.yaml each Saturday to the Google Storage Bucket defined by the s3-us-west settings (see above) and a daily backp to GCP Persistent Disk defined by the fs-pvc settings (see above). The `keep` value determines how many backups will be retained with the oldest being deleted on any new backup if the number of current backups equls the `keep` value:

```
      schedule:
        - name: "sat-night-backup"
          schedule: "0 0 * * 6"
          keep: 3
          storageName: s3-us-west
        - name: "daily-backup"
          schedule: "0 0 * * *"
          keep: 5
          storageName: fs-pvc
```

### restore-cluster

This performs a restore of a backup to a MySQL cluster deployment from either GCP Persistent Disk or a Google Storage Bucket (using HMAC credentials mimicing AWS S3).

Presteps before you run the SaaS Ops CD Pipeline:

* In [values.yaml](./values.yaml), set the `command` field to `restore-cluster`.
* See the presteps defined above for `backup-cluster` regarding the settings in [/operator/cr.yaml](./operator/cr.yaml).

Ensure the [/operator/restore.yaml](.operator/restore.yaml) refers to the cluster name you want to restore to and the backup name to restore.

Trigger the SaaS Ops CD pipeline by making a commit to the github branch. This will then perform a MySQL cluster restore as per the settings defined in [/operator/restore.yaml](./operator/restore.yaml) by running the following commands:

1. Ensures the operator pod is running in the namespace (following will return 1 if true)<br/>
   kubectl get pods | grep percona-xtradb-cluster-operator- | grep Running | wc -l<br/>
2. Apply restore<br/>
   kubectl apply -f [/operator/restore.yaml](./operator/restore.yaml)

You will see a restore job be run and you can review it's logs to see what it has done.

### delete-cluster

This performs a delete of a MySQL cluster deployment. You can decide to delete the data as well as the deployment or just the deployment.

Presteps before you run the CD Pipeline:

* In [values.yaml](./values.yaml), set the `command` field to `delete-cluster`<br/>
* Define the name of the cluster to be deleted in the [/operator/cr.yaml](./operator/cr.yaml). If you want to keep the data and only delete the deployment, remove or comment out the `delete-proxysql-pvc` and `delete-pxc-pvc` finalizer lines:

```
  metadata:
    name: cluster1
    finalizers:
      - delete-pxc-pods-in-order
      - delete-proxysql-pvc
      - delete-pxc-pvc
```

Trigger the SaaS Ops CD pipeline by making a commit to the github branch. This will then perform a MySQL cluster delete as per the settings defined in [/operator/restore.yaml](./operator/restore.yaml) by running the following commands:

1. Ensures the operator pod is running in the namespace (following will return 1 if true)<br/>
kubectl get pods | grep percona-xtradb-cluster-operator- | grep Running | wc -l<br/>
2. Apply delete<br/>
kubectl delete -f [/operator/cr.yaml](./operator/cr.yaml)

If you run `kubetl get pxc` you should not see the cluster name listed.

### list-backups

This returns a list (viewable in the Jenkins SaaS Ops CD Pipeline log) of the previously performed backups.

Presteps before you run the SaaS Ops CD Pipeline:

* In [values.yaml](./values.yaml), set the `command` field to `list-backups`.

Trigger the SaaS Ops CD pipeline by making a commit to the github branch. This will run the following commands:

1. Ensures the operator pod is running in the namespace (following will return 1 if true)<br/>
   kubectl get pods | grep percona-xtradb-cluster-operator- | grep Running | wc -l<br/>
2. Gets available clusters<br/>
   kubectl get pxc<br/>
3. Gets available cluster backups<br/>
   kubectl get pxc-backup

### delete-backup

This deletes the named backup

Presteps before you run the SaaS Ops CD Pipeline:

* In [values.yaml](./values.yaml), set the `command` field to `delete-backup` and the `backupName` field to the name of the backup to delete.

Trigger the SaaS Ops CD pipeline by making a commit to the github branch. This will run the following commands:

1. Ensures the operator pod is running in the namespace (following will return 1 if true)<br/>
   kubectl get pods | grep percona-xtradb-cluster-operator- | grep Running | wc -l<br/>
2. Delete backup<br/>
   kubectl delete pxc-backup <backupName>

### update-cluster

This updates an already deployed cluster to a later Percona release

Presteps before you run the SaaS Ops CD Pipeline:

* In [values.yaml](./values.yaml), set the `command` field to `update-cluster`, `perconaOperatorVersion`to the new Percona version (e.g. 1.3.0), `perconaOperatorApiVersion` to the new Percona API version (e.g. v1-3-0) and the `clusterName` field to the name of the cluster to update.
* The images used by the new Percona version must have previously been downloaded from the [Percona Operator location on Docker Hub](https://hub.docker.com/r/percona/percona-xtradb-cluster-operator) by a cluster admin, retagged and pushed to Artifactory. Then the cluster admin must have pushed those images to the local Google Container Registry in the mysql-operator namespace.

Trigger the SaaS Ops CD pipeline by making a commit to the github branch. This will run the following commands:

1. Ensures the operator pod is running in the namespace (following will return 1 if true)<br/>
   kubectl get pods | grep percona-xtradb-cluster-operator- | grep Running | wc -l<br/>
2. Patches the operator pod with the latest Percona operator image<br/>
   kubectl patch deployment percona-xtradb-cluster-operator -p '{"spec":{"template":{"spec":{"containers":[{"name":"percona-xtradb-cluster-operator","image":"<gcp-project-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator:'<perconaOperatorVersion>'"}]}}}}<br/>
3. Patch the pxc, proxysql, backup and pmm pods with the latest Percona images<br/>
```
   kubectl patch pxc <clusterName> --type=merge -p '{
   "metadata": {"annotations":{ "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"pxc.percona.com/'<perconaApiVersion>'\"}" }},
   "spec": {"pxc":{ "image": "<gcp-project-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator-pxc:'<perconaOperatorVersion>'" },
       "proxysql": { "image": "<gcp-project-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator-proxysql:'<perconaOperatorVersion>'" },
       "backup":   { "image": "<gcp-project-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator-backup:'<perconaOperatorVersion>'" },
       "pmm":      { "image": "<gcp-project-id>/<env-name>/mysql-operator/percona-xtradb-cluster-operator-pmm:'<perconaOperatorVersion>'" }
   }}'
```

Replace gcp-project-id with the project ID of your Google Project and the name of your environment as defined in your [deploy-info.yml](./deploy-info.yml).

You should see the following:

* The operator pod is terminated and restarted, using the latest operator image
* The pxc, proxysql, backup and pmm pods are terminated and restarted using their latest images. The pxc and proxysql pods are terminated in sequence and thus there should be no loss of service as at least one pxc and proxysql pod should be running during the update.
