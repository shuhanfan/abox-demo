# PostgreSQL Application Package

This is a [kpt](https://github.com/GoogleContainerTools/kpt) package to deploy a PostgreSQL cluster managed by [Crunchy Data Postgres Operator](https://github.com/CrunchyData/postgres-operator).

## Installation

First ensure you have an ACM git repository with `sourceFormat: unstructured`.
Assume the repository is checked out to `~/acm` on your workstation.

Get the package with `kpt`.
```shell
kpt pkg get sso://team/abox-team/abox.git/dev/demo/postgres/application ~/acm/postgres
cd ~/acm/postgres
```

### [Optional] Customize Parameters

You can set customizable parameters in the package. Firstly, display the setters
that are provided to the package.

```
$ kpt cfg list-setters .
           NAME                  VALUE         SET BY            DESCRIPTION             COUNT   REQUIRED
  backrest-storage-class   cbs                          the storage class used for       1       No
                                                        storage provisioning(e.g.
                                                        standard, gold, fast).
  name                     postgres-operator            application name                 14      No
  namespace                pgo                                                           17      No
  ...
...
```

Then, change the parameters with `kpt cfg set . <param-name> <value>`. For example
```shell
kpt cfg set . backrest-storage-class cbs
```

If you're not using GKE, you probably want to change the value of
`XXX-storage-class`.

### [Optional] Upload Images

If you're using a private docker registry, you should upload all the images to it before deploying the database.

First download all the images as tarballs with `fetch-images.sh`.

TODO(yfcheng) Make this an `anthosbox` command.

```shell
${ANTHOSBOX_SRC}/build/fetch-images.sh $(cat images.txt)
```

Then upload them to the private registry with `anthosbox upload-images`.
```shell
anthosbox upload-images --private-registry=<private registry> --images=<image directory>
```

### Configurate TLS Certificates

A TLS certificate chain is needed to encrypt the traffic of database.

#### Use self-signed certificates

There is nothing for you to do, self-signed certificates are automatically
generated in the next step when you run the kpt functions.

#### Use your own certificates

You need to prepare the following files yourself:
* `ca.crt`: A CA certificate.
* `server.crt`: A certificate used by the database server, issued by the CA.
* `server.key`: Key file of `server.crt`.
* `replication.crt`: A certificate used by replica instances to authenticate
  themselves. The `Common Name` must be `primaryuser`. It's also issued by the
  CA.
* `replication.key`: Key file of `replication.key`.

Then use the following commands to fill those files into `cluster/certificates.yaml`.
```shell
CA_CRT=$(base64 -w 0 < "path/to/ca.crt")
SERVER_CRT=$(base64 -w 0 < "path/to/server.crt")
SERVER_KEY=$(base64 -w 0 < "path/to/server.key")
REPLICATION_CRT=$(base64 -w 0 < "path/to/replication.crt")
REPLICATION_KEY=$(base64 -w 0 < "path/to/replication.key")
export CA_CRT
export SERVER_CRT
export SERVER_KEY
export REPLICATION_CRT
export REPLICATION_KEY
envsubst '${CA_CRT} ${SERVER_CRT} ${SERVER_KEY} ${REPLICATION_CRT} ${REPLICATION_KEY}' < cluster/certificates.yaml | sponge cluster/certificates.yaml
```

### Run kpt Functions

Run all the kpt functions inside the package.
```shell
kpt fn run --enable-exec .
```
Currently, those functions do the following things:
1. Generate a self-signed certificate to be used by the database if needed.
2. Generate random passwords for database users.


### Deploy

Commit the newly added files and push to remote.
```shell
git add .
git commit -m "Add postgres application"
git push
```

This will create the following things in your cluster:
1. The Postgre Operator.
2. A database cluster managed by that operator.

### Install the pgo Client

In another terminal tab, forward the port of the operator to localhost:8443.
```shell
kubectl -n <namespace> port-forward svc/postgres-operator 8443:8443
```

Download and run a helper script `client-setup.sh`. It helps you download the
`pgo` CLI tool into your `$HOME/.pgo`, and stores the service credential into
the same directory.
```shell
$ curl https://raw.githubusercontent.com/CrunchyData/postgres-operator/v4.4.1/installers/kubectl/client-setup.sh > client-setup.sh
$ chmod +x client-setup.sh
$ ./client-setup.sh
```

Set the environment variables used by `pgo`.
```shell
export PATH=$HOME/.pgo/pgo:$PATH
export PGOUSER=$HOME/.pgo/pgo/pgouser
export PGO_CA_CERT=$HOME/.pgo/pgo/client.crt
export PGO_CLIENT_CERT=$HOME/.pgo/pgo/client.crt
export PGO_CLIENT_KEY=$HOME/.pgo/pgo/client.key
export PGO_APISERVER_URL=https://localhost:8443
export PGO_NAMESPACE=<namespace>
```

Use `pgo version` to verify the connection to the operator.
```shell
$ pgo version
pgo client version 4.4.1
pgo-apiserver version 4.4.1
```

### Install the pgAdmin

[pgAdmin](https://www.pgadmin.org/) can be installed with a single command.
```shell
$ pgo create pgadmin <cluster name>
<cluster name> pgAdmin addition scheduled
```

You can visit the Web UI of pgAdmin by proxying it to your workstation and
visit http://localhost:5050.
```shell
kubectl -n <namespace> port-forward svc/<cluster name>-pgadmin 5050:5050
```

### Credentials

The username/password of both pgAdmin and PostgreSQL cluster are the same. You
can get them by running the following command.
```shell
pgo show user <cluster name>
```

The password is autogenerated, if you want to use your own password, you must
first make the password of the default user not managed by ACM. See [Stop
managing a managed
object](https://cloud.google.com/anthos-config-management/docs/how-to/managing-objects#stop-managing)
for instructions.

After that, you can change it with `pgo update user`.

```shell
pgo update user <cluster name> --username=testuser --password=<new password>
```

### Connecting

The database is accessible behind 3 Kubernetes Services.

* `<cluster name>` points to the current master instance.
* `<cluster name>-replica` points to the replicas, which can only perform read
  only operations.
* `<cluster name>-pgbouncer` is the load balancer.

To forward the port of master instance to your workstation, use `kubectl
port-forward` like this.

```shell
kubectl -n <namespace> port-forward svc/<cluster name> 5432:5432
```

## Scaling

### Scaling Up

To scale up the cluster by adding more replicas, use `pgo scale`. Note that the
flag `--replica-count` accepts the number of **new** replicas, not **total**
replicas.

```shell
$ pgo scale <cluster name> --replica-count=1
WARNING: Are you sure? (yes/no): yes
created Pgreplica <cluster name>-gbhr
```

### Scaling Down

To scale down the cluster by removing some replicas, use `pgo scaledown`.

First use `--query` to query the list of existing replicas.
```shell
$ pgo scaledown <cluster name> --query
Cluster: <cluster name>
REPLICA                 STATUS          NODE            REPLICATION LAG         PENDING RESTART
<cluster name>-nzpz           running         node                0 MB                   false
<cluster name>-gbhr           running         node                0 MB                   false
```

Then pick a replica name, and delete it.
```shell
$ pgo scaledown <cluster name> --target=<replica name>
WARNING: Are you sure? (yes/no): yes
deleted replica <replica name>
```

## Backup and Restore

Backup and restore can be used to recover your database to a previous state
after disaster.

See also [the offical guide][1].

### List Backups

You can see the recent backups with `pgo show backup <cluster name>`.
```shell
$ pgo show backup <cluster name>
...
        full backup: 20200615-050254F
            timestamp start/stop: 2020-06-15 13:02:54 +0800 HKT / 2020-06-15 13:03:16 +0800 HKT
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 31.3MiB, backup size: 31.3MiB
            repository size: 3.7MiB, repository backup size: 3.7MiB
            backup reference list:
```

### Create a New Backup

To create a new backup, use `pgo backup <cluster name>`.
* To create a full backup, add the flag `--backup-opts="--type=full"`.
* To create a differential backup, add the flag `--backup-opts="--type=diff"`.
* To create an incremental backup, add the flag `--backup-opts="--type=incr"`. This is the default option.

```shell
$ pgo backup <cluster name>
created Pgtask backrest-backup-<cluster name>

$ pgo show backup <cluster name>
...
        full backup: 20200615-050254F
            timestamp start/stop: 2020-06-15 13:02:54 +0800 HKT / 2020-06-15 13:03:16 +0800 HKT
            wal start/stop: 000000010000000000000004 / 000000010000000000000004
            database size: 31.3MiB, backup size: 31.3MiB
            repository size: 3.7MiB, repository backup size: 3.7MiB
            backup reference list:

        incr backup: 20200615-050254F_20200615-063322I
            timestamp start/stop: 2020-06-15 14:33:22 +0800 HKT / 2020-06-15 14:33:24 +0800 HKT
            wal start/stop: 00000001000000000000000B / 00000001000000000000000B
            database size: 31.3MiB, backup size: 3.4MiB
            repository size: 3.7MiB, repository backup size: 409.7KiB
            backup reference list: 20200615-050254F
```

### Restore the Cluster

You can restore the cluster to a specific time in the past with `pgo restore <cluster name> --pitr-target=<time> --backup-opts="--type=time"`.

During restoring, the existing cluster will be destroyed and a new one will be spinned up. So a downtime of several minutes is expected.
```shell
$ pgo restore <cluster name> --pitr-target="2020-06-15 14:33:30.000000+08" --backup-opts="--type=time"
If currently running, the primary database in this cluster will be stopped and recreated as part of this workflow!
WARNING: Are you sure? (yes/no): yes
restore performed on <cluster name> to ... opts=--type=time pitr-target=2020-06-15 14:33:30.000000+08
workflow id 847792b1-a9d6-4f86-afa7-be0eb3e66815
```
## Performance and Monitoring

The following components can be used to understand how PostgreSQL containers are performing over time using tools such as pgBadger, Grafana and Prometheus.

### Crunchy pgBadger
The Crunchy pgBadger provides a tool that parses PostgreSQL logs and generate an in-depth statistical report. Crunchy pgBadger reports includes:
* Connections
* Sessions
* Checkpoints
* Vacuum
* Locks
* Queries

#### Setup
Enable pgbadger after getting the PostgreSQL kpt package:
```shell
$ kpt cfg set <postgres-dir> enable-pgbadger true
set 2 fields
```
Forward the port of service postgres to localhost:10000 when the PostgreSQL is deployed successfully.
```shell
$ kubectl -n <namespace> port-forward svc/postgres 10000:10000
Forwarding from 127.0.0.1:10000 -> 10000
Forwarding from [::1]:10000 -> 10000
```
Access pgBadger UI by http://localhost:10000.

### Monitoring
Monitoring helps you anticipate problems before they hanppend, and helps you diagnose and resolve additional issues that may not result in downtime ,but cause degraded performance.

Monitoring infrastructure is made up of the following components:

* crunchy-postgres-exporter: provides real time metrics about the PostgreSQL database via an API.
* Prometheus: a time-series database that scrapes and stores the collected metrics so they can be consumed by other services.
* Grafana: a visulization tool that provides charting and other capabilities for viewing the collected monitoring data.

#### Setup
Enable metric exporters after getting the PostgreSQL kpt package:
```shell
$ kpt cfg set <postgres-dir> enable-metrics true
set 4 fields
```

Prometheus and Grafana are installed automatically, which can not be reconfigured.

The ports exposed for metric exporters, Prometheus, and Grafana are 9187, 9090 and 3000 respectively. Forward those ports to localhost and access UIs by `http://localhost:<port>`.

```
$ kubectl -n <namespace> port-forward svc/postgres 9187:9187
$ kubectl -n <namespace> port-forward svc/crunchy-prometheus 9090:9090
$ kubectl -n <namespace> port-forward svc/crunchy-grafana 3000:3000
```


[TODO](jesseiefan@)
As the monitoring doesn't support SSL connection, it can not work when `tlsOnly=true`. Configure the Monitoring to work over an SSL connection.

## Data Migration

To migrate your data from or to another PostgreSQL cluster, e.g. Cloud SQL, you
dump the database, move the dumped file, and restore the dump into a new empty
database.

There are `pg_dump` and `psql` commands to do it. See the [official
documentation](https://www.postgresql.org/docs/current/backup-dump.html) for
details.

### Dumping

Generally, you use `pg_dump dbname > dumpfile` to dump the database into SQL
file. You can add `-n <schema>` and/or `-t <table>` to further restrict the
scope.

If you're using Cloud SQL, you can click the **EXPORT** button in its Web
console to export the database into a SQL file in GCS. Then use `gsutil` to
download the exported SQL file.

### Restoring

You use `psql --set ON_ERROR_STOP=on dbname < dumpfile` to restore the data to
your new database.

## Uninstallation

PostgreSQL uninstallation removes the PostgreSQL clusters, the Postgres Operator, the namespace and all the other related namespace-scoped or cluster-scoped resources.

To uninstall PostgreSQL application, follow these two steps:

1. Remove the application directory in ACM git repository. There are two situations:

If the PostgreSQL application is the last project in your ACM git repository, you should NOT remove it directly. Removing all namespaces or cluster-scoped resources in a single commit leads to [Config Manangement Errors](https://cloud.google.com/anthos-config-management/docs/reference/errors#knv2006).Instead, it requires the following steps:
* Remove all but `cluster-roles.yaml` in a first commit and allow Anthos Config Management to sync those changes.
* Remove `cluster-roles.yaml` in a second commit.

If not, you can remvove the PostgreSQL application directory in a single commit.

The step above deletes the PostgreSQL cluster, the namespace, namespace-scoped resources and cluster-scoped resources managed by ACM.

2. Delete cluster-scoped resources which is not managed by ACM.
```
$ kubectl delete clusterrole pgo-cluster-role
clusterrole.rbac.authorization.k8s.io "pgo-cluster-role" deleted
$ kubectl delete clusterrole pgo-prometheus-sa
clusterrole.rbac.authorization.k8s.io "pgo-prometheus-sa" deleted
$ kubectl delete clusterrolebinding pgo-cluster-role
clusterrolebinding.rbac.authorization.k8s.io "pgo-cluster-role" deleted
$ kubectl delete clusterrolebinding pgo-prometheus-sa
clusterrolebinding.rbac.authorization.k8s.io "pgo-prometheus-sa" deleted
```
