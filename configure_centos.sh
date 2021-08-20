#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGFILE="/var/log/configure_linux.log"

SSH_PORT=2022

if [ ! -f /etc/redhat-release ]; then
	echo "CentOS no detectado, abortando."
	exit 0
fi

echo "Actualizando SO..."
yum update -y
yum groupinstall "Base" --skip-broken -y

if grep -i "release 8" /etc/redhat-release > /dev/null; then
	# En RHL8 mejor instalar epel porque hay paquetes faltantes
	yum install epel-release -y
fi

yum install screen -y
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/sysconfig/selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
/usr/sbin/setenforce 0
iptables-save > /root/firewall.rules

echo "Configurando Red..."
find /etc/sysconfig/network-scripts/ -name "ifcfg-*" -not -name "ifcfg-lo" | while read ETHCFG
do
	sed -i '/^PEERDNS=.*/d' $ETHCFG
	sed -i '/^DNS1=.*/d' $ETHCFG
	sed -i '/^DNS2=.*/d' $ETHCFG
	
	echo "PEERDNS=no" >> $ETHCFG
	echo "DNS1=8.8.8.8" >> $ETHCFG
	echo "DNS2=8.8.4.4" >> $ETHCFG

done

echo "Reescribiendo /etc/resolv.conf..."

echo "nameserver 8.8.8.8" > /etc/resolv.conf # Google
echo "nameserver 8.8.4.4" >> /etc/resolv.conf # Google


echo "Configurando SSH..."
sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config

echo "Cambiando puerto SSH..."
if [ -d /etc/csf ]; then
	echo "Abriendo CSF..."
        CURR_CSF_IN=$(grep "^TCP_IN" /etc/csf/csf.conf | cut -d'=' -f2 | sed 's/\ //g' | sed 's/\"//g' | sed "s/,$SSH_PORT,/,/g" | sed "s/,$SSH_PORT//g" | sed "s/$SSH_PORT,//g" | sed "s/,,//g")
        sed -i "s/^TCP_IN.*/TCP_IN = \"$CURR_CSF_IN,$SSH_PORT\"/" /etc/csf/csf.conf
        csf -r
fi

echo "Cambiando puerto SSH default 22 a $SSH_PORT..."
sed -i "s/^\(#\|\)Port.*/Port $SSH_PORT/" /etc/ssh/sshd_config

service sshd restart

# FIREWALL

# SI TIENE SOLO IPTABLES
if [ -f /etc/sysconfig/iptables ]; then
	sed -i 's/dport 22 /dport 2022 /' /etc/sysconfig/iptables
	service iptables restart 2>/dev/null
fi

# SI TIENE FIREWALLD
if systemctl is-enabled firewalld | grep "^enabled$" > /dev/null; then
	if systemctl is-active firewalld | grep "^inactive$" > /dev/null; then
		service firewalld restart
	fi
	firewall-cmd --permanent --add-port=2022/tcp > /dev/null
	firewall-offline-cmd --add-port=2022/tcp > /dev/null
	firewall-cmd --reload 
fi

echo "Configurando FSCK..."
grubby --update-kernel=ALL --args=fsck.repair=yes
grep "fsck.repair" /etc/default/grub > /dev/null || sed 's/^GRUB_CMDLINE_LINUX="/&fsck.repair=yes /' /etc/default/grub

if grep -i "release 8" /etc/redhat-release > /dev/null; then
	echo "Configurando dnf-automatic ..."
	yum -y install dnf-automatic
	sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
	systemctl enable --now dnf-automatic.timer
else
        echo "Configurando Yum-Cron..."
        yum -y install yum-cron
        sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/yum/yum-cron.conf
        systemctl start yum-cron.service
fi

echo "Configurando SSD (de poseer)..."
for DEVFULL in /dev/sg? /dev/sd?; do
	DEV=$(echo "$DEVFULL" | cut -d'/' -f3)
        if [ -f "/sys/block/$DEV/queue/rotational" ]; then
        	TYPE=$(grep "0" /sys/block/$DEV/queue/rotational > /dev/null && echo "SSD" || echo "HDD")
		if [ "$TYPE" = "SSD" ]; then
			systemctl enable fstrim.timer

		fi
        fi
done

if grep -i "release 8" /etc/redhat-release > /dev/null; then
        echo "Instalando Chrony..."
	yum install chrony -y
        systemctl enable chronyd
else
	yum install ntpdate -y
        echo "Sincronizando fecha con pool.ntp.org..."
        ntpdate 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org 0.south-america.pool.ntp.org
fi

if [ -f /usr/share/zoneinfo/America/Buenos_Aires ]; then
        echo "Seteando timezone a America/Buenos_Aires..."
        mv /etc/localtime /etc/localtime.old
        ln -s /usr/share/zoneinfo/America/Buenos_Aires /etc/localtime
fi

echo "Seteando fecha del BIOS..."
hwclock -r

echo "Instalando GIT..."
yum install git -y

echo "Instalando CRON clean de Journal..."
echo "30 22 * * * root /usr/bin/journalctl --vacuum-time=1d; /usr/sbin/service systemd-journald restart" > /etc/cron.d/clean_journal
service crond restart

# TAREAS POST-INSTALACION

for i in "$@"
do
case $i in
        --notify-email=*)
                EMAIL="${i#*=}"
		echo "Avisando a $EMAIL..."
	        cat "$LOGFILE" | sed ':a;N;$!ba;s/\n/<br>\n/g' | mailx -s "Servidor $(hostname -f) configurado con $(basename $0) $(echo -e "\nContent-Type: text/html")" -r "$(hostname -f) <$(hostname -f)>" "$EMAIL"
	;;
esac
done

# DESACTIVAR MLOCATE
if ! (grep -i "release 8" /etc/redhat-release > /dev/null); then
	chmod -x /etc/cron.daily/mlocate
fi

echo "Finalizado!"
