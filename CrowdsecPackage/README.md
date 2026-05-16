# synology-crowdsec-spk
#
# SPDX-License-Identifier: MIT
#
# Copyright (C) 2021-2022 Gerald Kerma <gandalf@gk2.net>
# Copyright (C) 2021-2022 CrowdSec <crowdsec@crowdsec.net>
#

Synology DSM7 package for CrowdSec (spk) 

Based on spksrc cross compilation framework for Synology NAS devices.

## Supported Versions

- **CrowdSec**: 1.6.11, 1.7.8
- **DSM**: 6.0, 7.0, 7.2, 7.3

## Build Instructions

### Using Docker Toolkit (Recommended)

Use the provided build script for native Docker-based compilation:

```bash
# Prepare the build environment
./build-crowdsec-for-dsm-native-with-docker.sh prepare [crowdsec_version]

# Build the package
./build-crowdsec-for-dsm-native-with-docker.sh build [crowdsec_version]

# Clean up
./build-crowdsec-for-dsm-native-with-docker.sh clean
```

Supported CrowdSec versions: `1.6.11`, `1.7.8`

Example:
```bash
./build-crowdsec-for-dsm-native-with-docker.sh prepare 1.7.8
./build-crowdsec-for-dsm-native-with-docker.sh build 1.7.8
```

### Using spksrc (Legacy)

Build directly with spksrc:

```bash
cd CrowdsecPackage
make clean
make arch-aarch64-7.0
```

Available architectures:
- `arch-aarch64-7.0` (DSM 7.0+ ARM64)
- `arch-aarch64-7.2` (DSM 7.2+ ARM64)
- `arch-aarch64-7.3` (DSM 7.3+ ARM64)
- `arch-denverton-7.2` (DSM 7.2+ x86_64)
- `arch-denverton-7.3` (DSM 7.3+ x86_64)

## Project Structure

- `CrowdsecPackage/` - Main package source
  - `Makefile` - Package build configuration
  - `INFO.sh` - Package metadata
  - `src/` - Source files and configurations
  - `scripts/` - Installation and service scripts
  - `SynoBuildConf/` - Synology build configurations

- `spksrc-crowdsec/` - Cross-compilation toolchain and patches
  - `patches/` - Patches for CrowdSec and spksrc
    - `crowdsec_1.6.11/` - Patches for CrowdSec 1.6.11
    - `crowdsec_1.7.8/` - Patches for CrowdSec 1.7.8
  - `toolchain/` - Toolchain configurations
    - `syno-denverton-7.2/` - DSM 7.2 toolchain (x86_64)
    - `syno-denverton-7.3/` - DSM 7.3 toolchain (x86_64)

## Changes in build-crowdsec-package-1.7.8

- Added DSM and 7.2 and 7.3 support
- Added CrowdSec 1.7.8 support with new patches
- Added `Makefile_denverton-7.8-x86-64.mk` toolchain configuration
- Added `build-crowdsec-for-dsm-native-with-docker.sh` build script
- Updated `spksrc.tc-flags.mk.patch` to include DSM 7.3
- Updated `Makefile_spk_crowdsec.mk.patch` to include DSM 7.3
- Updated `CrowdsecPackage/Makefile` with DSM 7.2/7.3 configuration
- Removed deprecated build scripts (`build-crowdsec.sh`, `build-crowdsec-with-docker.sh`, `build-packages-with-docker.sh`)
