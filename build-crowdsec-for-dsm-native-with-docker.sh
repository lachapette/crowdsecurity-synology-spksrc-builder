#!/usr/bin/env bash
# Copyrights Yannick LIDIE
# Building CrowdSec Synology Package for DSM 7.3 from WSL and Docker Synology SDK Toolchains

SHELL_OPTION=$1
CROWDSEC_VERS=$2
USAGE_INFOS="\nUsage: $0 {prepare | build | clean} [crowdsec_version]\n\nSupported CrowdSec versions: 1.6.11, 1.7.8\nExample: $0 prepare 1.7.8"

set -euo pipefail

# Validate CrowdSec version
if [ -n "${CROWDSEC_VERS}" ] && [ "${SHELL_OPTION}" != "clean" ]; then
  case "${CROWDSEC_VERS}" in
    1.6.11|1.7.8)
      ;;
    *)
      echo "Error: Unsupported CrowdSec version '${CROWDSEC_VERS}'. Supported: 1.6.11, 1.7.8"
      echo -e "$USAGE_INFOS"
      exit 1
      ;;
  esac
fi

SYNO_NETWORK='synology_network'
PROJECT_BUILDER=$(pwd)
ROOT_DIR=$(dirname "${PROJECT_BUILDER}")
CROWDSEC_PROJECT=spksrc-crowdsec
TOOLKIT_DIR="${ROOT_DIR}/${CROWDSEC_PROJECT}"
SDK_WORK_DIR="/${CROWDSEC_PROJECT}"
CROWDSEC_PKG="${SDK_WORK_DIR}/spk/crowdsec"

# Directories for patches (absolute paths)
PATCHES_SDK_DIR="${ROOT_DIR}/${CROWDSEC_PROJECT}/patches"
PATCHES_CROWDSEC_DIR="${ROOT_DIR}/${CROWDSEC_PROJECT}/patches/crowdsec_${CROWDSEC_VERS}"
CROWDSEC_PATCHES_TARGET="${TOOLKIT_DIR}/cross/crowdsec/patches"

DOCKER_IMAGE=synocommunity/spksrc

# Architecture Synology target for building package
ARCH="denverton"
DSM_VER="7.3"
# Default CrowdSec version if not specified
CROWDSEC_VERS=${CROWDSEC_VERS:-1.7.8}
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
  if [ -d "./${CROWDSEC_PROJECT}/.git" ]; then
    echo "==> Repository already exists, cleaning and pulling latest changes"
    cd ./${CROWDSEC_PROJECT}
    git reset --hard HEAD 2>/dev/null || true
    git clean -fd 2>/dev/null || true
    git pull 2>/dev/null || true
    cd ..
  else
    git clone "https://github.com/crowdsecurity/${CROWDSEC_PROJECT}.git"
  fi

  # Copy patches and toolchain Makefile from script directory to workspace
  echo "==> Copying patches and toolchain files to workspace"
  mkdir -p "${TOOLKIT_DIR}/patches" "${TOOLKIT_DIR}/toolchain/syno-${ARCH}-${DSM_VER}"
  cp -r "${PROJECT_BUILDER}/spksrc-crowdsec/patches/"* "${TOOLKIT_DIR}/patches/" 2>/dev/null || true
  cp "${PROJECT_BUILDER}/spksrc-crowdsec/toolchain/syno-${ARCH}-${DSM_VER}/Makefile" "${TOOLKIT_DIR}/toolchain/syno-${ARCH}-${DSM_VER}/Makefile" 2>/dev/null || true

  # Fix sponge command in spksrc.service.mk (not available in container)
  sed -i 's|sponge \$@|{ cat > \$@.tmp \&\& mv \$@.tmp \$@; }|g' ./${CROWDSEC_PROJECT}/mk/spksrc.service.mk

  echo "==> Patching all files SDK Toolkit Synology in ${TOOLKIT_DIR}"
  sed -i "s|\(setup: [- \.a-zA-Z0-9]*\)|\1 dsm-${DSM_VER}|g" ./${CROWDSEC_PROJECT}/Makefile
  dos2unix ./${CROWDSEC_PROJECT}/mk/spksrc.checksum.mk ./${CROWDSEC_PROJECT}/mk/spksrc.tc-flags.mk ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST
  
  # Apply SDK patches from patches/spksrc/
  patch -p1 -d ./${CROWDSEC_PROJECT}/mk < "${PATCHES_SDK_DIR}/spksrc.checksum.mk.patch"
  patch -p1 -d ./${CROWDSEC_PROJECT}/mk < "${PATCHES_SDK_DIR}/spksrc.tc-flags.mk.patch"
  patch -p1 -d ./${CROWDSEC_PROJECT}/spk/crowdsec < "${PATCHES_SDK_DIR}/Makefile_spk_crowdsec.mk.patch"
  
  # Set CrowdSec version in Makefiles
  sed -i "s|\(SPK_VERS = \)[0-9]*\.[0-9]*\.[0-9]*|\1${CROWDSEC_VERS}|g" ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile
  sed -i "s|\(SPK_REV = \)[0-9]*|\1${CROWDSEC_REV}|g" ./${CROWDSEC_PROJECT}/spk/crowdsec/Makefile
  sed -i "s|\(PKG_VERS = \)[0-9]*\.[0-9]*\.[0-9]*|\1${CROWDSEC_VERS}|g" ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  sed -i "s|\(PKG_REV = \)[0-9]*|\1${CROWDSEC_REV}|g" ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  
  # Fix notifications paths for CrowdSec 1.7.8 (plugins -> cmd)
  sed -i 's|plugins/notifications/|cmd/notification-|g' ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  sed -i 's|/usr/lib/crowdsec/plugins/|/usr/lib/crowdsec/cmd/|g' ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  sed -i 's|Copying plugins files|Copying notification files|g' ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  # Add missing directory creation for cmd/ before file installations
  sed -i '/Copying notification files/a\\tinstall -m 755 -d $(STAGING_INSTALL_PREFIX)\/usr\/lib\/crowdsec\/cmd' ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  # Remove obsolete plugins directory creation
  sed -i '/install -m 755 -d.*usr\/lib\/crowdsec\/plugins/d' ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile

  # Add missing notification binaries for CrowdSec 1.7.8
  # Step 1: Add to /usr/sbin/ (after cscli)
  printf '\tinstall -m 551 $(GO_SRC_DIR)/cmd/notification-dummy/notification-dummy $(STAGING_INSTALL_PREFIX)/usr/sbin/notification-dummy\n' > /tmp/notif_sbin.txt
  printf '\tinstall -m 551 $(GO_SRC_DIR)/cmd/notification-file/notification-file $(STAGING_INSTALL_PREFIX)/usr/sbin/notification-file\n' >> /tmp/notif_sbin.txt
  printf '\tinstall -m 551 $(GO_SRC_DIR)/cmd/notification-sentinel/notification-sentinel $(STAGING_INSTALL_PREFIX)/usr/sbin/notification-sentinel\n' >> /tmp/notif_sbin.txt
  awk '/usr\/sbin\/cscli/ {print; while(getline < "/tmp/notif_sbin.txt") print; next} 1' ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile > /tmp/Makefile.step1
  rm -f /tmp/notif_sbin.txt

  # Step 2: Add to /usr/lib/crowdsec/cmd/ (after splunk notification)
  printf '\tinstall -m 551 $(GO_SRC_DIR)/cmd/notification-dummy/notification-dummy $(STAGING_INSTALL_PREFIX)/usr/lib/crowdsec/cmd/\n' > /tmp/notif_cmd.txt
  printf '\tinstall -m 551 $(GO_SRC_DIR)/cmd/notification-file/notification-file $(STAGING_INSTALL_PREFIX)/usr/lib/crowdsec/cmd/\n' >> /tmp/notif_cmd.txt
  printf '\tinstall -m 551 $(GO_SRC_DIR)/cmd/notification-sentinel/notification-sentinel $(STAGING_INSTALL_PREFIX)/usr/lib/crowdsec/cmd/\n' >> /tmp/notif_cmd.txt
  awk '/notification-splunk\/notification-splunk/ {print; while(getline < "/tmp/notif_cmd.txt") print; next} 1' /tmp/Makefile.step1 > /tmp/Makefile.step2
  rm -f /tmp/notif_cmd.txt /tmp/Makefile.step1

  # Step 3: Add yaml configs (after splunk.yaml)
  printf '\tinstall -m 664 $(GO_SRC_DIR)/cmd/notification-dummy/dummy.yaml $(STAGING_INSTALL_PREFIX)/etc/crowdsec/notifications/dummy.yaml\n' > /tmp/notif_yaml.txt
  printf '\tinstall -m 664 $(GO_SRC_DIR)/cmd/notification-file/file.yaml $(STAGING_INSTALL_PREFIX)/etc/crowdsec/notifications/file.yaml\n' >> /tmp/notif_yaml.txt
  printf '\tinstall -m 664 $(GO_SRC_DIR)/cmd/notification-sentinel/sentinel.yaml $(STAGING_INSTALL_PREFIX)/etc/crowdsec/notifications/sentinel.yaml\n' >> /tmp/notif_yaml.txt
  awk '/splunk.yaml/ {print; while(getline < "/tmp/notif_yaml.txt") print; next} 1' /tmp/Makefile.step2 > ./${CROWDSEC_PROJECT}/cross/crowdsec/Makefile
  rm -f /tmp/notif_yaml.txt /tmp/Makefile.step2

  # Fix PLIST for CrowdSec 1.7.8
  if [ -f "${PATCHES_CROWDSEC_DIR}/PLIST_cross_crowdsec.patch" ]; then
    sed -i 's|rsc:etc/crowdsec/patterns/\*|rsc:etc/crowdsec/patterns/aws\nrsc:etc/crowdsec/patterns/bacula\nrsc:etc/crowdsec/patterns/bro\nrsc:etc/crowdsec/patterns/cowrie_honeypot\nrsc:etc/crowdsec/patterns/exim\nrsc:etc/crowdsec/patterns/firewalls\nrsc:etc/crowdsec/patterns/haproxy\nrsc:etc/crowdsec/patterns/java\nrsc:etc/crowdsec/patterns/junos\nrsc:etc/crowdsec/patterns/linux-syslog\nrsc:etc/crowdsec/patterns/mcollective\nrsc:etc/crowdsec/patterns/modsecurity\nrsc:etc/crowdsec/patterns/mongodb\nrsc:etc/crowdsec/patterns/mysql\nrsc:etc/crowdsec/patterns/nagios\nrsc:etc/crowdsec/patterns/nginx\nrsc:etc/crowdsec/patterns/paths\nrsc:etc/crowdsec/patterns/postgresql\nrsc:etc/crowdsec/patterns/rails\nrsc:etc/crowdsec/patterns/redis\nrsc:etc/crowdsec/patterns/ruby\nrsc:etc/crowdsec/patterns/smb\nrsc:etc/crowdsec/patterns/ssh|' ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST
    sed -i '/lib:usr\/lib\/crowdsec\/plugins\//d' ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST
    # Add all notification files for CrowdSec 1.7.8
    for notif in dummy email file http sentinel slack splunk; do
      if ! grep -q "notifications/${notif}.yaml" ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST; then
        echo "rsc:etc/crowdsec/notifications/${notif}.yaml" >> ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST
      fi
      if ! grep -q "crowdsec/cmd/notification-${notif}" ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST; then
        echo "lib:usr/lib/crowdsec/cmd/notification-${notif}" >> ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST
      fi
    done
  fi
  
  # Apply CrowdSec version-specific patches for cross/crowdsec
  if [ -d "${PATCHES_CROWDSEC_DIR}" ]; then
    for patch_file in "${PATCHES_CROWDSEC_DIR}"/*.patch; do
      [ -f "$patch_file" ] || continue
      case "$(basename "$patch_file")" in
        PLIST_cross_crowdsec.patch)
          # PLIST already modified by sed commands above, skip patch to avoid artifacts
          ;;
        go.mod*.patch) 
          if [ "${CROWDSEC_VERS}" != "1.7.8" ]; then
            cp "$patch_file" ./${CROWDSEC_PROJECT}/cross/crowdsec/patches/go.mod.patch
          fi
          ;;
        *)
          cp "$patch_file" "${CROWDSEC_PATCHES_TARGET}/"
          ;;
      esac
    done
  fi

  echo "==> Fix GO parameters to use ${GO_VERSION_NATIVE} in ./${CROWDSEC_PROJECT}/native/go/Makefile"
  sed -i "s|\(PKG_VERS = \)[\.0-9]*|\1${GO_VERSION_NATIVE}|g" ./${CROWDSEC_PROJECT}/native/go/Makefile
  sed -i "s|\(PKG_DIST_SITE = \)\.*$|\1${GO_DOWNLOAD_URL}|g" ./${CROWDSEC_PROJECT}/native/go/Makefile

  # Clean default CrowdSec patches that may cause issues
  rm -f "./${CROWDSEC_PROJECT}/cross/crowdsec/patches/"* 2>/dev/null || true
  
  # Clean and copy CrowdSec version-specific patches
  if [ -d "${PATCHES_CROWDSEC_DIR}" ]; then
    echo "==> Cleaning CrowdSec patches directory"
    rm -f "${CROWDSEC_PATCHES_TARGET}"/*.patch 2>/dev/null || true
    mkdir -p "${CROWDSEC_PATCHES_TARGET}"
    echo "==> Copying CrowdSec ${CROWDSEC_VERS} specific patches to ${CROWDSEC_PATCHES_TARGET}"
    # For 1.7.8, exclude go.mod patches
    if [ "${CROWDSEC_VERS}" = "1.7.8" ]; then
      for patch_file in "${PATCHES_CROWDSEC_DIR}"/*.patch; do
        [ -f "$patch_file" ] || continue
        # Skip go.mod patches for 1.7.8
        case "$(basename "$patch_file")" in
          go.mod*.patch) continue ;;
          *) cp "$patch_file" "${CROWDSEC_PATCHES_TARGET}/" ;;
        esac
      done
    else
      cp "${PATCHES_CROWDSEC_DIR}"/*.patch "${CROWDSEC_PATCHES_TARGET}/" 2>/dev/null || true
    fi
  else
    echo "==> No CrowdSec ${CROWDSEC_VERS} specific patches found in ${PATCHES_CROWDSEC_DIR}"
    # Clean existing patches that might cause issues
    rm -f "${CROWDSEC_PATCHES_TARGET}"/*.patch 2>/dev/null || true
  fi

  # Sanitize PLIST: remove any diff artifact lines starting with +/- that patch may have left
  sed -i '/^[+-]/d' ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST
  # Remove Windows carriage returns from PLIST
  sed -i 's/\r$//' ./${CROWDSEC_PROJECT}/cross/crowdsec/PLIST

  echo "==> Cleaning default CrowdSec patches from SDK"
  rm -f "./${CROWDSEC_PROJECT}/cross/crowdsec/patches/"* 2>/dev/null || true

  echo "==> Using Makefile from ${CROWDSEC_PROJECT}/toolchain/syno-${ARCH}-${DSM_VER}"

  cd "${TOOLKIT_DIR}"
  # Clean PLIST in work directory too (remove CR)
  sed -i 's/\r$//' ./${CROWDSEC_PROJECT}/spk/crowdsec/work-denverton-7.3/PLIST 2>/dev/null || true

  docker run -td --privileged --cpuset-cpus=6 --stop-signal=SIGPWR --hostname=${CROWDSEC_PROJECT} --net="${SYNO_NETWORK}" --name=${CROWDSEC_PROJECT} \
    -v "${TOOLKIT_DIR}":"${SDK_WORK_DIR}" \
    -e TZ=Europe/Paris \
    ${DOCKER_IMAGE}
}

build_crowdsec() {
  echo "==> Deploy Toolchain DSM ${DSM_VER} for ${ARCH}..."
  docker exec ${CROWDSEC_PROJECT} su -s /bin/bash -c "cd ${SDK_WORK_DIR} && make dsm-${DSM_VER} && make toolchain-${ARCH}-${DSM_VER}"
  echo "==> Build Crowdsec ${CROWDSEC_VERS} for ${ARCH}..."
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
