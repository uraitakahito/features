#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/vscode-dev-containers/blob/main/script-library/docs/desktop-lite.md
# Maintainer: The VS Code and Codespaces Teams

NOVNC_VERSION="${NOVNCVERSION:-"1.6.0"}" # TODO: Add in a 'latest' auto-detect and swap name to 'version'
VNC_PASSWORD=${PASSWORD:-"vscode"}
if [ "$VNC_PASSWORD" = "noPassword" ]; then
    unset VNC_PASSWORD
fi
NOVNC_PORT="${WEBPORT:-6080}"
VNC_PORT="${VNCPORT:-5901}"

INSTALL_NOVNC="${INSTALL_NOVNC:-"true"}"
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"

WEBSOCKETIFY_VERSION=0.10.0

package_list="
    tigervnc-standalone-server \
    tigervnc-common \
    fluxbox \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    xdg-utils \
    fbautostart \
    at-spi2-core \
    xterm \
    eterm \
    nautilus\
    mousepad \
    seahorse \
    gnome-icon-theme \
    gnome-keyring \
    libx11-dev \
    libxkbfile-dev \
    libsecret-1-dev \
    libgbm-dev \
    libnotify4 \
    libnss3 \
    libxss1 \
    xfonts-base \
    xfonts-terminus \
    fonts-noto \
    fonts-wqy-microhei \
    fonts-droid-fallback \
    htop \
    ncdu \
    curl \
    ca-certificates\
    unzip \
    nano \
    locales"

# Packages to attempt to install if essential tools are missing (ie: vncpasswd).
# This is useful, at least, for Ubuntu 22.04 (jammy)
package_list_additional="
    tigervnc-tools"

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi
# Add default Fluxbox config files if none are already present
fluxbox_apps="$(cat \
<< 'EOF'
[transient] (role=GtkFileChooserDialog)
  [Dimensions]	{70% 70%}
  [Position]	(CENTER)	{0 0}
[end]
EOF
)"

fluxbox_init="$(cat \
<< 'EOF'
session.configVersion:	13
session.menuFile:	~/.fluxbox/menu
session.keyFile: ~/.fluxbox/keys
session.styleFile: /usr/share/fluxbox/styles/qnx-photon
session.screen0.workspaces: 1
session.screen0.workspacewarping: false
session.screen0.toolbar.widthPercent: 100
session.screen0.strftimeFormat: %a %l:%M %p
session.screen0.toolbar.tools: RootMenu, clock, iconbar, systemtray
session.screen0.workspaceNames: One,
EOF
)"

fluxbox_menu="$(cat \
<< 'EOF'
[begin] (  Application Menu  )
    [exec] (File Manager) { nautilus ~ } <>
    [exec] (Text Editor) { mousepad } <>
    [exec] (Terminal) { tilix -w ~ -e $(readlink -f /proc/$$/exe) -il } <>
    [exec] (Web Browser) { x-www-browser --disable-dev-shm-usage } <>
    [submenu] (System) {}
        [exec] (Set Resolution) { tilix -t "Set Resolution" -e bash /usr/local/bin/set-resolution } <>
        [exec] (Edit Application Menu) { mousepad ~/.fluxbox/menu } <>
        [exec] (Passwords and Keys) { seahorse } <>
        [exec] (Top Processes) { tilix -t "Top" -e htop } <>
        [exec] (Disk Utilization) { tilix -t "Disk Utilization" -e ncdu / } <>
        [exec] (Editres) {editres} <>
        [exec] (Xfontsel) {xfontsel} <>
        [exec] (Xkill) {xkill} <>
        [exec] (Xrefresh) {xrefresh} <>
    [end]
    [config] (Configuration)
    [workspaces] (Workspaces)
[end]
EOF
)"

# Copy config files if the don't already exist
copy_fluxbox_config() {
    local target_dir="$1"
    mkdir -p "${target_dir}/.fluxbox"
    touch "${target_dir}/.Xmodmap"
    if [ ! -e "${target_dir}/.fluxbox/apps" ]; then
        echo "${fluxbox_apps}" > "${target_dir}/.fluxbox/apps"
    fi
    if [ ! -e "${target_dir}/.fluxbox/init" ]; then
        echo "${fluxbox_init}" > "${target_dir}/.fluxbox/init"
    fi
    if [ ! -e "${target_dir}/.fluxbox/menu" ]; then
        echo "${fluxbox_menu}" > "${target_dir}/.fluxbox/menu"
    fi
}

apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

##########################
#  Install starts here   #
##########################

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

apt_get_update

# On older Ubuntu, Tilix is in a PPA. on Debian stretch its in backports.
if [[ -z $(apt-cache --names-only search ^tilix$) ]]; then
    . /etc/os-release
    if [ "${ID}" = "ubuntu" ]; then
        check_packages apt-transport-https software-properties-common
        add-apt-repository -y ppa:webupd8team/terminix
    elif [ "${VERSION_CODENAME}" = "stretch" ]; then
        echo "deb http://deb.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/stretch-backports.list
    fi
    apt-get update
    if [[ -z $(apt-cache --names-only search ^tilix$) ]]; then
        echo "(!) WARNING: Tilix not available on ${ID} ${VERSION_CODENAME} architecture $(uname -m). Skipping."
    else
        package_list="${package_list} tilix"
    fi
else
    package_list="${package_list} tilix"
fi

# Install X11, fluxbox and VS Code dependencies
check_packages ${package_list}

# if Ubuntu-24.04, noble(numbat) found, then will install libasound2-dev instead of libasound2.
# this change is temporary, https://packages.ubuntu.com/noble/libasound2 will switch to libasound2 once it is available for Ubuntu-24.04, noble(numbat)
. /etc/os-release
if [ "${ID}" = "ubuntu" ] && [ "${VERSION_CODENAME}" = "noble" ]; then
    echo "Ubuntu 24.04, Noble(Numbat) detected. Installing libasound2-dev package..."
    check_packages "libasound2-dev"
else 
    check_packages "libasound2"
fi

# On newer versions of Ubuntu (22.04), 
# we need an additional package that isn't provided in earlier versions
if ! type vncpasswd > /dev/null 2>&1; then
    check_packages ${package_list_additional}
fi

# Install Emoji font if available in distro - Available in Debian 10+, Ubuntu 18.04+
if dpkg-query -W fonts-noto-color-emoji > /dev/null 2>&1 && ! dpkg -s fonts-noto-color-emoji > /dev/null 2>&1; then
    apt-get -y install --no-install-recommends fonts-noto-color-emoji
fi

# Check at least one locale exists
if ! grep -o -E '^\s*en_US.UTF-8\s+UTF-8' /etc/locale.gen > /dev/null; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
fi

# Install the Cascadia Code fonts - https://github.com/microsoft/cascadia-code
if [ ! -d "/usr/share/fonts/truetype/cascadia" ]; then
    curl -sSL https://github.com/microsoft/cascadia-code/releases/download/v2008.25/CascadiaCode-2008.25.zip -o /tmp/cascadia-fonts.zip
    unzip /tmp/cascadia-fonts.zip -d /tmp/cascadia-fonts
    mkdir -p /usr/share/fonts/truetype/cascadia
    mv /tmp/cascadia-fonts/ttf/* /usr/share/fonts/truetype/cascadia/
    rm -rf /tmp/cascadia-fonts.zip /tmp/cascadia-fonts
fi

# Install noVNC
if [ "${INSTALL_NOVNC}" = "true" ] && [ ! -d "/usr/local/novnc" ]; then
    mkdir -p /usr/local/novnc
    curl -sSL https://github.com/novnc/noVNC/archive/v${NOVNC_VERSION}.zip -o /tmp/novnc-install.zip
    unzip /tmp/novnc-install.zip -d /usr/local/novnc
    cp /usr/local/novnc/noVNC-${NOVNC_VERSION}/vnc.html /usr/local/novnc/noVNC-${NOVNC_VERSION}/index.html
    curl -sSL https://github.com/novnc/websockify/archive/v${WEBSOCKETIFY_VERSION}.zip -o /tmp/websockify-install.zip
    unzip /tmp/websockify-install.zip -d /usr/local/novnc
    ln -s /usr/local/novnc/websockify-${WEBSOCKETIFY_VERSION} /usr/local/novnc/noVNC-${NOVNC_VERSION}/utils/websockify
    rm -f /tmp/websockify-install.zip /tmp/novnc-install.zip

    # Install noVNC dependencies and use them.
    check_packages python3-minimal python3-numpy
    sed -i -E 's/^python /python3 /' /usr/local/novnc/websockify-${WEBSOCKETIFY_VERSION}/run
fi

# Set up folders for scripts and init files
mkdir -p /var/run/dbus /usr/local/etc/vscode-dev-containers/

# Script to change resolution of desktop
cat << EOF > /usr/local/bin/set-resolution
#!/bin/bash
RESOLUTION=\${1:-\${VNC_RESOLUTION:-1920x1080}}
DPI=\${2:-\${VNC_DPI:-96}}
IGNORE_ERROR=\${3:-"false"}
if [ -z "\$1" ]; then
    echo -e "**Current Settings **\n"
    xrandr
    echo -n -e "\nEnter new resolution (WIDTHxHEIGHT, blank for \${RESOLUTION}, Ctrl+C to abort).\n> "
    read NEW_RES
    if [ "\${NEW_RES}" != "" ]; then
        RESOLUTION=\${NEW_RES}
    fi
    if ! echo "\${RESOLUTION}" | grep -E '[0-9]+x[0-9]+' > /dev/null; then
        echo -e "\nInvalid resolution format!\n"
        exit 1
    fi
    if [ -z "\$2" ]; then
        echo -n -e "\nEnter new DPI (blank for \${DPI}, Ctrl+C to abort).\n> "
        read NEW_DPI
        if [ "\${NEW_DPI}" != "" ]; then
            DPI=\${NEW_DPI}
        fi
    fi
fi

xrandr --fb \${RESOLUTION} --dpi \${DPI} > /dev/null 2>&1

if [ \$? -ne 0 ] && [ "\${IGNORE_ERROR}" != "true" ]; then
    echo -e "\nFAILED TO SET RESOLUTION!\n"
    exit 1
fi

echo -e "\nSuccess!\n"
EOF

# Container ENTRYPOINT script
cat << EOF > /usr/local/share/desktop-init.sh
#!/bin/bash

user_name="${USERNAME}"
group_name="$(id -gn ${USERNAME})"
LOG=/tmp/container-init.log

export DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-"autolaunch:"}"
export DISPLAY="\${DISPLAY:-:1}"
export VNC_RESOLUTION="\${VNC_RESOLUTION:-1440x768x16}" 
export LANG="\${LANG:-"en_US.UTF-8"}"
export LANGUAGE="\${LANGUAGE:-"en_US.UTF-8"}"

# Execute the command it not already running
startInBackgroundIfNotRunning()
{
    log "Starting \$1."
    echo -e "\n** \$(date) **" | sudoIf tee -a /tmp/\$1.log > /dev/null
    if ! pgrep -x \$1 > /dev/null; then
        keepRunningInBackground "\$@"
        while ! pgrep -x \$1 > /dev/null; do
            sleep 1
        done
        log "\$1 started."
    else
        echo "\$1 is already running." | sudoIf tee -a /tmp/\$1.log > /dev/null
        log "\$1 is already running."
    fi
}

# Keep command running in background
keepRunningInBackground()
{
    (\$2 bash -c "while :; do echo [\\\$(date)] Process started.; \$3; echo [\\\$(date)] Process exited!; sleep 5; done 2>&1" | sudoIf tee -a /tmp/\$1.log > /dev/null & echo "\$!" | sudoIf tee /tmp/\$1.pid > /dev/null)
}

# Use sudo to run as root when required
sudoIf()
{
    if [ "\$(id -u)" -ne 0 ]; then
        sudo "\$@"
    else
        "\$@"
    fi
}

# Use sudo to run as non-root user if not already running
sudoUserIf()
{
    if [ "\$(id -u)" -eq 0 ] && [ "\${user_name}" != "root" ]; then
        sudo -u \${user_name} "\$@"
    else
        "\$@"
    fi
}

# Log messages
log()
{
    echo -e "[\$(date)] \$@" | sudoIf tee -a \$LOG > /dev/null
}

# Function to compare versions
version_gt() {
    # returns 0 if \$1 > \$2
    [ "\$(printf '%s\n' "\$2" "\$1" | sort -V | head -n1)" != "\$1" ]
}


log "** SCRIPT START **"

# Start dbus.
log 'Running "/etc/init.d/dbus start".'
if [ -f "/var/run/dbus/pid" ] && ! pgrep -x dbus-daemon  > /dev/null; then
    sudoIf rm -f /var/run/dbus/pid
fi
sudoIf /etc/init.d/dbus start 2>&1 | sudoIf tee -a /tmp/dbus-daemon-system.log > /dev/null
while ! pgrep -x dbus-daemon > /dev/null; do
    sleep 1
done

# Startup tigervnc server and fluxbox
sudoIf rm -rf /tmp/.X11-unix /tmp/.X*-lock
mkdir -p /tmp/.X11-unix
sudoIf chmod 1777 /tmp/.X11-unix
sudoIf chown root:\${group_name} /tmp/.X11-unix
if [ "\$(echo "\${VNC_RESOLUTION}" | tr -cd 'x' | wc -c)" = "1" ]; then VNC_RESOLUTION=\${VNC_RESOLUTION}x16; fi
screen_geometry="\${VNC_RESOLUTION%*x*}"
screen_depth="\${VNC_RESOLUTION##*x}"

# Check if VNC_PASSWORD is set and use the appropriate command
common_options="tigervncserver \${DISPLAY} -geometry \${screen_geometry} -depth \${screen_depth} -rfbport ${VNC_PORT} -dpi \${VNC_DPI:-96} -localhost -desktop fluxbox -fg"

if [ -n "\${VNC_PASSWORD+x}" ]; then
    startInBackgroundIfNotRunning "Xtigervnc" sudoUserIf "\${common_options} -passwd /usr/local/etc/vscode-dev-containers/vnc-passwd"
else
    startInBackgroundIfNotRunning "Xtigervnc" sudoUserIf "\${common_options} -SecurityTypes None"
fi

# Spin up noVNC if installed and not running.
if [ -d "/usr/local/novnc" ]; then
    if [ "\$(ps -ef | grep /usr/local/novnc/noVNC*/utils/launch.sh | grep -v grep)" = "" ] && [ "\$(ps -ef | grep /usr/local/novnc/noVNC*/utils/novnc_proxy | grep -v grep)" = "" ]; then
        if version_gt "${NOVNC_VERSION}" "1.2.0"; then
            keepRunningInBackground "noVNC" sudoIf "/usr/local/novnc/noVNC*/utils/novnc_proxy --listen ${NOVNC_PORT} --vnc localhost:${VNC_PORT}"
            log "noVNC started with novnc_proxy."
        else
            keepRunningInBackground "noVNC" sudoIf "/usr/local/novnc/noVNC*/utils/launch.sh --listen ${NOVNC_PORT} --vnc localhost:${VNC_PORT}"
            log "noVNC started with launch.sh."
        fi
    else
        log "noVNC is already running."
    fi
else
    log "noVNC is not installed."
fi

# Run whatever was passed in
if [ -n "\$1" ]; then
    log "Executing \$@"
    exec "\$@"
else
    log "No command provided to execute."
fi
log "** SCRIPT EXIT **"
EOF

if [ -n "${VNC_PASSWORD+x}" ]; then
    echo "${VNC_PASSWORD}" | vncpasswd -f > /usr/local/etc/vscode-dev-containers/vnc-passwd
fi
chmod +x /usr/local/share/desktop-init.sh /usr/local/bin/set-resolution

# Set up fluxbox config
copy_fluxbox_config "/root"
if [ "${USERNAME}" != "root" ]; then
    copy_fluxbox_config "/home/${USERNAME}"
    chown -R ${USERNAME} /home/${USERNAME}/.Xmodmap /home/${USERNAME}/.fluxbox
fi

# Clean up
rm -rf /var/lib/apt/lists/*

# Determine the message based on whether VNC_PASSWORD is set
if [ -n "${VNC_PASSWORD+x}" ]; then
    PASSWORD_MESSAGE="In both cases, use the password \"${VNC_PASSWORD}\" when connecting"
else
    PASSWORD_MESSAGE="In both cases, no password is required."
fi

# Display the message
cat << EOF


You now have a working desktop! Connect to in one of the following ways:

- Forward port ${NOVNC_PORT} and use a web browser to start the noVNC client (recommended)
- Forward port ${VNC_PORT} using VS Code client and connect using a VNC Viewer

${PASSWORD_MESSAGE}

(*) Done!

EOF
