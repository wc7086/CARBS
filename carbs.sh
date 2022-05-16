#!/bin/bash
# fork https://github.com/LukeSmithxyz/LARBS
# Chen's Auto Rice Boostrapping Script (CARBS)
# https://github.com/chenjicheng/CARBS
# by Chen Jicheng <hi@chenjicheng.com>
# License: GNU GPLv3

### FUNCTIONS ###

error() {
	printf "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: %s\n" "$@" >&2
}

install_pkg() { pacman --noconfirm --needed -S $@; }

welcome_msg() {
	dialog --title "Welcome!" --msgbox "Welcome to Chen's Auto-Rice Bootstrapping Script!\n\nThis script will automatically install a fully-featured Linux desktop, which I use as my main machine.\n\nChen Jicheng" 10 60

	dialog --colors --title "Important Note!" --yes-label "All ready!" --no-label "Return..." --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\n\nIf it does not, the installation of some programs might fail." 9 60
}

get_user_and_pass() {
	# Prompts user for new username an password.
	name=$(dialog --title "User account name" --inputbox "First, please enter a name for the user account." 8 60 --output-fd 1) || { clear; exit 1; }
	while ! printf "%s" "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(dialog --title "User account" --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 --output-fd 1)
	done
	pass1=$(dialog --title "User account password" --insecure --no-cancel --passwordbox "Enter a password for that user." 8 60 --output-fd 1)
	pass2=$(dialog --title "User account password" --insecure --no-cancel --passwordbox "Retype password." 8 60 --output-fd 1)
	while ! [[ "$pass1" = "$pass2" ]]; do
		unset pass2
		pass1=$(dialog --title "User account password" --insecure --no-cancel --passwordbox "Passwords do not match!!! Enter password again." 8 60 --output-fd 1)
		pass2=$(dialog --title "User account password" --insecure --no-cancel --passwordbox "Retype password." 8 60 --output-fd 1)
	done
}

user_check() {
	! { id -u "$name"; } ||
	dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. CARBS can install for a user already existing, but it will \Zboverwrite\Zn any conflicting settings/dotfiles on the user account.\n\nCARBS will \Zbnot\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\n\nNote also that CARBS will change $name's password to the one you just gave." 16 60
}

pre_install_msg() {
	dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\n\nIt will take some time, but when done, you can relax even more with your complete system.\n\nNow just press <Let's go!> and the system will begin installation!" 12 60 || { clear; exit; }
}

add_user_and_pass() {
	# Adds user `$name` with password $pass1.
	printf "Adding user \"%s\"...\n" "$name"
	useradd -m -G wheel -s /bin/bash "$name" || (usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name")
	export repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	printf "%s:%s" "$name" "$pass1" | chpasswd
	unset pass1 pass2
}

refresh_keys() {
	case "$(readlink -f /sbin/init)" in
		*systemd* )
			printf "Refreshing Arch Keyring...\n"
			pacman --noconfirm -S archlinux-keyring
			;;
		*)
			printf "Enabling Arch Repositories...\n"
			pacman --noconfirm --needed -S artix-keyring artix-archlinux-support
			for repo in extra community; do
				grep -q "^\[$repo\]" /etc/pacman.conf || printf "[\$repo]
Include = /etc/pacman.d/mirrorlist-arch\n" >> /etc/pacman.conf
			done
			pacman -Sy
			pacman-key --populate archlinux
			;;
	esac
}

new_permissions() { # Set special sudoers settings for install (or after).
	sed -i "/#CARBS/d" /etc/sudoers
	printf "%s #CARBS\n" "$@" >> /etc/sudoers
}

manual_install() { # Installs $1 manually. Used only for AUR helper here.
	# Should be run after repodir is created and var is set.
	printf "Installing \"%s\", an AUR helper...\n" "$1"
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git clone --depth 1 "https://aur.archlinux.org/$1.git" "$repodir/$1" || ( cd "$repodir/$1" || return 1 && sudo -u "$name" git pull --force origin master )
	cd "$repodir/$1"
	sudo -u "$name" -D "$repodir/$1" makepkg --noconfirm -si || return 1
}

main_install() { # Installs all needed programs from main repo.
	printf "Installing \`%s\`.\n" "$@"
	install_pkg "$@"
}

git_make_install() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	printf "Installing \`%s\` via \`git\` and \`make\`. $(basename "%s")\n" "$progname" "$1"
	sudo -u "$name" git clone --depth 1 "$1" "$dir" || ( cd "$dir" || return 1 && sudo -u "$name" git pull --force origin master )
	cd "$dir" || exit 1
	make
	make install
	cd /tmp || return 1
}

aur_install() {
	printf "Installing \`%s\` from the AUR.\n" "$@"
	sudo -u "$name" $aur_helper -S --noconfirm $@
}

pip_install() {
	printf "Installing the Python package \`%s\`.\n" "$@"
	[[ -x "$(command -v "pip")" ]] || python -m ensurepip --upgrade
	yes | pip install $@
}

installation_loop() {
	([[ -f "$progs_file" ]] && cp "$progs_file" /tmp/progs.csv) || curl -Ls "$progs_file" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aur_installed=$(pacman -Qqm)
	while IFS=',' read -r tag program comment; do
		n=$((n+1))
		printf "%s" "$comment" | grep -q "^\".*\"$" && comment="$(printf "%s" "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
			"A") aur_install_list+="$program " ;;
			"G") git_make_install_list+=("$program") ;;
			"P") pip_install_list+="$program " ;;
			*) main_install_list+="$program " ;;
		esac
	done < /tmp/progs.csv
	main_install "$main_install_list"
	aur_install "$aur_install_list"
	pip_install "$pip_install_list"
	for x in "${git_make_install_list[@]}"; do
		git_make_install "$x"
	done
}

put_git_repo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	printf "Downloading and installing config files...\n"
	[[ -z "$3" ]] && branch="master" || branch="$repo_branch"
	dir=$(mktemp -d)
	[[ ! -d "$2" ]] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git clone --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
}

system_beep_off() {
	printf "Getting rid of that retarded error beep sound...\n"
	rmmod pcspkr
	printf "blacklist pcspkr\n" > /etc/modprobe.d/nobeep.conf
}

finalize(){ \
	dialog --infobox "Preparing welcome message..." 4 50
	dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\n\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\n\nChen Jicheng" 14 60
}


main() {
	### OPTIONS AND VARIABLES ###

	while getopts ":a:r:b:p:h" o; do case "${o}" in
		h) printf "Optional arguments for custom use:\n  -r: Dotfiles repository (local file or url)\n  -p: Dependencies and programs csv (local file or url)\n  -a: AUR helper (must have pacman-like syntax)\n  -h: Show this message\n" && exit 1 ;;
		r) dotfiles_repo=${OPTARG} && git ls-remote "$dotfiles_repo" || exit 1 ;;
		b) repo_branch=${OPTARG} ;;
		p) progs_file=${OPTARG} ;;
		a) aur_helper=${OPTARG} ;;
		*) printf "Invalid option: -%s\n" "$OPTARG" && exit 1 ;;
	esac done

	[[ -z "$dotfiles_repo" ]] && dotfiles_repo="https://github.com/chenjicheng/voidrice.git"
	[[ -z "$progs_file" ]] && progs_file="https://carbs.run/progs.csv"
	[[ -z "$aur_helper" ]] && aur_helper="yay"
	[[ -z "$repo_branch" ]] && repo_branch="main"

	### THE ACTUAL SCRIPT ###

	### This is how everything happens in an intuitive format and order.

	# Check if user is root on Arch distro. Install dialog.
	pacman --noconfirm --needed -Sy dialog || { error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"; exit 1; }

	# Welcome user and pick dotfiles.
	welcome_msg || ( error "User exited." && exit )

	# Get and verify username and password.
	get_user_and_pass || ( error "User exited." && exit )

	# Give warning if user already exists.
	user_check || ( error "User exited." && exit )

	# Last chance for user to back out before install.
	pre_install_msg || ( error "User exited." && exit )

	### The rest of the script requires no user input.

	# Make pacman colorful, concurrent downloads and Pacman eye-candy.
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
	sed -Ei "s/^#(ParallelDownloads).*/\1 = 3/;/^#Color$/s/#//" /etc/pacman.conf

	# Refresh Arch keyrings.
	refresh_keys || ( error "Error automatically refreshing Arch keyring. Consider doing so manually." && exit 1 )

	required_software="curl ca-certificates base-devel git ntp"
	printf "Installing \`%s\` which is required to install and configure other programs.\n" "$required_software"
	install_pkg "$required_software"

	printf "Synchronizing system time to ensure successful and secure installation of software...\n"
	ntpdate 0.pool.ntp.org

	add_user_and_pass || ( error "Error adding username and/or password." && exit 1 )

	[[ -f /etc/sudoers.pacnew ]] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

	# Allow user to run sudo without password. Since AUR programs must be installed
	# in a fakeroot environment, this is required for all builds with AUR.
	new_permissions "%wheel ALL=(ALL) NOPASSWD: ALL"

	# Use all cores for compilation.
	sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

	manual_install yay || ( error "Failed to install AUR helper." && exit 1 )

	# The command that does all the installing. Reads the progs.csv file and
	# installs each needed program the way required. Be sure to run this only after
	# the user has been created and has priviledges to run sudo without a password
	# and all build dependencies are installed.
	installation_loop

	printf "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes.\n"
	yes | sudo -u "$name" $aur_helper -S libxft-bgra-git

	# Install the dotfiles in the user's home directory
	put_git_repo "$dotfiles_repo" "/home/$name" "$repo_branch"
	rm -f "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"
	# Create default urls file if none exists.
	[[ ! -f "/home/$name/.config/newsboat/urls" ]] && printf 'https://news.ycombinator.com/rss
https://landchad.net/rss.xml
https://based.cooking/index.xml
https://www.archlinux.org/feeds/news/ "tech"\n' > "/home/$name/.config/newsboat/urls"
	# make git ignore deleted LICENSE & README.md files
	git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml" "/home/$name/.git" "/home/$name/.gitmodules"

	# Most important command! Get rid of the beep!
	system_beep_off

	# Tap to click
	[[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ]] && printf 'Section "InputClass"
	Identifier "libinput touchpad catchall"
	MatchIsTouchpad "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
	EndSection\n' > /etc/X11/xorg.conf.d/40-libinput.conf

	# This line, overwriting the `newperms` command above will allow the user to run
	# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
	new_permissions "%wheel ALL=(ALL) ALL #CARBS
	%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/paru,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/veracrypt,/usr/bin/uptime"

	# Activating numlock on bootup.
	mkdir -p /etc/systemd/system/getty@.service.d
	printf "[Service]
	ExecStartPre=/bin/sh -c 'setleds -D +num < /dev/%%I'\n" > /etc/systemd/system/getty@.service.d/activate-numlock.conf

	# Enable freetype2.
	sed -i '/^#.*FREETYPE_PROPERTIES/s/#//' /etc/profile.d/freetype2.sh

	# fcitx5 environment.
	printf "GTK_IM_MODULE=fcitx
	QT_IM_MODULE=fcitx
	XMODIFIERS=@im=fcitx
	INPUT_METHOD=fcitx
	SDL_IM_MODULE=fcitx
	GLFW_IM_MODULE=ibus\n" >> /etc/environment

	# Fix psutil
	sed -i "/curr = cpuinfo_freqs\[i\]$/ s/$/ * 1000/" /usr/lib/python3.10/site-packages/psutil/_pslinux.py

	# Enable lxpolkit
	sed -i "/^Hidden=true$/d" /etc/xdg/autostart/lxpolkit.desktop

	# Last message! Install complete!
	finalize
	clear
}
main "$@"
