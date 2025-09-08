# containerdays-2024-dns

Resources used for the ContainerDays 2024 Talk «Building and Operating a Highly Reliable Cloud Native DNS Service With Open Source Technologies»

## Authors

Please feel free to approach us with feedback and questions!

Fabian Schulz <fabian.schulz1@swisscom.com>
Joel Studler <joel.studler@swisscom.com>

Contact us on slack:

- <https://cloud-native.slack.com>
- <https://kubernetes.slack.com>

## Getting started

For docker engine / virtualization we use [colima](https://github.com/abiosoft/colima) but any other tool for docker such as docker desktop should also work.
The scripts have also been tested on linux directly.

## Prerequisites

```bash
brew install colima docker kind
colima start -c 4 -m 4 --network-address
colima ssh # ssh onto colima node
sudo -i
echo "fs.inotify.max_user_watches = 1048576" >> /etc/sysctl.conf
echo "fs.inotify.max_user_instances = 512" >> /etc/sysctl.conf
apt update && apt install -y dnsutils
colima restart
export DOCKER_HOST=unix:///Users/joel/.colima/local/docker.sock
```

## Demo Environment setup

Call make demo1 followed by make demo2 and make demo3 if you would like to setup a local dual-cluster setup step by step like in the demo.

You can also directly call the prepare-demo scripts without parameters to create your environment. The prepare-demo scripts 2 & 3 come in two flavours:

- prepare-demoX-fresh.sh which first deletes the kind clusters and sets them up from scratch
- prepare-demoX-continued.sh which keeps the setup from the previous demo

## 3 cluster local setup

Please use the create-3-cluster-setup.sh to automatically setup a 3 cluster setup locally.


## Environment teardown

To teardown the kind clusters simply execute:
make rm

### Check MariaDB Records:
- Get DB root password: `kubectl get secret --namespace dns mariadb -o jsonpath="{.data.mariadb-root-password}" | base64 -d`
- Connect to mariadb pod and execute `mariadb -uroot -p`
- `SHOW DATABASES;`
- `USE powerdns;`
- `SHOW Tables;`

