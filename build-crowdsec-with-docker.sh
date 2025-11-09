#!/usr/bin/env bash
# Building CrowdSec Synology Package from WSL and Docker Synology SDK Toolchains

SHELL_OPTION=$1
USAGE_INFOS="\nUsage: $0 {prepare | build | clean}"

set -euo pipefail

SYNO_NETWORK='synology_network'
PROJECT_BUILDER=$(pwd)
ROOT_DIR=$(dirname "${PROJECT_BUILDER}")
CROWDSEC_PROJECT=spksrc-crowdsec
TOOLKIT_DIR="${ROOT_DIR}/${CROWDSEC_PROJECT}"
SDK_WORK_DIR="/${CROWDSEC_PROJECT}"
CROWDSEC_PKG="${SDK_WORK_DIR}/spk/crowdsec"
CROWDSEC_PATCHES_DIR="./${CROWDSEC_PROJECT}/cross/crowdsec/patches"

DOCKER_IMAGE=synocommunity/spksrc

# Architecture Synology target for building package
ARCH="denverton"
DSM_VER="7.2"
# Crowdsec version target to build
CROWDSEC_VERS=1.6.11
CROWDSEC_REV=1
GO_MOD_VERSION=1.24
GO_VERSION_NATIVE=1.24.7
GO_DOWNLOAD_URL=https://go.dev/dl/

clean_docker_synology() {
  if [ "$(docker ps -a -q -f name=$CROWDSEC_PROJECT)" ]; then
    docker stop $CROWDSEC_PROJECT
    if [ "$(docker ps -aq -f status=exited -f name=$CROWDSEC_PROJECT)" ]; then
        # cleanup
        docker rm $CROWDSEC_PROJECT
#        docker system prune
    fi
  fi
  sudo rm -rf "${TOOLKIT_DIR}"
}

prepare_docker_synology_toolkit() {
  sudo apt install -y dos2unix

  docker network ls | grep "${SYNO_NETWORK}"
  if [ $? -eq 1 ]; then
    docker network create "${SYNO_NETWORK}"
  fi

  cd "${ROOT_DIR}"
  echo "==> Install SDK Toolkit Synology in ${TOOLKIT_DIR}"
  git clone "https://github.com/crowdsecurity/${CROWDSEC_PROJECT}.git"

  echo "==> Patching all files SDK Toolkit Synology in ${TOOLKIT_DIR}"
  sed -i "s|\(setup: [- \.a-zA-Z0-9]*\)|\1 dsm-${DSM_VER}|g" ./${CROWDSEC_PROJECT}/Makefile
  dos2unix ./${CROWDSEC_PROJECT}/mk/spksrc.checksum.mk ./${CROWDSEC_PROJECT}/mk/spksrc.tc-flags.mk ./${CROWDSEC_PROJECT}/mk/spksrc.install.mk ./${CROWDSEC_PROJECT}/mk/spksrc.spk.mk ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST ./${CROWDSEC_PROJECT}/spk/crowdsec/src/service-setup.sh
  patch ./${CROWDSEC_PROJECT}/mk/spksrc.checksum.mk "${PROJECT_BUILDER}/spksrc.checksum.mk.patch"
  patch ./${CROWDSEC_PROJECT}/mk/spksrc.tc-flags.mk "${PROJECT_BUILDER}/spksrc.tc-flags.mk.patch"
  patch ./${CROWDSEC_PROJECT}/mk/spksrc.install.mk "${PROJECT_BUILDER}/spksrc.install.mk.patch"
  patch ./${CROWDSEC_PROJECT}/mk/spksrc.spk.mk "${PROJECT_BUILDER}/spksrc.spk.mk.patch"
  patch ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile "${PROJECT_BUILDER}/Makefile_spk_crowdsec.mk.patch"
  patch ./${CROWDSEC_PROJECT}/spk/crowdsec/src/service-setup.sh "${PROJECT_BUILDER}/service-setup.sh.patch"
  patch ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile "${PROJECT_BUILDER}/Makefile_cross_crowdsec.mk.patch"
  patch ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST "${PROJECT_BUILDER}/PLIST_cross_crowdsec.patch"
  sed -i "s|\(SPK_VERS = \)[0-9]*\.[0-9]*\.[0-9]*|\1${CROWDSEC_VERS}|g" ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile
  sed -i "s|\(SPK_REV = \)[0-9]*|\1${CROWDSEC_REV}|g" ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile
  sed -i "s|\(PKG_VERS = \)[0-9]*\.[0-9]*\.[0-9]*|\1${CROWDSEC_VERS}|g" ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  sed -i "s|\(PKG_REV = \)[0-9]*|\1${CROWDSEC_REV}|g" ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  echo "==> Fix GO parameters to use ${GO_MOD_VERSION} in ./${CROWDSEC_PROJECT}/native/go/Makefile"
  sed -i "s|\(PKG_VERS = \)[\.0-9]*|\1${GO_VERSION_NATIVE}|g" ./${CROWDSEC_PROJECT}/native/go/Makefile
  sed -i "s|\(PKG_DIST_SITE = \).*$|\1${GO_DOWNLOAD_URL}|g" ./${CROWDSEC_PROJECT}/native/go/Makefile
  echo "==> Patches copied for specific Crowdsec version ${CROWDSEC_VERS} fixes in ${CROWDSEC_PATCHES_DIR}"
  if [ "${CROWDSEC_VERS}" == "1.6.11" ]; then
    find ${CROWDSEC_PATCHES_DIR} -type f -iname \*.patch -delete
    cp "${PROJECT_BUILDER}/go.mod_1.24.4.patch" "${CROWDSEC_PATCHES_DIR}/$(printf "%03d-go.mod_1.24.4.patch" "$(( $(find ${CROWDSEC_PATCHES_DIR} -maxdepth 1 -type f | wc -l) + 1))")"
  fi

  echo "==> Adding new version Makefile SDK Toolkit Synology in ${TOOLKIT_DIR}"
  mkdir -p "./${CROWDSEC_PROJECT}/toolchain/syno-${ARCH}-${DSM_VER}"
  cp "${PROJECT_BUILDER}/Makefile_${ARCH}-${DSM_VER}-x86-64.mk" "./${CROWDSEC_PROJECT}/toolchain/syno-${ARCH}-${DSM_VER}/Makefile"

  cd "${TOOLKIT_DIR}"
  docker run -td --privileged --cpuset-cpus=6 --stop-signal=SIGPWR --hostname=${CROWDSEC_PROJECT} --net="${SYNO_NETWORK}" --name=${CROWDSEC_PROJECT} \
    -v "${TOOLKIT_DIR}":"${SDK_WORK_DIR}" \
    -e TZ=Europe/Paris \
    ${DOCKER_IMAGE}
  docker exec ${CROWDSEC_PROJECT} su -s /bin/bash -c "sed -i 's|deb.debian.org/debian|archive.debian.org/debian|g' /etc/apt/sources.list && sed -i 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list && sed -i '/buster-updates/d' /etc/apt/sources.list"
  docker exec ${CROWDSEC_PROJECT} su -s /bin/bash -c "apt-get update && apt-get install -y dos2unix moreutils"
}

build_crowdsec() {
  echo "==> Deploy Toolchain DSM ${DSM_VER} for ${ARCH}..."
  docker exec ${CROWDSEC_PROJECT} su -s /bin/bash -c "cd ${SDK_WORK_DIR} && make dsm-${DSM_VER} && make toolchain-${ARCH}-${DSM_VER}"
  echo "==> Build Crowdsec ${DSM_VER} for ${ARCH}..."
  docker exec ${CROWDSEC_PROJECT} su -s /bin/bash -c "cd ${CROWDSEC_PKG} && make clean && make BUILD_RE2_WASM=1 arch-${ARCH}-${DSM_VER}"
}


case "${SHELL_OPTION}" in
clean)
  clean_docker_synology
  ;;
prepare)
  prepare_docker_synology_toolkit
  ;;
build)
  build_crowdsec
  ;;
*)
  echo -e "$USAGE_INFOS"
  exit 1
  ;;
esac

exit 0
