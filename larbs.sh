#!/bin/sh
# Luke's Auto Rice Boostrapping Script (LARBS)
# by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

while getopts ":a:r:b:p:h" o; do case "${o}" in
		h) printf "Optional arguments for custom use:\\n  -r: Dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit 1 ;;
		r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit 1 ;;
		b) repobranch=${OPTARG} ;;
		p) progsfile=${OPTARG} ;;
		a) aurhelper=${OPTARG} ;;
		*) printf "Invalid option: -%s\\n" "$OPTARG" && exit 1 ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/danielgleonard/voidrice.git"
[ -z "$progsfile" ] && progsfile="https://scripts.danleonard.us/arch/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"
[ -z "$repobranch" ] && repobranch="master"

### FUNCTIONS ###

installpkg(){ pacman --noconfirm --needed -S "$1" >>/var/log/larbs.sh.log 2>&1 ;}

error() { printf "%s\n" "$1" >&2; exit 1; }

welcomemsg() { \
		echo "Script started" >/var/log/larbs.sh.log
		dialog --title "Welcome!" --msgbox "Welcome to Dan's Arch Bootstrapping Script!\\n\\nThis script will automatically install a fully-featured Arch Linux desktop, which I use on my server.\\n\\n-Dan" 10 60

		dialog --colors --title "Important Note!" --yes-label "All ready!" --no-label "Return..." --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
		}

getuserandpass() { \
		# Prompts user for new username an password.
		name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
		while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
				name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
		done
		pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
		while ! [ "$pass1" = "$pass2" ]; do
				unset pass2
				pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
				pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
		done ;}

usercheck() { \
		! { id -u "$name" >>/var/log/larbs.sh.log 2>&1; } ||
		dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. This script can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nThis script will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that this script will change $name's password to the one you just gave." 14 70
	}

preinstallmsg() { \
		dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit 1; }
	}

adduserandpass() { \
		# Adds user `$name` with password $pass1.
		dialog --backtitle "Arch Linux Installation" --infobox "Adding user \"$name\"..." 4 50
		useradd -m -g wheel -s /usr/bin/fish "$name" >>/var/log/larbs.sh.log 2>&1 ||
		usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
		export repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
		echo "$name:$pass1" | chpasswd
		unset pass1 pass2 ;}

refreshkeys() { \
		case "$(readlink -f /sbin/init)" in
				*systemd* )
						dialog --backtitle "Arch Linux Installation" --infobox "Refreshing Arch Keyring..." 4 40
						pacman --noconfirm -S archlinux-keyring >>/var/log/larbs.sh.log 2>&1
						;;
				*)
						dialog --backtitle "Arch Linux Installation" --infobox "Enabling Arch Repositories..." 4 40
						pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >>/var/log/larbs.sh.log 2>&1
						for repo in extra community; do
								grep -q "^\[$repo\]" /etc/pacman.conf ||
										echo "[$repo]
Include = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
						done
						pacman -Sy >>/var/log/larbs.sh.log 2>&1
						pacman-key --populate archlinux
						;;
		esac ;}

newperms() { # Set special sudoers settings for install (or after).
		sed -i "/#LARBS/d" /etc/sudoers
		echo "$* #LARBS" >> /etc/sudoers ;}

manualinstall() { # Installs $1 manually. Used only for AUR helper here.
		# Should be run after repodir is created and var is set.
		dialog --backtitle "Arch Linux Installation" --infobox "Installing \"$1\", an AUR helper..." 4 50
		sudo -u "$name" mkdir -p "$repodir/$1"
		sudo -u "$name" git clone --depth 1 "https://aur.archlinux.org/$1.git" "$repodir/$1" >>/var/log/larbs.sh.log 2>&1 ||
				{ cd "$repodir/$1" || return 1 ; sudo -u "$name" git pull --force origin master;}
		cd "$repodir/$1"
		sudo -u "$name" -D "$repodir/$1" makepkg --noconfirm -si >>/var/log/larbs.sh.log 2>&1 || return 1
	}

maininstall() { # Installs all needed programs from main repo.
		dialog --backtitle "Arch Linux Installation" --title "Installing from Pacman" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
		installpkg "$1"
	}

gitmakeinstall() {
		progname="$(basename "$1" .git)"
		dir="$repodir/$progname"
		dialog --backtitle "Arch Linux Installation" --title "Installing programs manually" --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
		sudo -u "$name" git clone --depth 1 "$1" "$dir" >>/var/log/larbs.sh.log 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master;}
		cd "$dir" || exit 1
		make >>/var/log/larbs.sh.log 2>&1
		make install >>/var/log/larbs.sh.log 2>&1
		cd /tmp || return 1 ;}

aurinstall() { \
		dialog --backtitle "Arch Linux Installation" --title "Installing from the AUR" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
		echo "$aurinstalled" | grep -q "^$1$" && return 1
		sudo -u "$name" $aurhelper -S --noconfirm "$1" >>/var/log/larbs.sh.log 2>&1
	}

pipinstall() { \
		dialog --backtitle "Arch Linux Installation" --title "Installing from Python Pip" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
		[ -x "$(command -v "pip")" ] || installpkg python-pip >>/var/log/larbs.sh.log 2>&1
		yes | pip install "$1"
	}

installationloop() { \
		([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
		total=$(wc -l < /tmp/progs.csv)
		aurinstalled=$(pacman -Qqm)
		while IFS=, read -r tag program comment; do
				n=$((n+1))
				echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
				case "$tag" in
						"A") aurinstall "$program" "$comment" ;;
						"G") gitmakeinstall "$program" "$comment" ;;
						"P") pipinstall "$program" "$comment" ;;
						*) maininstall "$program" "$comment" ;;
				esac
		done < /tmp/progs.csv ;}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
		dialog --backtitle "Arch Linux Installation" --infobox "Downloading and installing config files..." 4 60
		[ -z "$3" ] && branch="master" || branch="$repobranch"
		dir=$(mktemp -d)
		[ ! -d "$2" ] && mkdir -p "$2"
		chown "$name":wheel "$dir" "$2" >>/var/log/larbs.sh.log 2>&1
		sudo -u "$name" git clone --bare --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir/.dotfiles" >>/var/log/larbs.sh.log 2>&1
		sudo -u "$name" git --git-dir="$dir/.dotfiles" config --local status.showUntrackedFiles >>/var/log/larbs.sh.log 2>&1
		sudo -u "$name" git --git-dir="$dir/.dotfiles" --work-tree="$dir" checkout master >>/var/log/larbs.sh.log 2>&1
		sudo -u "$name" git --git-dir="$dir/.dotfiles" --work-tree="$dir" submodule update --init --recursive >>/var/log/larbs.sh.log 2>&1
		ls -la "$dir" >>/var/log/larbs.sh.log 2>&1
		ls -la "$dir/.dotfiles" >>/var/log/larbs.sh.log 2>&1
		cd "$dir/.dotfiles"
		sudo -u "$name" git --git-dir="$dir/.dotfiles" --work-tree="$dir" submodule update --remote --recursive >>/var/log/larbs.sh.log 2>&1
		sudo -u "$name" cp -rfT "$dir" "$2" >>/var/log/larbs.sh.log 2>&1
		cd "/root"
	}

putgitreporoot() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
		dialog --backtitle "Arch Linux Installation" --infobox "Downloading and installing config files..." 4 60
		[ -z "$3" ] && branch="master" || branch="$repobranch"
		dir=$(mktemp -d)
		[ ! -d "$2" ] && mkdir -p "$2"
		git clone --bare --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir/.dotfiles" >>/var/log/larbs.sh.log 2>&1
		git --git-dir="$dir/.dotfiles" config --local status.showUntrackedFiles >>/var/log/larbs.sh.log 2>&1
		git --git-dir="$dir/.dotfiles" --work-tree="$dir" checkout master >>/var/log/larbs.sh.log 2>&1
		git --git-dir="$dir/.dotfiles" --work-tree="$dir" submodule update --init --recursive >>/var/log/larbs.sh.log 2>&1
		ls -la "$dir" >>/var/log/larbs.sh.log 2>&1
		ls -la "$dir/.dotfiles" >>/var/log/larbs.sh.log 2>&1
		cd "$dir/.dotfiles"
		git --git-dir="$dir/.dotfiles" --work-tree="$dir" submodule update --remote --recursive >>/var/log/larbs.sh.log 2>&1
		cp -rfT "$dir" "$2" >>/var/log/larbs.sh.log 2>&1
		cd "/root"
	}

fishinstall() { \
		dialog --backtitle "Arch Linux Installation" --title "Configuring Fish" --infobox "Configuring the Fish shell to look pretty." 5 70
		# curl -fsSL -o "/home/$name/oh-my-fish.fish" "https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install" >>/var/log/larbs.sh.log
		# chmod +rx "/home/$name/oh-my-fish.fish" >>/var/log/larbs.sh.log 2>&1
		# /home/$name/oh-my-fish.fish --noninteractive --yes >>/var/log/larbs.sh.log 2>&1
		# omf install https://github.com/danielgleonard/theme-ansilambda.git >>/var/log/larbs.sh.log 2>&1
		# rm ~/.config/fish/functions/fish_prompt.fish >>/var/log/larbs.sh.log 2>&1
		# omf theme ansilambda >>/var/log/larbs.sh.log 2>&1
		# sudo -u "$name" "/usr/bin/env /home/$name/oh-my-fish.fish --noninteractive --yes" >>/var/log/larbs.sh.log 2>&1
		# sudo -u "$name" "omf install https://github.com/danielgleonard/theme-ansilambda.git" >>/var/log/larbs.sh.log 2>&1
		# rm "/home/$name/.config/fish/functions/fish_prompt.fish" >>/var/log/larbs.sh.log 2>&1
		# sudo -u "$name" "omf theme ansilambda" >>/var/log/larbs.sh.log 2>&1
		# rm /home/$name/oh-my-fish.fish >>/var/log/larbs.sh.log 2>&1

		sed -i "s/\$HOME/\/home\/$name/g" "/home/$name/.config/fish/fish_variables" >>/var/log/larbs.sh.log 2>&1

		sed -i "s/\$HOME/\/root/g" /root/.config/fish/fish_variables >>/var/log/larbs.sh.log 2>&1

		dialog --backtitle "Arch Linux Installation" --title "Configuring Fish" --infobox "Generating autocompletions in Fish." 5 70
		fish_update_completions >>/var/log/larbs.sh.log 2>&1
		sudo -u "$name" fish_update_completions >>/var/log/larbs.sh.log 2>&1
	}

sshd_configure() {
		dialog --backtitle "Arch Linux Installation" --title "sshd settings" --msgbox "Configuring sshd to disable passwords and require public key authentication." 7 70
		systemctl start sshd.service >>/var/log/larbs.sh.log 2>&1
		sleep 5 >>/var/log/larbs.sh.log 2>&1
		systemctl stop sshd.service >>/var/log/larbs.sh.log 2>&1
		sleep 5 >>/var/log/larbs.sh.log 2>&1
		sed "s/PubkeyAuthentication no/PubkeyAuthentication yes/g" -i /etc/ssh/sshd_config >>/var/log/larbs.sh.log 2>&1
		sed "s/PasswordAuthentication yes/PasswordAuthentication no/g" -i /etc/ssh/sshd_config >>/var/log/larbs.sh.log 2>&1
		sed "s/ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/g" -i /etc/ssh/sshd_config >>/var/log/larbs.sh.log 2>&1
		sed "/PubkeyAuthentication yes/s/^#//" -i /etc/ssh/sshd_config >>/var/log/larbs.sh.log 2>&1
		sed "/PasswordAuthentication no/s/^#//" -i /etc/ssh/sshd_config >>/var/log/larbs.sh.log 2>&1
		sed "/ChallengeResponseAuthentication no/s/^#//" -i /etc/ssh/sshd_config >>/var/log/larbs.sh.log 2>&1
		systemctl start sshd.service >>/var/log/larbs.sh.log 2>&1
	}

systembeepoff() { dialog --backtitle "Arch Linux Installation" --infobox "Getting rid of that retarded error beep sound..." 10 50
		rmmod pcspkr
		echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

finalize(){ \
		dialog --backtitle "Arch Linux Installation" --infobox "Preparing welcome message..." 4 50
		dialog --backtitle "Arch Linux Installation" --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t Dan" 12 80
	}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl ca-certificates base-devel git ntp zsh ; do
		dialog --backtitle "Arch Linux Installation" --title "Installing from Pacman" --infobox "Installing \`$x\` which is required to install and configure other programs." 5 70
		installpkg "$x"
done

dialog --backtitle "Arch Linux Installation" --title "Time" --infobox "Synchronizing system time to ensure successful and secure installation of software..." 4 70
ntpdate ntp.illinois.edu >>/var/log/larbs.sh.log 2>&1
hwclock --systohc >>/var/log/larbs.sh.log 2>&1
timedatectl set-timezone America/Chicago >>/var/log/larbs.sh.log 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -i "s/^#ParallelDownloads = 8$/ParallelDownloads = 5/;s/^#Color$/Color/" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall yay-bin || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

dialog --backtitle "Arch Linux Installation" --title "Emoji" --infobox "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes." 5 70
yes | sudo -u "$name" $aurhelper -S libxft-bgra-git >>/var/log/larbs.sh.log 2>&1

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -f "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Same for root
putgitreporoot "$dotfilesrepo" /root "$repobranch"
rm -f /root/README.md /root/LICENSE /root/FUNDING.yml

# Create default urls file if none exists.
[ ! -f "/home/$name/.config/newsboat/urls" ] && echo "https://www.archlinux.org/feeds/news/" > "/home/$name/.config/newsboat/urls"
# make git ignore deleted LICENSE & README.md files
git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

# Configure fish shell
fishinstall

# Most important command! Get rid of the beep!
systembeepoff

# Make zsh the default shell for the user.
chsh -s /usr/bin/fish "$name" >>/var/log/larbs.sh.log 2>&1
chsh -s /usr/bin/fish >>/var/log/larbs.sh.log 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# dbus UUID must be generated for Artix runit.
dbus-uuidgen > /var/lib/dbus/machine-id

# Use system notifications for Brave on Artix
echo "export \$(dbus-launch)" > /etc/profile.d/dbus.sh

# Tap to click
[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
		Identifier "libinput touchpad catchall"
		MatchIsTouchpad "on"
		MatchDevicePath "/dev/input/event*"
		Driver "libinput"
		# Enable left mouse button by tapping
		Option "Tapping" "on"
EndSection' > /etc/X11/xorg.conf.d/40-libinput.conf

# Fix fluidsynth/pulseaudio issue.
grep -q "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" /etc/conf.d/fluidsynth ||
		echo "OTHER_OPTS='-a pulseaudio -m alsa_seq -r 48000'" >> /etc/conf.d/fluidsynth

# Start/restart PulseAudio.
pkill -15 -x 'pulseaudio'; sudo -u "$name" pulseaudio --start

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #LARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/paru,/usr/bin/pacman -Syyuw --noconfirm"

# Last message! Install complete!
finalize
clear
