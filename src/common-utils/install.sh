#!/bin/sh
#-------------------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://github.com/devcontainers/features/blob/main/LICENSE for license information.
#-------------------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/devcontainers/features/tree/main/src/common-utils
# Maintainer: The Dev Container spec maintainers

set -e

INSTALL_ZSH="${INSTALLZSH:-"true"}"
CONFIGURE_ZSH_AS_DEFAULT_SHELL="${CONFIGUREZSHASDEFAULTSHELL:-"false"}"
INSTALL_OH_MY_ZSH="${INSTALLOHMYZSH:-"true"}"
INSTALL_OH_MY_ZSH_CONFIG="${INSTALLOHMYZSHCONFIG:-"true"}"
UPGRADE_PACKAGES="${UPGRADEPACKAGES:-"true"}"
USERNAME="${USERNAME:-"automatic"}"
# NOTE: USER_UID and USER_GID defined here are NOT used in this script.
# This script executes main.sh via 'exec', and main.sh reads USERUID/USERGID
# (not UID/GID) from environment variables.
# To set custom UID/GID, use USERUID and USERGID when calling this script:
#
#   USERUID=1001 USERGID=1001 ./install.sh
#
USER_UID="${UID:-"automatic"}"
USER_GID="${GID:-"automatic"}"
ADD_NON_FREE_PACKAGES="${NONFREEPACKAGES:-"false"}"
INSTALL_SSL="${INSTALLSSL:-"true"}"
ADD_USER_TO_ROOT_GROUP="${ADDUSERTOROOTGROUP:-"false"}"

MARKER_FILE="/usr/local/etc/vscode-dev-containers/common"

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# If we're using Alpine, install bash before executing
. /etc/os-release
if [ "${ID}" = "alpine" ]; then
    apk add --no-cache bash
fi
if [ "${ID}" = "azurelinux" ]; then
    tdnf install -y curl git 
fi
exec /bin/bash "$(dirname $0)/main.sh" "$@"
exit $?
