# minimal-registry

This is a very simple, minimal, readonly registry server intended for K3s air-gapped systems.
It is for mitigating the overhead of pre-loading containerd with bootstrap images on each restart. It does **NOT** implement the registry specification, but only serves files and adds headers when required to allow it to function.

## K3s Reference material

 * [Air-Gap Install](https://docs.k3s.io/installation/airgap)
 * [Private Registry Configuration](https://docs.k3s.io/installation/private-registry#mirrors)

## Build

```
git clone https://github.com/adrianmoye/minimal-registry.git
go build -o minimal-registry main.go
```

## Setup  

The following needs to be configured:
 
 * Prepare your registry content (from a host with internet access).
 * Registries files.

### Registry Content

To prepare the registry content you need a machine with internet access. This machine requires a UNIX/Linux style environment, and the following installed:
 * curl, awk, sed, grep
 * [crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane)

Download the registry content by running the script `download-system-images.sh`.

```
./download-system-images.sh -f extra-images.txt --platform linux/arm64
<snip>
tar -zcf ./registry-content.tar.gz registry
```

Copy the content to the k8s nodes, and extract them in the required location:
```
mkdir -p /var/lib/rancher/k3s/server/
tar -zxf ./registry-content.tar.gz -C /var/lib/rancher/k3s/server/
```
This will create a registry directory in the k3s agent directory.

#### Repos

Each repo is a directory tree containing `<repo name>/manifests` and `<repo name>/blobs`.
All of the manifest files should go in the manifests directory, the registry reads these files and JSON parses them, so if they're too big it may cause problems.
The rest of the blobs go in the blob directory. You can symlink the blobs directories together to share layers.

### Install the files

On the k8s nodes copy the files, start it:
```
cp minimal-registry /usr/local/bin/
cp minimal-registry.service /etc/systemd/system/
systemctl start minimal-registry.service
```

### Registries Configuration

Make the config directory on each node, and place your registry file in there. This is an example, it also hijacks other registries, see the k3s documentation.
```
$ mkdir -p /etc/rancher/k3s/
$ cat /etc/rancher/k3s/registries.yaml
mirrors:
  bootstrap-registry.airgap:
    endpoint:
      - "http://127.0.0.1:9080"
```

## Installing k3s

Copy the k3s `install.sh` script and appropraite `k3s` binary to the destination host.

```
ip link add dummy0 type dummy
ip link set dummy0 up
ip addr add 169.254.255.254/31 dev dummy0
ip route add default via 169.254.255.255 dev dummy0 metric 1000
INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh \
  --system-default-registry bootstrap-registry.airgap
```


## Examples

```
Usage: ./download-system-images.sh --help \
          [-v <k3s version string (default=stable)>] \
          [-d <registry directory (default=./registry)>] \
          [-f <extra images list file>] \
          [-p <platform (default=linux/amd64)>] \
          [-n] \
          [-s] \
          [-h]
<snip>
```

On the node with internet access:
```
./download-system-images.sh -f extra-images.txt --platform linux/arm64
Downloading image list for v1.27.6+k3s1
pull_image docker.io/rancher/klipper-helm:v0.8.2-build20230815
<snip>
tar -zcf registry.tar.gz registry
cp install.sh k3s registry.yaml minimal-registry minimal-registry.service registry.tar.gz /mnt/sda1/
```

On the server node:
```
cd /mnt/sda1
mkdir -p /etc/rancher/k3s/
cp registry.yaml /etc/rancher/k3s/
mkdir -p /var/lib/rancher/k3s/server/
tar -zxf ./registry-content.tar.gz -C /var/lib/rancher/k3s/server/
cp minimal-registry /usr/local/bin/
cp minimal-registry.service /etc/systemd/system/
systemctl start minimal-registry.service
ip link add dummy0 type dummy
ip link set dummy0 up
ip addr add 169.254.255.254/31 dev dummy0
ip route add default via 169.254.255.255 dev dummy0 metric 1000
INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh \
  --system-default-registry bootstrap-registry.airgap
```

