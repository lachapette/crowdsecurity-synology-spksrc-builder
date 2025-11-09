# Building CrowdSec Synology Package from WSL and Synology SDK Toolchains with Docker

> Current script is able to build a package Crowdsec 1.6.11 for Synology DSM using repositories
> 
> https://github.com/crowdsecurity/spksrc-crowdsec

- Install WSL with Docker
- From the shell launch build-crowdsec-with-docker.sh
```sh 
 build-crowdsec-with-docker.sh prepare
 # doing stuff and applying patches 
 build-crowdsec-with-docker.sh build
 # building Synology package Crowdsec
```