# containerdays-2024-dns

Resources used for the ContainerDays 2024 Talk «Building and Operating a Highly Reliable Cloud Native DNS Service With Open Source Technologies»

## Authors

Please feel free to approach us with feedback and questions!

Hoang Anh Mai <hoanganh.mai@swisscom.com>
Fabian Schulz <fabian.schulz1@swisscom.com>
Joel Studler <joel.studler@swisscom.com>

Contact us on slack:

- <https://cloud-native.slack.com>
- <https://kubernetes.slack.com>

## Getting started

For docker engine / virtualization we use [colima](https://github.com/abiosoft/colima) but any other tool for docker such as docker desktop should also work.

## Prerequisites

- colima:
  - brew install colima
  - colima start dns1 -c 4 -m 4 --network-address
  - colima ssh -p dns1 # ssh onto colima node
    - edit /etc/sysctl.conf and add: # We need to increase the file handler limit of the linux distro
      - fs.inotify.max_user_watches = 1048576
      - fs.inotify.max_user_instances = 512
  - colima restart dns1
- docker cli: brew install docker
- kind: brew install kind

## Demo Environment setup

Call the prepare-demo scripts without parameters to create your environment. The prepare-demo scripts 2 & 3 come in two flavours:

- prepare-demoX-fresh.sh which first deletes the kind clusters and sets them up from scratch
- prepare-demoX-continued.sh which keeps the setup from the previous demo

## 3 cluster local setup

Please use the create-3-cluster-setup.sh to automatically setup a 3 cluster setup locally.

## Manual Environment setup

Use the create-kind-clusters.sh and setup-kind.sh scripts to create your environment. Below are the instructions for a 2-cluster setup, the scripts also support more than two if your machine does.

To create 2 kind clusters execute:
./create-kind-clusters.sh 2

The clusters will be named dns-0, dns-1.

The setup script accepts the cluster id and an optional clusternameprefix parameter, so call it for each cluster like that:

- ./setup-kind.sh 0
- ./setup-kind.sh 1

## Environment teardown

To teardown the kind clusters simply execute:
./destroy-kind.sh 2
