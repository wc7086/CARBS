#!/bin/bash
#https://github.com/chenjicheng/CARBS
#This is a lazy script I have for auto-installing Arch.
#It's not officially part of CARBS, but I use it for testing.
#DO NOT RUN THIS YOURSELF because Step 1 is it reformatting drive WITHOUT confirmation,
#which means RIP in peace qq your data unless you've already backed up all of your drive.

error() {
	printf "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: %s\n" "$@" >&2
}

timedatectl set-ntp true

# Verify the boot mode
[[ -d /sys/firmware/efi/efivars ]] && boot_mode=UEFI || ( boot_mode=BIOS && error "\033[31mERROR\033[0m: The Legacy BIOS mode is not supported.\n" && exit 1 )

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -i "s/^#ParallelDownloads.*/ParallelDownloads = 5/;s/^#Color$/Color/" /etc/pacman.conf

pacman --noconfirm --needed -Sy dialog || ( error "Error at script start: Are you sure you're running this as the root user? Are you sure you have an internet connection?\n" && exit 1 )

dialog --defaultno --title "DON'T BE A BRAINLET!" --yesno "This is an Arch install script that is very rough around the edges.\n\nOnly run this script if you're a big-brane who doesn't mind deleting your entire drive.\n\nThis script is only really for me so I can autoinstall Arch.\n\nChen Jicheng"  14 60 || { clear; exit; }

mirrors_countries=($(reflector --list-countries | grep -oP "[A-Z][A-Z]"))
i=0
for mirrors_country in "${mirrors_countries[@]}"; do
	mirrors_countries_list_menu+="$i $mirrors_country "
	i=$((i+1))
done
mirrors_country_id=$(dialog --title "DON'T BE A BRAINLET!" --menu "Select your region or the region closest to you for a mirrors list." 15 60 0 $mirrors_countries_list_menu --output-fd 1) || { clear; exit; }
mirrors_country=${mirrors_countries[$mirrors_country_id]}

drives=($(find /dev | grep -wP "\/dev\/(sd|hd|vd)[a-z]+|\/dev\/nvme[1-9]+[a-z]+[1-9]+|\/dev\/mmcblk[1-9]+" | sort))
i=0
for drive in "${drives[@]}"; do
	drives_list_menu+="$i $drive "
	i=$((i+1))
done
drive_id=$(dialog --title "DON'T BE A BRAINLET!" --menu "Do you think I'm meming? Only select yes to DELET your entire drive and reinstall Arch.\n\nTo stop this script, press no." 15 60 0 $drives_list_menu --output-fd 1) || { clear; exit; }
drive=${drives[$drive_id]}

computer_name=$(dialog --no-cancel --inputbox "Enter a name for your computer." 8 60 --output-fd 1)

dialog --defaultno --title "Time Zone select" --yesno "Do you want use the default time zone(Asia/Shanghai)?.\n\nPress no for select your own time zone" 7 60 && tz="Asia/Shanghai" || tz=$(tzselect)

psize=$(dialog --no-cancel --inputbox "Enter partitionsize in gb, separated by space (swap & root)." 9 60 "12 30" --output-fd 1)

IFS=' ' read -ra SIZE <<< $psize

re='^[0-9]+$'
if ! [[ ${#SIZE[@]} -eq 2 ]] || ! [[ ${SIZE[0]} =~ $re ]] || ! [[ ${SIZE[1]} =~ $re ]] ; then
	SIZE=(12 30);
fi

reflector --country "$mirrors_country" --age 12 --sort rate --protocol https --save /etc/pacman.d/mirrorlist
pacman -Syy

sgdisk ${drive} -Z -n 1::+512M -t 1:ef00 -n 2::+${SIZE[0]}G -t 8200 -n 3::+${SIZE[1]}G -t 3:8304 -N 4 -t 4:8302

partprobe

yes | mkfs.vfat ${drive}1
mkswap ${drive}2
yes | mkfs.ext4 ${drive}3
yes | mkfs.ext4 ${drive}4
swapon ${drive}2
mount ${drive}3 /mnt
mkdir -p /mnt/boot/efi
mount ${drive}1 /mnt/boot/efi
mkdir -p /mnt/home
mount ${drive}4 /mnt/home

pacman -S --noconfirm archlinux-keyring

pacstrap /mnt linux linux-firmware linux-headers base

# install cpu microcode.
cpu=$(grep "vendor_id" /proc/cpuinfo | awk -F ': ' '{print $2}' | tail -1)
case $cpu in
	AuthenticAMD) pacstrap /mnt amd-ucode ;;
	GenuineIntel) pacstrap /mnt intel-ucode ;;
	*) printf "There is no corresponding Microcode for this CPU.\n" ;;
esac

genfstab -U /mnt >> /mnt/etc/fstab
printf "%s\n" "$computer_name" > /mnt/etc/hostname
printf "127.0.0.1	localhost
::1		localhost
127.0.1.1	%s.localdomain	%s\n" "$computer_name" "$computer_name" >> /mnt/etc/hosts

### BEGIN
# Prompts user for new username an password.
pass1=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Enter a password for that account." 8 60 --output-fd 1)
pass2=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Retype password." 8 60 --output-fd 1)
while ! [[ "$pass1" = "$pass2" ]]; do
	unset pass2
	pass1=$(dialog --title "root account password" --insecure --no-cancel --passwordbox 'Passwords do not match!!! Enter password again.' 8 60 --output-fd 1)
	pass2=$(dialog --title "root account password" --insecure --no-cancel --passwordbox "Retype password." 8 60 --output-fd 1)
done
printf "root:%s" "$pass1" | arch-chroot /mnt chpasswd
unset pass1 pass2

ln -sf /usr/share/zoneinfo/$tz /mnt/etc/localtime

arch-chroot /mnt hwclock --systohc

printf "LANG=en_US.UTF-8\n" >> /mnt/etc/locale.conf
printf "en_US.UTF-8 UTF-8\n" >> /mnt/etc/locale.gen
printf "zh_CN.UTF-8 UTF-8\n" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen

pacstrap /mnt dialog efibootmgr efivar grub networkmanager ntp vnstat

arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable vnstat
arch-chroot /mnt systemctl enable ntpd

# Set up ntp server
sed -i "s/Arch's //g" /mnt/etc/ntp.conf
sed -i 's/arch.pool/pool/g' /mnt/etc/ntp.conf
sed -i '/[0-9].pool/s/$/ iburst/' /mnt/etc/ntp.conf

arch-chroot /mnt grub-install && arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

carbs() { curl -L https://carbs.run/carbs.sh -o /mnt/carbs.sh && arch-chroot /mnt bash carbs.sh && rm /mnt/carbs.sh; }
dialog --title "Install Chen's Rice" --yesno "This install script will easily let you access Chen's Auto-Rice Boostrapping Scripts (CARBS) which automatically install a full Arch Linux dwm environment.\n\nIf you'd like to install this, select yes, otherwise select no.\n\nChen Jicheng"  12 60 && carbs
### END

dialog --defaultno --title "Final Qs" --yesno "Shutdown computer?"  5 30 && shutdown -h now
dialog --defaultno --title "Final Qs" --yesno "Return to chroot environment?"  6 30 && arch-chroot /mnt
clear
