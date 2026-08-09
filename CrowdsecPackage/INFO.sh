#!/bin/bash
# Copyright (c) 2000-2020 Synology Inc. All rights reserved.

source /pkgscripts/include/pkg_util.sh

# Load common package variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/src/common"

package="${PACKAGE_NAME}"
version="1.3.0"
displayname="${DISPLAY_NAME}"
os_min_ver="7.2-64570"
maintainer="Yannick LIDIE <yannick@lidie.fr>"
arch="$(pkg_get_platform)"
description="CrowdSec is an open-source and lightweight security solution that detects and responds to suspicious behaviors or attacks"
dsmuidir="ui"
[ "$(caller)" != "0 NULL" ] && return 0
pkg_dump_info
