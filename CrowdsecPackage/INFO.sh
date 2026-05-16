#!/bin/bash
# Copyright (c) 2000-2020 Synology Inc. All rights reserved.

source /pkgscripts/include/pkg_util.sh

package="crowdsec"
version="1.3.0"
displayname="CrowdSec"
os_min_ver="7.2"
maintainer="Synology Inc."
arch="$(pkg_get_platform)"
description="this is an example package"
dsmuidir="ui"
[ "$(caller)" != "0 NULL" ] && return 0
pkg_dump_info
