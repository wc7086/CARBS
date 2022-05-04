#!/bin/bash
#Potential variables: timezone, lang and local

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -i "s/^#ParallelDownloads.*/ParallelDownloads = 5/;s/^#Color$/Color/" /etc/pacman.conf

# Prompts user for new username an password.
pass1=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Enter a password for that account." 8 60 --output-fd 1)
pass2=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Retype password." 8 60 --output-fd 1)
while ! [[ "$pass1" = "$pass2" ]]; do
	unset pass2
	pass1=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Passwords do not match!!! Enter password again." 8 60 --output-fd 1)
	pass2=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Retype password." 8 60 --output-fd 1)
done
printf "root:%s" "$pass1" | chpasswd
unset pass1 pass2

tz=$(cat tzfinal.tmp) && rm tzfinal.tmp
ln -sf /usr/share/zoneinfo/$tz /etc/localtime

hwclock --systohc

printf "LANG=en_US.UTF-8\n" >> /etc/locale.conf
printf "en_US.UTF-8 UTF-8\n" >> /etc/locale.gen
printf "zh_CN.UTF-8 UTF-8\n" >> /etc/locale.gen
locale-gen

pacman --noconfirm --needed -S dialog efibootmgr efivar grub networkmanager ntp vnstat

systemctl enable NetworkManager
systemctl enable vnstat
systemctl enable ntpd

# Set up ntp server
sed -i "s/Arch's //g" /etc/ntp.conf
sed -i 's/arch.pool/pool/g' /etc/ntp.conf
sed -i '/[0-9].pool/s/$/ iburst/' /etc/ntp.conf

grub-install && grub-mkconfig -o /boot/grub/grub.cfg

carbs() { curl -L https://carbs.run/testing/carbs.sh -o carbs.sh && bash carbs.sh; }
dialog --title "Install Chen's Rice" --yesno "This install script will easily let you access Chen's Auto-Rice Boostrapping Scripts (CARBS) which automatically install a full Arch Linux dwm environment.\n\nIf you'd like to install this, select yes, otherwise select no.\n\nChen Jicheng"  12 60 && carbs
