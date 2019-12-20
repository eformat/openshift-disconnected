## Diconnected OpenShift 4 Install using Quay and Libvirt

Steps

1. [Install quay on a bastion host](#quay)

   - https://access.redhat.com/documentation/en-us/red_hat_quay/3/html-single/deploy_red_hat_quay_-_basic/index#preparing_for_red_hat_quay_basic

2. [Create mirror registry and populate off line repos](#create-mirror-registry)

   - https://docs.openshift.com/container-platform/4.2/installing/installing_restricted_networks/installing-restricted-networks-preparations.html

3. [Install openshift disconnected](#openshift-install-disconnected)

   - https://docs.openshift.com/container-platform/4.2/installing/installing_restricted_networks/installing-restricted-networks-bare-metal.html#installing-restricted-networks-bare-metal

4. [Install images disconnected](#other-images) 

   - https://docs.openshift.com/container-platform/4.2/openshift_images/image-configuration.html

5. [Install olm disconnected](#olm) 

   - https://docs.openshift.com/container-platform/4.2/operators/olm-restricted-networks.html

6. [Update cluster versions disconnected](#)


### Quay

All steps done as root on bastion vm and bare metal host

Generate certificates for Quay.io (and the host name we are using)
```
cd ~/git/openshift-disconnected
wget https://gist.githubusercontent.com/sferich888/fc1a97a4652c22034cf2/raw/8b44f77ff247200124f40d4ec02c7b222938efd9/signed_test_certs.sh
```

Update your hypervisor (laptop) to talk to the registry
```
sudo cp certs/tls/certs/cacert.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

Install bastion as libvirt vm, create network
```
cat <<EOF > /etc/libvirt/qemu/networks/ocp4.xml
<network>
  <name>ocp4</name>
  <uuid>fc43091e-ce21-4af5-103b-99468b9f4d3f</uuid>
  <forward mode='nat'>  
    <nat>  
      <port start='1024' end='65535'/>  
    </nat>  
  </forward>  
  <bridge name='virbr12' stp='on' delay='0'/>  
  <mac address='52:54:00:29:7d:d7'/>  
  <domain name='hosts.eformat.me'/>  
  <dns>  
    <host ip='192.168.140.2'>  
      <hostname>bootstrap.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.3'>  
      <hostname>m1.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.4'>  
      <hostname>m2.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.5'>  
      <hostname>m3.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.6'>  
      <hostname>w1.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.7'>  
      <hostname>w2.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.8'>  
      <hostname>w3.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.200'>  
      <hostname>bastion.hosts.eformat.me</hostname>
    </host>
  </dns>  
  <ip address='192.168.140.1' netmask='255.255.255.0'>  
    <dhcp>  
      <range start='192.168.140.2' end='192.168.140.254'/>  
      <host mac='52:54:00:b3:7d:1a' name='bootstrap.hosts.eformat.me' ip='192.168.140.2'/>
      <host mac='52:54:00:b3:7d:1b' name='m1.hosts.eformat.me' ip='192.168.140.3'/>
      <host mac='52:54:00:b3:7d:1c' name='m2.hosts.eformat.me' ip='192.168.140.4'/>
      <host mac='52:54:00:b3:7d:1d' name='m3.hosts.eformat.me' ip='192.168.140.5'/>
      <host mac='52:54:00:b3:7d:1e' name='w1.hosts.eformat.me' ip='192.168.140.6'/>
      <host mac='52:54:00:b3:7d:1f' name='w2.hosts.eformat.me' ip='192.168.140.7'/>
      <host mac='52:54:00:b3:7d:2a' name='w3.hosts.eformat.me' ip='192.168.140.8'/>
      <host mac='52:54:00:29:5d:01' name='bastion.hosts.eformat.me' ip='192.168.140.200'/>
    </dhcp>
  </ip>
</network>
EOF
```

Start Network
```
virsh net-define /etc/libvirt/qemu/networks/ocp4.xml
virsh net-start ocp4
virsh net-autostart ocp4
```

DNS using named
```
# cat /etc/named.conf
zone "apps.eformat.me" IN {
        type master;
        file "dynamic/apps.eformat.me.db";
	forwarders {}; // never forward queries for this domain
};

zone "foo.eformat.me" IN {
       type master;
       file "dynamic/foo.eformat.me.db";
       forwarders {}; // never forward queries for this domain
};

# cat /var/named/dynamic/foo.eformat.me.db
$TTL    3600
@       IN      SOA     ns1 root (
	1         ; Serial
	3600         ; Refresh
	300         ; Retry
	3600         ; Expire
	300 )        ; Negative Cache TTL

        IN      NS      ns1

ns1       IN     A       192.168.140.1
api       IN     A       10.0.0.184
api-int   IN     A       10.0.0.184

_etcd-server-ssl._tcp    8640 IN	SRV 0 10 2380 etcd-0
_etcd-server-ssl._tcp    8640 IN	SRV 0 10 2380 etcd-1
_etcd-server-ssl._tcp    8640 IN	SRV 0 10 2380 etcd-2

etcd-0    IN  CNAME m1.hosts.eformat.me.
etcd-1    IN  CNAME m2.hosts.eformat.me.
etcd-2    IN  CNAME m3.hosts.eformat.me.

*.apps    IN     A      192.168.140.6
          IN     A      192.168.140.7

# cat /var/named/dynamic/hosts.eformat.me.db
$TTL    3600
@       IN      SOA     ns1 root (
	1         ; Serial
	3600         ; Refresh
	300         ; Retry
	3600         ; Expire
	300 )        ; Negative Cache TTL

        IN      NS      ns1

ns1		IN     A       192.168.140.1
bootstrap       IN     A       192.168.140.2
m1              IN     A       192.168.140.3
m2              IN     A       192.168.140.4
m3              IN     A       192.168.140.5
w1              IN     A       192.168.140.6
w2              IN     A       192.168.140.7
w3              IN     A       192.168.140.8
bastion         IN     A       192.168.140.200
```

Install VM using thin lvm snapshot based on RHEL7 (this has 
```
for vm in bastion; do lvcreate -s --name $vm fedora/base-el76; done
vgchange -ay -K fedora

guestfish --rw -a /dev/fedora/bastion -i write-append /etc/sysconfig/network-scripts/ifcfg-eth0 "HWADDR=52:54:00:29:5d:01"

virt-install -v --name bastion --ram 6000 --vcpus=2 --hvm --disk path=/dev/fedora/bastion -w network=ocp4,model=virtio,mac=52:54:00:29:5d:01 --noautoconsole --os-variant=rhel7.0 --boot hd
```

Optionally cleanup if needed
```
for vm in bastion; do virsh destroy $vm; done; for vm in bastion; do virsh undefine $vm; done; for lv in bastion; do lvremove -f fedora/$lv; done
```

Update cpu for max performance
```
virsh edit bastion
  <cpu mode='host-passthrough' check='none'/>
```

Subscribe VM
```
subscription-manager register --username=rhn-sa-mhepburn --password=<password>
subscription-manager subscribe --pool=8a85f99a6ae5e464016b251793900683
subscription-manager repos --disable="*" --enable="rhel-7-server-rpms" --enable="rhel-7-server-extras-rpms"
yum update -y
reboot
```

Add Quay.io authentication
```
yum -y install docker
systemctl enable docker
systemctl start docker
systemctl is-active docker
docker login -u="redhat+quay" -p="O81..." quay.io
```

Open ports in firewall
```
firewall-cmd --permanent --zone=public --add-port=8443/tcp
firewall-cmd --permanent --zone=public --add-port=80/tcp
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=public --add-port=3306/tcp
firewall-cmd --permanent --zone=public --add-port=6379/tcp
firewall-cmd --reload
```

Install / Deploy a Database
```
lvcreate -L10G -n mysql cinder-volumes
mkdir -p /var/lib/mysql
mke2fs -t ext4 /dev/cinder-volumes/mysql
mount /dev/cinder-volumes/mysql /var/lib/mysql
echo "/dev/cinder-volumes/mysql /var/lib/mysql  ext4     defaults,nofail        0 0" >> /etc/fstab
chmod 777 /var/lib/mysql

export MYSQL_CONTAINER_NAME=mysql
export MYSQL_DATABASE=enterpriseregistrydb
export MYSQL_PASSWORD=<password>
export MYSQL_USER=quayuser
export MYSQL_ROOT_PASSWORD=<password>

docker run \
    --detach \
    --restart=always \
    --env MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
    --env MYSQL_USER=${MYSQL_USER} \
    --env MYSQL_PASSWORD=${MYSQL_PASSWORD} \
    --env MYSQL_DATABASE=${MYSQL_DATABASE} \
    --name ${MYSQL_CONTAINER_NAME} \
    --privileged=true \
    --publish 3306:3306 \
    -v /var/lib/mysql:/var/lib/mysql/data:Z \
    registry.access.redhat.com/rhscl/mysql-57-rhel7

docker logs mysql -f
```

Check mysql connectivity
```
yum install -y mariadb
mysql -h 192.168.140.200 -u root --password=<password>
> status
```

Install / Deploy Redis
```
lvcreate -L10G -n redis cinder-volumes
mkdir -p /var/lib/redis
mke2fs -t ext4 /dev/cinder-volumes/redis
mount /dev/cinder-volumes/redis /var/lib/redis
echo "/dev/cinder-volumes/redis /var/lib/redis  ext4     defaults,nofail        0 0" >> /etc/fstab
chmod 777 /var/lib/redis

docker run -d --restart=always -p 6379:6379 \
    --name redis \
    --privileged=true \
    -v /var/lib/redis:/var/lib/redis/data:Z \
    registry.access.redhat.com/rhscl/redis-32-rhel7

docker logs redis -f
```

Check redis conenctivity
```
yum -y install telnet
telnet 192.168.140.200 6379
MONITOR
PING
QUIT
```

Configuring Quay
```
export QUAY_PASSWORD=<password>
docker run --name=quay-config --privileged=true -p 8443:8443 -d quay.io/redhat/quay:v3.2.0 config $QUAY_PASSWORD
```

Open browser and login
```
## ssh to remote host
## add to ~/.ssh/config
	LocalForward 8443 192.168.140.200:8443
	LocalForward 3306 192.168.140.200:3306
	LocalForward 6379 192.168.140.200:6379
##

https://localhost:8443
quayconfig / $QUAY_PASSWORD
```

Configure mysql db
```
SERVER=bastion.hosts.eformat.me
MYSQL_DATABASE=enterpriseregistrydb
MYSQL_PASSWORD=<password>
MYSQL_USER=quayuser
```

Configure superuser
```
Usernane: eformat
Email: eformat@gmail.com
PWD: <password>
```

Create self signed certs
```
cd ~/git/openshift-disconnected
HOSTNAME=bastion.hosts.eformat.me
./signed_test_certs.sh
```

Load ssl certs during configuration, set config
```
Upload certificates: <load cacert.crt>
ServerHostname: bastion.hosts.eformat.me:443
TLS: RedHat Quay TLS
Certificate: server.crt
Private Key: server.key
Redis Server: bastion.hosts.eformat.me
```

Validate config then Download configuration
```
Select the Download Configuration button and save the tarball (quay-config.tar.gz)
```

Stop config pod
```
docker stop quay-config
```

Deploying Quay
```
lvcreate -L150G -n quay cinder-volumes
mkdir -p /mnt/quay
mke2fs -t ext4 /dev/cinder-volumes/quay
mount /dev/cinder-volumes/quay /mnt/quay
echo "/dev/cinder-volumes/quay /mnt/quay  ext4     defaults,nofail        0 0" >> /etc/fstab
chmod 777 /mnt/quay

mkdir -p /mnt/quay/config
#optional: if you don't choose to install an Object Store
mkdir -p /mnt/quay/storage
```

Copy Config files
```
scp /tmp/quay-config.tar.gz bastion:/mnt/quay/config/
ssh bastion
cd /mnt/quay/config/
tar xvf quay-config.tar.gz
```

Run Quay
```
docker run --restart=always -p 443:8443 -p 80:8080 \
   --name quay \
   --sysctl net.core.somaxconn=4096 \
   --privileged=true \
   -v /mnt/quay/config:/conf/stack:Z \
   -v /mnt/quay/storage:/datastorage:Z \
   -d quay.io/redhat/quay:v3.2.0

docker logs quay -f
```

Browse to quay, login
```
## ssh to remote host
## add to ~/.ssh/config
	LocalForward 9443 192.168.140.200:443
#
https://localhost:9443/
eformat / <password>
```

Create an new Organization (openshift)
Create a public Repository (ocp4) 
Create a Robot Account (docker)
  - admin permissions on the ocp4 repository
  - make robot account as team member of organisation
  - can set default org permissions to admin for robot account
Get pull secret from robot account

Add ca.crt to docker host
```
scp ~/git/openshift-disconnected/certs/tls/certs/cacert.crt hades:/etc/docker/certs.d/bastion.hosts.eformat.me/ca.crt
scp ~/git/openshift-disconnected/certs/tls/certs/cacert.crt hades:/etc/docker/certs.d/bastion.hosts.eformat.me:443/ca.crt
systemctl restart docker
```

Add auth sections (bastion.hosts.eformat.me:443, bastion.hosts.eformat.me) to ~/.docker/config.json using openshift+docker robot account (get auth section from quay)
```
    "bastion.hosts.eformat.me:443": {
      "auth": "b3Blb...",
      "email": ""
    },
    "bastion.hosts.eformat.me": {
      "auth": "b3Bl...",
      "email": ""
    }
```

Login (get auth from quay)
```
docker login -u="openshift+docker" -p="F4GZ..." bastion.hosts.eformat.me:443
```

We want to configure quay to be able to mirror other repositories. Start a mirror worker
```
docker run --restart=always \
  --name mirroring-worker \
  -v /mnt/quay/config:/conf/stack:Z \
  -d quay.io/redhat/quay:v3.2.0 \
  repomirror

docker logs -f mirroring-worker
```

Login to config tool
```
https://localhost:8443
quayconfig / $QUAY_PASSWORD
```

Upload cconfiguration file generated above. Enable mirroring, download config
```
Enable repository mirroring
Select HTTPS and cert verification
Save configuration
```

Stop config, Copy Config files
```
docker stop quay-config
scp /tmp/quay-config.tar.gz bastion:/mnt/quay/config/
ssh bastion
cd /mnt/quay/config/
tar xvf quay-config.tar.gz
```

Restart quay
```
docker restart quay
```

See other sections of doc to:
- Add Clair image scanning to Red Hat Quay


### Create Mirror Registry

Create OpenShift mirror in quay

Grab latest oc client and untar on bare metal or bastion host
```
https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest
```

Ensure OpenShift pull secret is part of ~/.docker/config.json
```
https://cloud.redhat.com/openshift/install/pull-secret
```

Copy Quay openshift+docker robot credentials to ~/.docker/config.json

Mirror repository variables
```
export OCP_RELEASE=4.2.10
export LOCAL_REGISTRY='bastion.hosts.eformat.me:443'
export LOCAL_REPOSITORY='openshift/ocp4'
export PRODUCT_REPO='openshift-release-dev' 
export LOCAL_SECRET_JSON='/home/mike/.docker/config.json' 
export RELEASE_NAME="ocp-release"
```

Mirror images
```
oc adm -a ${LOCAL_SECRET_JSON} release mirror \
     --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
     --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
     --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE} \
     --insecure=true
```

Record Output when done for later
```
info: Mirroring completed in 33m19.81s (2.559MB/s)

Success
Update image:  bastion.hosts.eformat.me:443/openshift/ocp4:4.2.10
Mirror prefix: bastion.hosts.eformat.me:443/openshift/ocp4

To use the new mirrored repository to install, add the following section to the install-config.yaml:

imageContentSources:
- mirrors:
  - bastion.hosts.eformat.me:443/openshift/ocp4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - bastion.hosts.eformat.me:443/openshift/ocp4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev


To use the new mirrored repository for upgrades, use the following to create an ImageContentSourcePolicy:

apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: example
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.hosts.eformat.me:443/openshift/ocp4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - bastion.hosts.eformat.me:443/openshift/ocp4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

To create the installation program that is based on the content that you mirrored, extract it and pin it to the release (this downloads the generated openshift-install command)
```
cd ~/ocp4
oc adm -a ${LOCAL_SECRET_JSON} release extract --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}" --insecure=true
```

### OpenShift install disconnected

From the bastion host or bare metal host
```
mkdir ~/ocp4
cd ~/ocp4
```

Create ssh key
```
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_foo -q -P ""
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa_foo
```

Make folder for igntion
```
mkdir ~/ocp4/cluster-foo && cd ~/ocp4/cluster-foo
```

Create install config - be sure to add the `additionalTrustBundle` and `pullSecret` from Quay, as well as the `imageContentSources` output from the import
```
cat <<'EOF' > install-config.yaml
apiVersion: v1
baseDomain: eformat.me
compute:
- hyperthreading: Enabled   
  name: worker
  replicas: 0 
controlPlane:
  hyperthreading: Enabled   
  name: master 
  replicas: 3
imageContentSources:
- mirrors:
  - bastion.hosts.eformat.me:443/openshift/ocp4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - bastion.hosts.eformat.me:443/openshift/ocp4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIC3jCCAcagAwIBAgIBADANBgkqhkiG9w0BAQsFADAoMRQwEgYDVQQKDAtwZXJz
  b25hbF9jYTEQMA4GA1UEAwwHcm9vdF9jYTAeFw0xOTEyMTcxMDM4NTFaFw0yOTEy
  MTcxMDM4NTFaMCgxFDASBgNVBAoMC3BlcnNvbmFsX2NhMRAwDgYDVQQDDAdyb290
  X2NhMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoYBfJlhQAIObb1gA
  yKztyAoT7jgZqE80K9smdH7XtRDnyQqz2FlQ+N/SChJuU8IOc20lGdthgCoE1MZq
  cCHWduis71hEu/y9b0j9EsZ0CgGOntI2JauKbSnJBBSu6FQFKlbR9g6s7VInfwqA
  Wh6gz3sllZ2RoVODOk9/a+1zOUew7z/MW3wHkUgol16Wu5MdIhdLUjbQcViepXNH
  qmyqDDcNN8N7rxVPWEC79U7q4sllaqLAvs1T0Pi+GLGgE5youPX7p+mq/iPE/Poh
  sSzwMKlQSkxLixeW1oSWdxnWTIZKS3exazuWxC7Y1wYzXf63pVxhkeyV00H2kKw1
  R4+GBQIDAQABoxMwETAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IB
  AQCIFQRryqShRibG2NNky2CecWgYQfcKsE96S+xMhQQ+XRE40mApXycsxKYbAniu
  eg/5uxJLstQmBN2KvA/VKCH3iAejYUv/KCvzYa2vOPZwt9OXxRWO+VtSQ8DX9bPE
  qCt+QWe1t8me4DlyB1Ib6WmDpIrG/ZerHrAlKIGXcDuQezbo4VRBYWYjP00qsq3U
  lvl4HMryCHZ8G1MxSHLyiXRWGvAVRxr6gxAvzujQZSnyn8F+sSk1jKwZPpVfBG5A
  Z15xgQJRTAN04Dw8ilm6Ehmn+0ua0ibhVMvGhDFIh0LRczzJTCn+0NMTK3WmR1zW
  ujlCRxfNbnSN9ZlGg6c0YunR
  -----END CERTIFICATE-----
metadata:
  name: foo
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23 
  networkType: OpenShiftSDN
  serviceNetwork: 
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '{"auths":{"bastion.hosts.eformat.me:443":{"auth":"b3Bl...","email":""},"bastion.hosts.eformat.me":{"auth":"b3Bl...","email":""}}}'
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAA ...'
EOF
```

Keep a backup of this file
```
cd ~/ocp4
cp cluster-foo/install-config.yaml install-config.yaml.foo.orig
```

Create manifests
```
./openshift-install create manifests --dir=cluster-foo
```

!! Make any necessary customisations to manifestes !!

Locate the mastersSchedulable parameter and set its value to False.
```
vi cluster-foo/manifests/cluster-scheduler-02-config.yml

spec:
  mastersSchedulable: false
```

Create ignition configs
```
./openshift-install create ignition-configs --dir=cluster-foo
```

Install apache to host image and files
```
dnf install httpd
systemctl enable httpd
systemctl start httpd
```

Upload files to web server and check it works (get rhcos image and installer from https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/)
```
sudo cp cluster-foo/*.ign /var/www/html/
curl http://127.0.0.1:8080/bootstrap.ign
sudo mv /home/mike/ocp4/rhcos-4.2.0-x86_64-metal-bios.raw.gz /var/www/html/rhcos-4.2.0-x86_64-metal-bios.raw.gz
sudo chcon -R -t httpd_sys_content_t /var/www/html/
```

Create a virtual network for openshift

```
cat <<EOF > /etc/libvirt/qemu/networks/ocp4.xml
<network>
  <name>ocp4</name>
  <uuid>fc43091e-ce21-4af5-103b-99468b9f4d3f</uuid>
  <forward mode='nat'>  
    <nat>  
      <port start='1024' end='65535'/>  
    </nat>  
  </forward>  
  <bridge name='virbr12' stp='on' delay='0'/>  
  <mac address='52:54:00:29:7d:d7'/>  
  <domain name='hosts.eformat.me'/>  
  <dns>  
    <host ip='192.168.140.2'>  
      <hostname>bootstrap.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.3'>  
      <hostname>m1.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.4'>  
      <hostname>m2.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.5'>  
      <hostname>m3.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.6'>  
      <hostname>w1.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.7'>  
      <hostname>w2.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.8'>  
      <hostname>w3.hosts.eformat.me</hostname>
    </host>
    <host ip='192.168.140.200'>  
      <hostname>bastion.hosts.eformat.me</hostname>
    </host>
  </dns>  
  <ip address='192.168.140.1' netmask='255.255.255.0'>  
    <dhcp>  
      <range start='192.168.140.2' end='192.168.140.254'/>  
      <host mac='52:54:00:b3:7d:1a' name='bootstrap.hosts.eformat.me' ip='192.168.140.2'/>
      <host mac='52:54:00:b3:7d:1b' name='m1.hosts.eformat.me' ip='192.168.140.3'/>
      <host mac='52:54:00:b3:7d:1c' name='m2.hosts.eformat.me' ip='192.168.140.4'/>
      <host mac='52:54:00:b3:7d:1d' name='m3.hosts.eformat.me' ip='192.168.140.5'/>
      <host mac='52:54:00:b3:7d:1e' name='w1.hosts.eformat.me' ip='192.168.140.6'/>
      <host mac='52:54:00:b3:7d:1f' name='w2.hosts.eformat.me' ip='192.168.140.7'/>
      <host mac='52:54:00:b3:7d:2a' name='w3.hosts.eformat.me' ip='192.168.140.8'/>
      <host mac='52:54:00:29:5d:01' name='bastion.hosts.eformat.me' ip='192.168.140.200'/>
    </dhcp>
  </ip>
</network>
EOF
```

Create and start SDN network
```
virsh net-define /etc/libvirt/qemu/networks/ocp4.xml
virsh net-start ocp4
virsh net-autostart ocp4
```

If you need to redo, you can tidy up/delete network using
```
virsh net-destroy ocp4
virsh net-undefine ocp4
```

Add iptables rules
```
iptables -F
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp -m state --state NEW -m udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 8080 -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 6443 -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport 22623 -j ACCEPT
iptables-save > /etc/sysconfig/iptables.save
iptables-save > /etc/sysconfig/iptables
```

Install HAproxy

```
dnf install haproxy
systemctl enable haproxy
systemctl start haproxy
systemctl status haproxy
setsebool -P haproxy_connect_any=1
```

Edit config

```
vi /etc/haproxy/haproxy.cfg

defaults
	mode                	http
	log                 	global
	option              	httplog
	option              	dontlognull
	option forwardfor   	except 127.0.0.0/8
	option              	redispatch
	retries             	3
	timeout http-request	10s
	timeout queue       	1m
	timeout connect     	10s
	timeout client      	300s
	timeout server      	300s
	timeout http-keep-alive 10s
	timeout check       	10s
	maxconn             	20000

# Useful for debugging, dangerous for production
listen stats
	bind :9000
	mode http
	stats enable
	stats uri /

frontend openshift-api-server
	bind *:6443
	default_backend openshift-api-server
	mode tcp
	option tcplog

backend openshift-api-server
	balance source
	mode tcp
	server bootstrap 192.168.140.2:6443 check
	server master-0 192.168.140.3:6443 check
	server master-1 192.168.140.4:6443 check
	server master-2 192.168.140.5:6443 check
    
frontend machine-config-server
	bind *:22623
	default_backend machine-config-server
	mode tcp
	option tcplog

backend machine-config-server
	balance source
	mode tcp
	server bootstrap 192.168.140.2:22623 check
	server master-0 192.168.140.3:22623 check
	server master-1 192.168.140.4:22623 check
	server master-2 192.168.140.5:22623 check
 
frontend ingress-http
	bind *:80
	default_backend ingress-http
	mode tcp
	option tcplog

backend ingress-http
	balance source
	mode tcp
	server worker-0 192.168.140.6:80 check
	server worker-1 192.168.140.7:80 check	

frontend ingress-https
	bind *:443
	default_backend ingress-https
	mode tcp
	option tcplog

backend ingress-https
	balance source
	mode tcp
	server worker-0 192.168.140.6:443 check
	server worker-1 192.168.140.7:443 check
```

Restart HAproxy
```
systemctl restart haproxy
systemctl status haproxy
```

DNS named configuration

```
# vi /etc/named.conf

zone "foo.eformat.me" IN {
       type master;
       file "dynamic/foo.eformat.me.db";
       forwarders {}; // never forward queries for this domain
};

# cat foo.eformat.me.db
$TTL    3600
@       IN      SOA     ns1 root (
	1         ; Serial
	3600         ; Refresh
	300         ; Retry
	3600         ; Expire
	300 )        ; Negative Cache TTL

        IN      NS      ns1

ns1       IN     A       192.168.140.1
api       IN     A       10.0.0.184
api-int   IN     A       10.0.0.184

_etcd-server-ssl._tcp    8640 IN	SRV 0 10 2380 etcd-0
_etcd-server-ssl._tcp    8640 IN	SRV 0 10 2380 etcd-1
_etcd-server-ssl._tcp    8640 IN	SRV 0 10 2380 etcd-2

etcd-0    IN  CNAME m1.hosts.eformat.me.
etcd-1    IN  CNAME m2.hosts.eformat.me.
etcd-2    IN  CNAME m3.hosts.eformat.me.

*.apps    IN     A      192.168.140.6
          IN     A      192.168.140.7
```

Move the installer
```
sudo mv rhcos-4.2.0-x86_64-installer.iso /var/lib/libvirt/images
sudo chown qemu:qemu /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso
sudo restorecon -rv  /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso
```

Create an lvm thin pool (or use pre-existing)
```
lvcreate --size 500G --type thin-pool --thinpool thin_pool2
```

Create servers
```
for vm in bootstrap m1 m2 m3 w1 w2; do lvcreate --virtualsize 100G --name $vm -T fedora/thin_pool2; done
vgchange -ay -K fedora
```

Bootstrap server
```
args='nomodeset rd.neednet=1 ipv6.disable=1 '
args+='coreos.inst=yes '
args+='coreos.inst.install_dev=vda '
args+='coreos.inst.image_url=http://10.0.0.184:8080/rhcos-4.2.0-x86_64-metal-bios.raw.gz '
args+='coreos.inst.ignition_url=http://10.0.0.184:8080/bootstrap.ign '

virt-install -v --connect=qemu:///system --name bootstrap --ram 10240 --vcpus 4 --hvm --disk path=/dev/fedora/bootstrap -w network=ocp4,model=virtio,mac=52:54:00:b3:7d:1a --noautoconsole -l /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso,kernel=images/vmlinuz,initrd=images/initramfs.img --extra-args="${args}" --os-variant=rhel7.0
```

Masters
```
args='nomodeset rd.neednet=1 ipv6.disable=1 '
args+='coreos.inst=yes '
args+='coreos.inst.install_dev=vda '
args+='coreos.inst.image_url=http://10.0.0.184:8080/rhcos-4.2.0-x86_64-metal-bios.raw.gz '
args+='coreos.inst.ignition_url=http://10.0.0.184:8080/master.ign '

virt-install -v --connect=qemu:///system --name m1 --ram 10240 --vcpus 4 --hvm --disk path=/dev/fedora/m1 -w network=ocp4,model=virtio,mac=52:54:00:b3:7d:1b --noautoconsole -l /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso,kernel=images/vmlinuz,initrd=images/initramfs.img --extra-args="${args}" --os-variant=rhel7.0

virt-install -v --connect=qemu:///system --name m2 --ram 10240 --vcpus 4 --hvm --disk path=/dev/fedora/m2 -w network=ocp4,model=virtio,mac=52:54:00:b3:7d:1c --noautoconsole -l /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso,kernel=images/vmlinuz,initrd=images/initramfs.img --extra-args="${args}" --os-variant=rhel7.0

virt-install -v --connect=qemu:///system --name m3 --ram 10240 --vcpus 4 --hvm --disk path=/dev/fedora/m3 -w network=ocp4,model=virtio,mac=52:54:00:b3:7d:1d --noautoconsole -l /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso,kernel=images/vmlinuz,initrd=images/initramfs.img --extra-args="${args}" --os-variant=rhel7.0
```

Workers
```
args='nomodeset rd.neednet=1 ipv6.disable=1 '
args+='coreos.inst=yes '
args+='coreos.inst.install_dev=vda '
args+='coreos.inst.image_url=http://10.0.0.184:8080/rhcos-4.2.0-x86_64-metal-bios.raw.gz '
args+='coreos.inst.ignition_url=http://10.0.0.184:8080/worker.ign '

virt-install -v --connect=qemu:///system --name w1 --ram 10240 --vcpus 4 --hvm --disk path=/dev/fedora/w1 -w network=ocp4,model=virtio,mac=52:54:00:b3:7d:1e --noautoconsole -l /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso,kernel=images/vmlinuz,initrd=images/initramfs.img --extra-args="${args}" --os-variant=rhel7.0

virt-install -v --connect=qemu:///system --name w2 --ram 10240 --vcpus 4 --hvm --disk path=/dev/fedora/w2 -w network=ocp4,model=virtio,mac=52:54:00:b3:7d:1f --noautoconsole -l /var/lib/libvirt/images/rhcos-4.2.0-x86_64-installer.iso,kernel=images/vmlinuz,initrd=images/initramfs.img --extra-args="${args}" --os-variant=rhel7.0
```

If needed, clean up all vms
```
for vm in bootstrap m1 m2 m3 w1 w2; do virsh destroy $vm; done; for vm in bootstrap m1 m2 m3 w1 w2; do virsh undefine $vm; done; for lv in bootstrap m1 m2 m3 w1 w2; do lvremove -f fedora/$lv; done
```

If needed, cleanup bootstrap only
```
for vm in bootstrap; do virsh destroy $vm; done; for vm in bootstrap; do virsh undefine $vm; done; for lv in bootstrap; do lvremove -f fedora/$lv; done
```

Wait till all vms have installed and stopped
```
watch virsh list --all
```

Startup all hosts
```
for x in bootstrap; do
  virsh start $x
done;
sleep 10;
for x in m1 m2 m3 w1 w2; do
  virsh start $x
done;
```

Install and bootstrap cluster
```
./openshift-install --dir=cluster-foo wait-for bootstrap-complete --log-level debug
```

Debug commands: ssh bootstrap server and watch bootstrap service, check podman pull for initial cvo
```
ssh -i ~/.ssh/id_rsa_foo core@bootstrap.hosts.eformat.me
journalctl -b -f -u bootkube.service
journalctl -f | grep "Back-off pulling image"
journalctl -u release-image.service
cat /usr/local/bin/release-image-download.sh
cat /etc/containers/registries.conf
ssh -i ~/.ssh/id_rsa_foo core@m1.hosts.eformat.me
tail -f ocp4/cluster-foo/.openshift_install.log
oc get clusteroperators
oc get clusterversion
watch oc get pods --all-namespaces -o wide
oc get pods --all-namespaces | grep -v -E 'Running|Completed'
```

Install and bootstrap cluster
```
./openshift-install --dir=cluster-foo wait-for bootstrap-complete --log-level debug

...
time="2019-12-18T04:15:12+10:00" level=info msg="API v1.14.6+17b1cc6 up"
time="2019-12-18T04:15:12+10:00" level=info msg="Waiting up to 30m0s for bootstrapping to complete..."
time="2019-12-18T04:19:58+10:00" level=debug msg="Bootstrap status: complete"
time="2019-12-18T04:19:58+10:00" level=info msg="It is now safe to remove the bootstrap resources"
```

Comment out bootstrap server from haproxy
```
vi /etc/haproxy/haproxy.cfg
systemctl restart haproxy
```

Cleanup bootstrap node
```
for vm in bootstrap; do virsh destroy $vm; done; for vm in bootstrap; do virsh undefine $vm; done; for lv in bootstrap; do lvremove -f fedora/$lv; done
```

Copy kube config
```
cp ocp4/cluster-foo/auth/kubeconfig ~/.kube/config
```

Install wont finish till registry booted with disk use empty for now
```
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"emptyDir":{}}}}'
```

Get completion
```
./openshift-install --dir=cluster-foo --log-level debug wait-for install-complete

DEBUG OpenShift Installer v4.2.10                  
DEBUG Built from commit 6ed04f65b0f6a1e11f10afe658465ba8195ac459 
INFO Waiting up to 30m0s for the cluster at https://api.foo.eformat.me:6443 to initialize... 
DEBUG Cluster is initialized                       
INFO Waiting up to 10m0s for the openshift-console route to be created... 
DEBUG Route found in openshift-console namespace: console 
DEBUG Route found in openshift-console namespace: downloads 
DEBUG OpenShift console route is created           
INFO Install complete!                            
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/mike/ocp4/cluster-foo/auth/kubeconfig' 
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.foo.eformat.me 
INFO Login to the console with user: kubeadmin, password: <password>
```

Check cluster version
```
$ oc get clusterversion -o json|jq ".items[0].status.history"
[
  {
    "completionTime": "2019-12-17T21:22:57Z",
    "image": "bastion.hosts.eformat.me:443/openshift/ocp4@sha256:dc2e38fb00085d6b7f722475f8b7b758a0cb3a02ba42d9acf8a8298a6d510d9c",
    "startedTime": "2019-12-17T18:15:48Z",
    "state": "Completed",
    "verified": false,
    "version": "4.2.10"
  }
]
```

### Other Images

#### General Application Images

https://docs.openshift.com/container-platform/4.2/openshift_images/image-configuration.html

```
oc edit image.config.openshift.io/cluster

  allowedRegistriesForImport:
    - domainName: bastion.hosts.eformat.me
      insecure: false
  additionalTrustedCA:
    name: bastion-registry-ca
```

`additionalTrustedCA`: A reference to a ConfigMap containing additional CAs that should be trusted during ImageStream import, pod image pull, openshift-image-registry pullthrough, and builds. The namespace for this ConfigMap is openshift-config. The format of the ConfigMap is to use the registry hostname as the key, and the base64-encoded certificate as the value, for each additional registry CA to trust.

You need to include the port number (..:433) in the configmap key, for the build logic to use the CA otherwise it doesn't match - Note the `..` formatting here and whitespace!
```
cat <<'EOF' | oc apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: bastion-registry-ca
  namespace: openshift-config
data:
  bastion.hosts.eformat.me..443: |
    -----BEGIN CERTIFICATE-----
    MIIC3jCCAcagAwIBAgIBADANBgkqhkiG9w0BAQsFADAoMRQwEgYDVQQKDAtwZXJz
    b25hbF9jYTEQMA4GA1UEAwwHcm9vdF9jYTAeFw0xOTEyMTcxMDM4NTFaFw0yOTEy
    MTcxMDM4NTFaMCgxFDASBgNVBAoMC3BlcnNvbmFsX2NhMRAwDgYDVQQDDAdyb290
    X2NhMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoYBfJlhQAIObb1gA
    yKztyAoT7jgZqE80K9smdH7XtRDnyQqz2FlQ+N/SChJuU8IOc20lGdthgCoE1MZq
    cCHWduis71hEu/y9b0j9EsZ0CgGOntI2JauKbSnJBBSu6FQFKlbR9g6s7VInfwqA
    Wh6gz3sllZ2RoVODOk9/a+1zOUew7z/MW3wHkUgol16Wu5MdIhdLUjbQcViepXNH
    qmyqDDcNN8N7rxVPWEC79U7q4sllaqLAvs1T0Pi+GLGgE5youPX7p+mq/iPE/Poh
    sSzwMKlQSkxLixeW1oSWdxnWTIZKS3exazuWxC7Y1wYzXf63pVxhkeyV00H2kKw1
    R4+GBQIDAQABoxMwETAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IB
    AQCIFQRryqShRibG2NNky2CecWgYQfcKsE96S+xMhQQ+XRE40mApXycsxKYbAniu
    eg/5uxJLstQmBN2KvA/VKCH3iAejYUv/KCvzYa2vOPZwt9OXxRWO+VtSQ8DX9bPE
    qCt+QWe1t8me4DlyB1Ib6WmDpIrG/ZerHrAlKIGXcDuQezbo4VRBYWYjP00qsq3U
    lvl4HMryCHZ8G1MxSHLyiXRWGvAVRxr6gxAvzujQZSnyn8F+sSk1jKwZPpVfBG5A
    Z15xgQJRTAN04Dw8ilm6Ehmn+0ua0ibhVMvGhDFIh0LRczzJTCn+0NMTK3WmR1zW
    ujlCRxfNbnSN9ZlGg6c0YunR
    -----END CERTIFICATE-----
EOF
```

Import image into our quay registry
```
docker pull quay.io/eformat/welcome
docker tag quay.io/eformat/welcome:latest bastion.hosts.eformat.me:443/openshift/welcome:latest
docker push bastion.hosts.eformat.me:443/openshift/welcome:latest
```

Test out deploying an application image
```
oc new-project foo
oc import-image --all --confirm -n foo bastion.hosts.eformat.me:443/openshift/welcome
oc new-app --image-stream=welcome
oc expose svc/welcome
```

#### Debug node image

To run `oc debug node/<node name>` we need the support tools images.

Copy image
```
oc image mirror registry.redhat.io/rhel7/support-tools:latest  bastion.hosts.eformat.me:443/openshift/support-tools:latest
```

`OR` in Quay, setup an image mirror, then Select Sync now
```
Create repo: openshift/support-tools
Settings
State: Mirror

Mirroring
External Registry: registry.redhat.io/rhel7/support-tools
Sync Interval: 1 day
Robot User: openshift+docker
Credentials Remote: 7271256|eformat:<password>
Verify TLS: yes
```

Create an ImageContentSourcePolicy
```
cat <<EOF | oc apply -f -
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: support-tools
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.hosts.eformat.me:443/openshift/support-tools
    source: registry.redhat.io/rhel7/support-tools
EOF
```

Test
```
# works
oc debug node/w1 --image=bastion.hosts.eformat.me:443/openshift/support-tools

# FIXME - these still fail ?? WHY, .. should be using mirror
# BUG - https://bugzilla.redhat.com/show_bug.cgi?id=1728135
oc debug node/w1
oc debug node/w1 --image=registry.redhat.io/rhel7/support-tools@sha256:459f46f24fe92c5495f772c498d5b2c71f1d68ac23929dfb2c2869a35d0b5807
```

#### UBI minimal image

From authenticated registry

Quay, setup an image mirror, then Select Sync now
```
Create repo: openshift/ubi-minimal
Settings
State: Mirror

Mirroring
External Registry: registry.redhat.io/ubi8/ubi-minimal
Sync Interval: 1 day
Robot User: openshift+docker
Credentials Remote: 7271256|eformat:<password>
Verify TLS: yes
```

Create an ImageContentSourcePolicy
```
cat <<EOF | oc apply -f -
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ubi8-minimal
spec:
  repositoryDigestMirrors:
  - mirrors:
    - bastion.hosts.eformat.me:443/openshift/ubi-minimal
    source: registry.redhat.io/ubi8/ubi-minimal
EOF
```

Get a node debug pod
```
oc debug node/w1 --image=bastion.hosts.eformat.me:443/openshift/support-tools
chroot /host
```

Must login and pull by digest (as that is how it is mirrored)
```
podman login bastion.hosts.eformat.me:443
podman pull --log-level=debug registry.redhat.io/ubi8/ubi-minimal@sha256:a5e923d16f4e494627199ebc618fe6b2fa0cad14c5990877067e2bafa0ccb01f
```

### OLM

Disable the default OperatorSources
```
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
```

Get all manifests for all operator namespaces (redhat-operators community-operators certified-operators)
```
./get-operator-package.sh
```

These are created in a directory called `olm/manifests`. There are 2 types of bundles; single file `bundle.yaml` that need unpacking (see ocp product documentation!)
```
Manifests
└── openshifttemplateservicebroker
├── clusterserviceversion.yaml
├── customresourcedefinition.yaml
├── package.yaml
└── etcd-XXXX
  └─ <CSV’s and CRDs and a package file>
```
If you already see files like this, then you should not have to do anything

#### Example `redhat-operators/amq-streams`

amq-streams as a single example that is unbundled already (no bundle.yaml)
```
cd olm/manifests/redhat-operators/amq-streams/amq-streams-jys3kr7c
tree

├── 1.0.0
│   ├── amq-streams-kafkaconnect.crd.yaml
│   ├── amq-streams-kafkaconnects2i.crd.yaml
│   ├── amq-streams-kafka.crd.yaml
│   ├── amq-streams-kafkamirrormaker.crd.yaml
│   ├── amq-streams-kafkatopic.crd.yaml
│   ├── amq-streams-kafkauser.crd.yaml
│   └── amq-streams.v1.0.0.clusterserviceversion.yaml
├── 1.1.0
│   ├── amq-streams-kafkaconnect.crd.yaml
│   ├── amq-streams-kafkaconnects2i.crd.yaml
│   ├── amq-streams-kafka.crd.yaml
│   ├── amq-streams-kafkamirrormaker.crd.yaml
│   ├── amq-streams-kafkatopic.crd.yaml
│   ├── amq-streams-kafkauser.crd.yaml
│   └── amq-streams.v1.1.0.clusterserviceversion.yaml
├── 1.2.0
│   ├── amq-streams-kafkabridges.crd.yaml
│   ├── amq-streams-kafkaconnects2is.crd.yaml
│   ├── amq-streams-kafkaconnects.crd.yaml
│   ├── amq-streams-kafkamirrormakers.crd.yaml
│   ├── amq-streams-kafkas.crd.yaml
│   ├── amq-streams-kafkatopics.crd.yaml
│   ├── amq-streams-kafkausers.crd.yaml
│   └── amq-streams.v1.2.0.clusterserviceversion.yaml
├── 1.3.0
│   ├── amq-streams-kafkabridges.crd.yaml
│   ├── amq-streams-kafkaconnects2is.crd.yaml
│   ├── amq-streams-kafkaconnects.crd.yaml
│   ├── amq-streams-kafkamirrormakers.crd.yaml
│   ├── amq-streams-kafkas.crd.yaml
│   ├── amq-streams-kafkatopics.crd.yaml
│   ├── amq-streams-kafkausers.crd.yaml
│   └── amq-streams.v1.3.0.clusterserviceversion.yaml
└── amq-streams.package.yaml
```

Edit *clusterserviceversion.yaml and change

- OperatorImage from quay.io to your mirror image registry
- OR registry.redhat.io imagetag to an registry.redhat.io image digest

Remove unwanted versions and list images in the version we want (1.3.0 in this case)
```
rm -rf 1.0.0/ 1.1.0/ 1.2.0/
cat */amq-streams.*.clusterserviceversion.yaml | grep registry.redhat.io

    containerImage: registry.redhat.io/amq7/amq-streams-operator:1.3.0
                image: registry.redhat.io/amq7/amq-streams-operator:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                    2.2.1=registry.redhat.io/amq7/amq-streams-kafka-22:1.3.0
                    2.3.0=registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                    2.2.1=registry.redhat.io/amq7/amq-streams-kafka-22:1.3.0
                    2.3.0=registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                    2.2.1=registry.redhat.io/amq7/amq-streams-kafka-22:1.3.0
                    2.3.0=registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                    2.2.1=registry.redhat.io/amq7/amq-streams-kafka-22:1.3.0
                    2.3.0=registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-operator:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-operator:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-operator:1.3.0
                  value: registry.redhat.io/amq7/amq-streams-bridge:1.3.0
```

Replace with our quay registry
```
# replace
sed -i 's|registry.redhat.io/amq7|bastion.hosts.eformat.me:443/openshift|' */amq-streams.v1.3.0.clusterserviceversion.yaml
# remove `replaces` line as we only have one version
sed -i '/replaces/'d */amq-streams.v1.3.0.clusterserviceversion.yaml
# check
cat */amq-streams.*.clusterserviceversion.yaml | grep bastion.hosts.eformat.me:443 
```

Sync all needed images from Quay.io to your mirror registry
```
oc image mirror registry.redhat.io/amq7/amq-streams-bridge:1.3.0 bastion.hosts.eformat.me:443/openshift/amq-streams-bridge:1.3.0
oc image mirror registry.redhat.io/amq7/amq-streams-kafka-22:1.3.0 bastion.hosts.eformat.me:443/openshift/amq-streams-kafka-22:1.3.0
oc image mirror registry.redhat.io/amq7/amq-streams-kafka-23:1.3.0 bastion.hosts.eformat.me:443/openshift/amq-streams-kafka-23:1.3.0
oc image mirror registry.redhat.io/amq7/amq-streams-operator:1.3.0 bastion.hosts.eformat.me:443/openshift/amq-streams-operator:1.3.0
```

Create olm custom registry image 
```
cd ~/git/openshift-disconnected

cat <<EOF > Dockerfile.olm
FROM registry.redhat.io/openshift4/ose-operator-registry:latest AS builder
COPY olm/manifests/redhat-operators/amq-streams/amq-streams-jys3kr7c manifests
RUN /bin/initializer -o ./bundles.db
FROM registry.redhat.io/ubi8/ubi-minimal:latest
COPY --from=builder /registry/bundles.db /bundles.db
COPY --from=builder /usr/bin/registry-server /registry-server
COPY --from=builder /usr/bin/grpc_health_probe /bin/grpc_health_probe

EXPOSE 50051
ENTRYPOINT ["/registry-server"]
CMD ["--database", "bundles.db"]
EOF
```

Build and push to quay
```
docker build -f Dockerfile.olm -t bastion.hosts.eformat.me:443/openshift/custom-registry .
docker push bastion.hosts.eformat.me:443/openshift/custom-registry
```

Create a CatalogSource pointing to the new Operator catalog image
```
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: My Operator Catalog
  sourceType: grpc
  image: bastion.hosts.eformat.me:443/openshift/custom-registry:latest
EOF
```

Verify deployment
```
oc get catalogsource -n openshift-marketplace
NAME                  DISPLAY               TYPE   PUBLISHER   AGE
my-operator-catalog   My Operator Catalog   grpc               9s

oc get catalogsource -n openshift-marketplace
NAME                  DISPLAY               TYPE   PUBLISHER   AGE
my-operator-catalog   My Operator Catalog   grpc               11s

NAME                                    READY   STATUS    RESTARTS   AGE
marketplace-operator-7bfd5cf75c-bfz8s   1/1     Running   0          16h
my-operator-catalog-6tckk               1/1     Running   0          19m

oc get packagemanifest -n openshift-marketplace
NAME          CATALOG               AGE
amq-streams   My Operator Catalog   43s
```

You should also be able to view them from the OperatorHub page in the web console and install amq-streams operator

From CLI
```
oc new-project amq

cat <<EOF | oc apply -f -
apiVersion: v1
items:
- apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: amq-streams
    namespace: amq
  spec:
    channel: stable
    installPlanApproval: Automatic
    name: amq-streams
    source: my-operator-catalog
    sourceNamespace: openshift-marketplace
    startingCSV: amqstreams.v1.3.0
- apiVersion: operators.coreos.com/v1
  kind: OperatorGroup
  metadata:
    annotations:
      olm.providedAPIs: Kafka.v1beta1.kafka.strimzi.io,KafkaBridge.v1alpha1.kafka.strimzi.io,KafkaConnect.v1beta1.kafka.strimzi.io,KafkaConnectS2I.v1beta1.kafka.strimzi.io,KafkaMirrorMaker.v1beta1.kafka.strimzi.io,KafkaTopic.v1beta1.kafka.strimzi.io,KafkaUser.v1beta1.kafka.strimzi.io
    name: amq-streams
    namespace: amq
  spec:
    targetNamespaces:
    - amq
kind: List
metadata:
  resourceVersion: ""
  selfLink: ""
EOF
```
