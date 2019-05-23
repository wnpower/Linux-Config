#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
        # Older SuSE/etc.
        OS="suse"
elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        OS="centos"
        VER=$(grep -o "[0-9]" /etc/redhat-release | head -1)

else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
fi

echo "Sistema operativo detectado: $OS, versión: $VER"
echo ""

if echo $OS | grep -i "centos\|cloudlinux\|redhat" > /dev/null; then
	echo "Ejecutando script para CentOS/CloudLinux/Red Hat..."
	yum install wget -y
	wget https://raw.githubusercontent.com/wnpower/Linux-Config/master/configure_centos.sh -O /tmp/configure_centos.sh
	bash /tmp/configure_centos.sh

elif echo $OS | grep -i "debian" > /dev/null; then
	echo "Ejecutando script para Debian..."
	apt install wget -y
        wget https://raw.githubusercontent.com/wnpower/Linux-Config/master/configure_debian.sh -O /tmp/configure_debian.sh
        bash /tmp/configure_debian.sh

elif echo $OS | grep -i "ubuntu" > /dev/null; then
        echo "Ejecutando script para Ubuntu..."
        apt install wget -y
        wget https://raw.githubusercontent.com/wnpower/Linux-Config/master/configure_ubuntu.sh -O /tmp/configure_ubuntu.sh
        bash /tmp/configure_ubuntu.sh
fi
