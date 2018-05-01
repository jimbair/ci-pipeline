#!/usr/bin/sh

set -xeuo pipefail

# A shell script that pulls the latest Fedora cloud build
# and uses virt-customize to inject rpms into it. It 
# outputs a new qcow2 image for you to use.

CURRENTDIR=$(pwd)

if [ ${CURRENTDIR} == "/" ] ; then
    cd /home
    CURRENTDIR=/home
fi
mkdir -p ${CURRENTDIR}/logs

# Start libvirtd
mkdir -p /var/run/libvirt
libvirtd &
sleep 5
virtlogd &

chmod 666 /dev/kvm

if [ $branch != "rawhide" ]; then
    branch=${branch:1}
fi

# Define proper install url
if [[ $(curl -q https://dl.fedoraproject.org/pub/fedora/linux/development/ | grep "${branch}/") != "" ]]; then
    INSTALL_URL="https://dl.fedoraproject.org/pub/fedora/linux/development/${branch}/Cloud/x86_64/images/"
elif [[ $(curl -q https://dl.fedoraproject.org/pub/fedora/linux/releases/ | grep "${branch}/") != "" ]]; then
    INSTALL_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/${branch}/CloudImages/x86_64/images/"
else
    echo "Could not find installation source! Exiting..."
    exit 1
fi

wget --quiet -r --no-parent -A 'Fedora-Cloud-Base*.qcow2' ${INSTALL_URL}
DOWNLOADED_IMAGE_LOCATION=$(pwd)/$(find dl.fedoraproject.org -name "*.qcow2")

function clean_up {
  set +e
  pushd ${CURRENTDIR}/images
  cp ${DOWNLOADED_IMAGE_LOCATION} .
  ln -sf $(find . -name "*.qcow2") test_subject.qcow2
  popd
  kill $(jobs -p)
}
trap clean_up EXIT SIGHUP SIGINT SIGTERM

{ #group for tee

mkdir -p ${CURRENTDIR}/images

RPM_LIST=""
REPO_LIST="--repofrompath=${package},file:///etc/yum.repos.d"
# Add custom rpms to image
virt-copy-in -a ${DOWNLOADED_IMAGE_LOCATION} ${rpm_repo}/*.rpm ${rpm_repo}/repodata /etc/yum.repos.d/

for pkg in $(repoquery --disablerepo=\* --enablerepo=${package} --repofrompath=${package},${rpm_repo} --all | egrep -v '\-debug\|\-devel|.src' | rev | cut -d '-' -f 3- | rev ) ; do
    RPM_LIST="${RPM_LIST} ${pkg}"
done
if ! virt-customize -a ${DOWNLOADED_IMAGE_LOCATION} --run-command "yum install -y --nogpgcheck ${REPO_LIST} ${RPM_LIST}" ; then
    echo "failure installing rpms"
    exit 1
fi

} 2>&1 | tee ${CURRENTDIR}/logs/console.log #group for tee
