#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGFILE="/var/log/configure_linux.log"

SSH_PORT=2022

echo "Actualizando SO e instalando paquetes básicos..."
apt update
DEBIAN_FRONTEND=noninteractive apt-get --yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
DEBIAN_FRONTEND=noninteractive apt-get --yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
apt install ca-certificates -y
apt install screen ntpdate git -y

# CREANDO SWAP SI NO TIENE
if ! free | awk '/^Swap:/ {exit (!$2 || ($2<2194300))}'; then
        echo "SWAP no detectada o menos de 2GB. Configurando..."

        dd if=/dev/zero of=/swap count=4096 bs=1MiB
        chmod 600 /swap
        mkswap /swap
        swapon /swap
        echo "/swap swap swap sw 0 0" >> /etc/fstab
fi

echo "Configurando Red..."
echo "Reescribiendo /etc/resolv.conf..."

echo "nameserver 8.8.8.8" > /etc/resolv.conf # Google
echo "nameserver 8.8.4.4" >> /etc/resolv.conf # Google

echo "Configurando SSH..."
sed -i 's/^X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

echo "Cambiando puerto SSH default 22 a $SSH_PORT..."
sed -i "s/^\(#\|\)Port.*/Port $SSH_PORT/" /etc/ssh/sshd_config

# En Ubuntu 23 el puerto está en otro archivo
sed -i "s/ListenStream=.*/ListenStream=$SSH_PORT/" /lib/systemd/system/ssh.socket && systemctl daemon-reload

systemctl restart ssh || systemctl restart sshd

echo "Configurando SSD (de poseer)..."
for DEVFULL in /dev/sg? /dev/sd?; do
	DEV=$(echo "$DEVFULL" | cut -d'/' -f3)
        if [ -f "/sys/block/$DEV/queue/rotational" ]; then
        	TYPE=$(grep "0" /sys/block/$DEV/queue/rotational > /dev/null && echo "SSD" || echo "HDD")
		if [ "$TYPE" = "SSD" ]; then
			cp /usr/share/doc/util-linux/examples/fstrim.service /etc/systemd/system
			cp /usr/share/doc/util-linux/examples/fstrim.timer /etc/systemd/system
			systemctl enable fstrim.timer
		fi
        fi
done

echo "Sincronizando fecha con pool.ntp.org..."
ntpdate 0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org 0.south-america.pool.ntp.org
if [ -f /usr/share/zoneinfo/America/Buenos_Aires ]; then
        echo "Seteando timezone a America/Buenos_Aires..."
        mv /etc/localtime /etc/localtime.old
        ln -s /usr/share/zoneinfo/America/Buenos_Aires /etc/localtime
fi

echo "Seteando fecha del BIOS..."
hwclock -r

echo "Instalando CRON clean de Journal..."
echo "30 22 * * * root /bin/journalctl --vacuum-time=1d; /usr/sbin/service systemd-journald restart" > /etc/cron.d/clean_journal
service cron restart

# TAREAS POST-INSTALACION

for i in "$@"
do
case $i in
        --notify-email=*)
                EMAIL="${i#*=}"
		echo "Avisando a $EMAIL..."
		# ACTIVO EL ENVIO REMOTO
		cp -af /etc/exim4/update-exim4.conf.conf /etc/exim4/update-exim4.conf.conf.bak
		sed -i 's/dc_eximconfig_configtype=.*/dc_eximconfig_configtype=\x27internet\x27/' /etc/exim4/update-exim4.conf.conf
		service exim4 restart

	        #cat "$LOGFILE" | sed ':a;N;$!ba;s/\n/<br>/g' | mailx -s "Servidor $(hostname -f) configurado con $(basename $0) $(echo -e "\nContent-Type: text/html")" -r "root@$(hostname -f) <root@$(hostname -f)>" "$EMAIL"

		echo -e "From: $(hostname -f) <$(hostname -f)>\nSubject: Servidor $(hostname -f) configurado con $(basename $0)\nContent-Type: text/html\n\n $(cat "$LOGFILE" | sed ':a;N;$!ba;s/\n/<br>\n/g')" | sendmail "$EMAIL"

		cp -af /etc/exim4/update-exim4.conf.conf.bak /etc/exim4/update-exim4.conf.conf
		service exim4 restart
	;;
esac
done

# DESACTIVAR MLOCATE
chmod -x /etc/cron.daily/mlocate

# DESACTIVAR SLEEP
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# DESINSTALAR POSTFIX
apt remove postfix -y

history -c
echo "" > /root/.bash_history

echo "Finalizado!"
