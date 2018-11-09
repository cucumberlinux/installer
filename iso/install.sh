#!/bin/bash

# Copyright 2017, 2018 Scott Court
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

RESPIN_NAME="Cucumber Linux"
VERSION="§VERSION§ §ARCH§"
ARCH="§ARCH§"
ORIGINAL_TITLE="$RESPIN_NAME Installer"
TITLE="$ORIGINAL_TITLE"
INSTALL_SOURCE="/media/install/cucumber-§ARCH§"

# Check if we are installing via a serial console
if [[ "$(tty)" = /dev/ttyS* ]]; then 
	export SERIAL=$(tty | rev | cut -d / -f 1 | rev)
	TITLE="$RESPIN_NAME Serial Installer ($SERIAL)"
fi

# Gets the mountpoint for drive $1
get_mountpoint () {
	cat /tmp/fstab | grep $1 2> /dev/null | awk '{ print $2 }'
}

# Prepares the chroot environment
prepare_chroot () {
	if [ -z "$(df | grep /mnt/dev)" ]; then
		mount --bind /dev /mnt/dev
	fi
	if [ -z "$(df | grep /mnt/proc)" ]; then
		mount --bind /proc /mnt/proc
	fi
	if [ -z "$(df | grep /mnt/sys)" ]; then
		mount --bind /sys /mnt/sys
	fi
}

# Brings up the installer menu
installer_menu () {
	dialog --title "$TITLE" --nocancel \
		--menu "$RESPIN_NAME $VERSION Installer" 13 60 6 \
		"1"	"Partition and format the hard drives" \
		"2"	"Select the mountpoints" \
		"3"	"Mount the filesystem" \
		"4"	"Install the base system" \
		"5"	"Configure the system" \
		"6"	"Install the bootloader" 2> /tmp/choice
	STATUS=$?
	
	if [ $STATUS -ne 0 ]; then
		exit
	fi
		
	choice=$(cat /tmp/choice)

	case $choice in
		"1")
			partition_drives
			;;
		"2")
			setup_mountpoints
			;;
		"3")
			mount_partitions
			;;
		"4")
			install_base
			;;
		"5")
			configure_system
			;;
		"6")
			install_bootloader
			;;
	esac
	
}

# Brings up the advanced installation options menu
advanced_install_options () {
	while [ true ]; do
		dialog --title "$TITLE - Advanced Installation Options" --cancel-label Back --menu "Advanced options for installing Cucumber Linux. Most people probably don't need to come here and can just start the installation." 15 0 6 Serial "Install Cucumber Linux to use a serial console." 2> /tmp/choice || return
		choice=$(cat /tmp/choice)
		case $choice in
			"Serial")
				dialog --title "$TITLE - Serial Installation" --inputbox "You can optionally install Cucumber Linux to use a serial terminal as a primary console. To do this, enter the name of the serial device without the leading /dev/ (e.g. ttyS0) in the box below. To disable serial installation, leave the box empty." 0 0 $SERIAL 2> /tmp/choice || continue
				export SERIAL=$(cat /tmp/choice)
				if [ -z "$SERIAL" ]; then
					TITLE="$ORIGINAL_TITLE"
				else
					TITLE="$RESPIN_NAME Serial Installer ($SERIAL)"
				fi
				;;
		esac
	done
}

# Starts the Installer
install_system () {
	
	# Partition the harddrives
	partition_drives
	
	MOUNT_STATUS=1
	while [ $MOUNT_STATUS -ne 0 ]; do
		# Setup the mount points
		setup_mountpoints
		
		# Mount the partitions
		mount_partitions
		MOUNT_STATUS=$?
	done
	
	# Install the base system
	INST_STATUS=1
	while [ $INST_STATUS -ne 0 ]; do
		install_base
		INST_STATUS=$?
	done
	
	# Configure the installed system
	configure_system
	
	# Install the bootloader
	install_bootloader
	
	# Done!
	dialog --title "$TITLE - Done!" \
			--msgbox "$RESPIN_NAME has been installed. Unless you need to do additional configuration, it is now safe to reboot into your new system." 12 60
}
	
# Starts the Upgrade Process
upgrade_system () {
	# Check that this is a full installation medium; if it is not, instruct the user that he must do
	# an online upgrade.
	if [ ! -e /media/install/.cucumber_installer_edition_full ]; then
		dialog --title "Error" --msgbox "Offline upgrades are supported only when using the full edition of the installation medium; you are using the basic edition. To perform an offline upgrade, please restart this process using the full edition installation medium.

Alternatively, you can perform an online upgrade using this basic edition medium by rebooting into your existing Cucumber Linux installation, mounting this medium and running the 'upgrade.sh' script at the root of this filesystem." 0 0
		return
	fi

	dialog --inputbox "Enter the root partition for the installation you want to upgrade." 0 0 "/dev/sda1" 2> /tmp/choice || return
	partition=$(cat /tmp/choice)

	# Attempt to mount and check for success
	umount -fl /mnt
	mount $partition /mnt
	if [ $? -ne 0 ]; then
		dialog --msgbox "There was an error mounting $partition." 0 0
		return
	fi

	# Check that the partition is a Cucumber Linux root partition
	if [ -z "$(grep 'DISTRIB_ID="Cucumber Linux"' /mnt/etc/lsb-release)" ]; then
		dialog --msgbox "$partition is not the root partition for an existing Cucumber Linux installation. Upgrading it is impossible." 0 0
		return
	fi

	# Chroot and mount the rest of the system's partitions
	prepare_chroot
	chroot /mnt /usr/bin/env -i \
		HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		mount -a

	# Start the upgrade script
	USER=root ROOT=/mnt TREE="file:///media/install" /media/install/upgrade.sh
	if [ $? -ne 0 ]; then
		cat << EOF
********************************************************************************
**************************** SYSTEM UPGRADE FAILED *****************************
********************************************************************************

Your system update has failed; any error messages have been printed above this
message. Please take note of this message and include it in any bug reports or
support requests. Press enter to return to the main menu.
EOF
		read
		return
	fi
	
}

# Partition the hard drives
partition_drives () {
	dialog --title "$TITLE - Partition and Format Drives" \
		--msgbox "It is time to partition and format your hard drives. The installer is going to drop to a shell. Partition your drives using fdisk or cfdisk. If you are using a GPT partition table, then use gdisk or cgdisk to do the partitioning instead. Once the partitions have been created format them using mkfs.<type>. When you are done, exit the shell to continue installation." 12 60
		/bin/bash
}

# Set up the partition mount points
setup_mountpoints () {
	
	touch /tmp/fstab
	
	while [ true ]; do
		ARGS="Done:Done setting up partitions"
		
		for i in $(lsblk -lno NAME); do
			if [ $(expr length $i) -gt 3 ]; then
				unset DEVNAME
				unset LABEL
				unset UUID
				unset TYPE
				blkid /dev/$i -o export > /tmp/sourcefile
				source /tmp/sourcefile
				MOUNTPOINT=$(get_mountpoint $UUID)
				
				if [ -z $TYPE ]; then
					TYPE="unknown"
				fi
				
				if [ -z $MOUNTPOINT ]; then
					ARGS=$ARGS":$i $LABEL:not used ($TYPE partition)"
				else
					ARGS=$ARGS":$i $LABEL:$MOUNTPOINT ($TYPE partition)"
				fi
			fi
		done
		
		IFS=":"
		dialog --title "$TITLE - Set up Mount Points" --nocancel --extra-button --extra-label "Root Shell" \
			--menu "Select a partition to configure its mount point. To use a partition as a swap partition, set the mount point to 'swap'. If you have an UEFI partition, you should mount it under /boot/efi. Partitions not selected will not get mounted automatically. Select done when you are finished." \
			16 60 5 $ARGS 2> /tmp/choice
		STATUS=$?
		unset IFS
		
		if [ $STATUS -eq 3 ]; then
			/bin/bash
			continue
		elif [ $STATUS -ne 0 ]; then
			installer_menu
		fi
		
		choice=$(cat /tmp/choice)
		
		if [ -z $choice ]; then
			continue
		elif [ "$choice" == "Done" ]; then
			break
		fi
		
		PARTITION=$(echo $choice | awk '{ print $1 }')
		blkid /dev/$PARTITION -o export > /tmp/sourcefile
		source /tmp/sourcefile
		MOUNTPOINT=$(get_mountpoint $UUID)
		
		dialog --inputbox "Enter mount point for $PARTITION" 8 60 $MOUNTPOINT 2> /tmp/choice
		
		choice=$(cat /tmp/choice)
		
		if [ -z $choice ]; then
			continue
		fi
		
		cat /tmp/fstab | grep -v $UUID > /tmp/fstab2
		rm /tmp/fstab
		mv /tmp/fstab2 /tmp/fstab
		if [ ! -z $choice ]; then
			echo "UUID=$UUID	$choice	$TYPE	defaults	0	0" >> /tmp/fstab
		fi
		
	done
	
	##### Setup /etc/fstab #####
	cat /tmp/fstab | grep "	/	" >> /tmp/fstab_user
	cat /tmp/fstab | grep -v "	/	" >> /tmp/fstab_user
	echo "#file system		mount-point	type		options			dump	fsck order" > /tmp/fstab2
	# Make sure / is first in fstab
	cat /tmp/fstab | grep "	/	" >> /tmp/fstab2
	cat /tmp/fstab | grep -v "	/	" >> /tmp/fstab2
	# And add the kernel filesystems
	echo "proc			/proc		proc		nosuid,noexec,nodev	0	0" >> /tmp/fstab2
	echo "sysfs			/sys		sysfs		nosuid,noexec,nodev	0	0" >> /tmp/fstab2
	echo "devpts			/dev/pts	devpts		gid=5,mode=620		0	0" >> /tmp/fstab2
	echo "tmpfs			/run		tmpfs		defaults		0	0" >> /tmp/fstab2
	echo "devtmpfs		/dev		devtmpfs	mode=0755,nosuid	0	0" >> /tmp/fstab2
	rm /tmp/fstab
	mv /tmp/fstab2 /tmp/fstab
}

# Mounts the installation partitions appropriately under /mnt
mount_partitions () {
	while read i; do
		if [[ $i = \#* ]]; then
			continue
		fi
	
		UUID=$(echo $i | awk '{ print $1 }')
		MOUNTPOINT=$(echo $i | awk '{ print $2 }')
		TYPE=$(echo $i | awk '{ print $3 }')
		
		if [ $TYPE == "swap" ]; then
			continue
		fi
		
		echo "Mounting $UUID at /mnt/$MOUNTPOINT"
		mkdir -p /mnt/$MOUNTPOINT
		mount $UUID /mnt/$MOUNTPOINT
		STATUS=$?
		
		if [ $STATUS -ne 0 ]; then
			dialog --title "$TITLE - Error Mounting Partitions" \
				--msgbox "There was an error mounting $MOUNTPOINT. Please fix your mountpoint configuration" 12 60
			return 1
		fi
	done </tmp/fstab_user
	
	return 0
}

# Installs the base system
install_base () {
	# Select package groups
	echo "dialog --title \"$TITLE - Select Package Groups\" --no-cancel \\" > /tmp/select_groups
	echo "	--checklist \"Select the package groups you want to install.\" 20 76 13 \\" >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/base ] &&	 	echo 'base            "The base system (required)." on \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/apps ] && 		echo 'apps            "Various applications." on \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/dev ] && 		echo 'dev             "Program development tools." on \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/kernel ] && 	echo 'kernel          "Source code for the Linux kernel." off \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/lang ] && 		echo 'lang            "Support for additional languages." on \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/lib ] && 		echo 'lib             "System libraries." on \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/net ] && 		echo 'net             "Networking programs." on \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/x ] && 		echo 'x               "The X window system." off \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/xapps ] && 		echo 'xapps           "Applications for the X window system." off \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/xfce ] && 		echo 'xfce            "The XFCE desktop environment." off \' >> /tmp/select_groups
	[ -d /media/install/cucumber-§ARCH§/multilib ] && 	echo 'multilib        "32 bit compatibility libraries." off \' >> /tmp/select_groups
	echo "	2> /tmp/package_groups" >> /tmp/select_groups
	. /tmp/select_groups
	
	dialog --title "$TITLE - Select Package Groups" --no-cancel \
		--radiolist "How would you like to install the packages?" 15 60 8 \
		full		"Install every package automatically (safest)." on \
		prompt		"Prompt before installing each package." off 2> /tmp/choice
		
	choice=$(cat /tmp/choice)
	case $choice in
		"full")
			INSTARGS="--infobox"
			;;
		"prompt")
			INSTARGS="--infobox --menu"
			;;
	esac
	
	echo 100 | dialog --title "$TITLE - Installing Base System" \
	--infobox "Setting up the filesystem skeleton." 8 60
	
	# Setup the FHS
	mkdir -pv /mnt/{bin,boot,dev,etc/{opt,sysconfig},home,lib/firmware,mnt,opt,proc,run,sys}
	mkdir -pv /mnt/{media/{floppy,cdrom},sbin,srv,var}
	install -dv -m 0750 /mnt/root
	install -dv -m 1777 /mnt/tmp /mnt/var/tmp
	mkdir -pv /mnt/usr/{,local/}{bin,include,lib,sbin,src}
	mkdir -pv /mnt/usr/{,local/}share/{color,dict,doc,info,locale,man}
	mkdir -v  /mnt/usr/{,local/}share/{misc,terminfo,zoneinfo}
	mkdir -v  /mnt/usr/libexec
	mkdir -pv /mnt/usr/{,local/}share/man/man{1..8}

	# x86_64 Stuff
	if [ "$ARCH" = "x86_64" ]; then
		mkdir -pv /mnt/lib64
		mkdir -pv /mnt/usr/lib64
		mkdir -pv /mnt/usr/local/lib64
	fi

	mkdir -v /mnt/var/{log/packages,mail,spool}
	ln -sv /run /mnt/var/run
	ln -sv /run/lock /mnt/var/lock
	mkdir -pv /mnt/var/{opt,cache,log,lib/{color,misc,locate},local}
	
	# Create /etc/passwd
	cat > /mnt/etc/passwd << "EOF"
root::0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/var/run/dbus:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF
	
	# Create /etc/groups
	cat > /mnt/etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
nogroup:x:99:
users:x:999:
EOF

	# Log File Initialization
	touch /mnt/var/log/{btmp,lastlog,wtmp}
	chgrp utmp /mnt/var/log/lastlog
	chmod 664  /mnt/var/log/lastlog
	chmod 600  /mnt/var/log/btmp
	
	# Install the selected package groups
	cd $INSTALL_SOURCE
	for GROUP in $(cat /tmp/package_groups); do
		cd $GROUP
		for pkg in $(find . -name '*.txz'); do
			installpkg $INSTARGS --root /mnt $pkg 2> /dev/null
		done
		cd ..
	done
	
	
	echo 100 | dialog --title "$TITLE - Installing Base System" \
	--infobox "Finishing up installing the system." 8 60
	
	# Install /etc/fstab
	cp /tmp/fstab /mnt/etc/fstab
	
	# Setup /etc/mtab
	ln -s /proc/self/mounts /mnt/etc/mtab

	# Chroot and do what we must
	prepare_chroot
	chroot /mnt /usr/bin/env -i \
		HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		/bin/bash --login << EOF
# Enable shadowed passwords
pwconv
# Enable shadowed group passwords
grpconv
# Generate modules.dep and map files
depmod
# Update the udev hardware database
udevadm hwdb --update

exit
EOF

	# Make the symlink for the fallback kernel if it doesn't exist
	if [ ! -e /mnt/boot/vmlinuz-fallback ]; then
		ln -s $(readlink /mnt/boot/vmlinuz) /mnt/boot/vmlinuz-fallback
	fi
	
	dialog --title "$TITLE" --nocancel \
		--msgbox "The base system has been installed" 12 60
}

# Configure the installed system
configure_system () {
	dialog --title "$TITLE - Configure System" \
		--yesno "Would you like to configure your system now? If you choose not to, all system settings (root password, hostname, etc) will set to the default values." \
		12 60
		
	STATUS=$?
	
	if [ $STATUS -eq 0 ]; then
		dialog --title "$TITLE - Configure System" \
			--inputbox "Enter a hostname for the new system." 12 60 "cucumber" 2> /mnt/etc/hostname
			
		dialog --title "$TITLE - Configure System" \
		--yesno "Would you like to set a root password?" \
		12 60
		STATUS=$?
		if [ $STATUS -eq 0 ]; then
			prepare_chroot
			chroot /mnt /usr/bin/env -i \
				HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
				PATH=/bin:/usr/bin:/sbin:/usr/sbin \
				passwd
		fi
		
		clear
		prepare_chroot
		chroot /mnt /usr/bin/env -i \
			HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
			PATH=/bin:/usr/bin:/sbin:/usr/sbin \
			/var/log/setup/setup.timezone
				
		dialog --title "$TITLE - Configure System" \
		--yesno "Would you like to enter a shell to perform any additional configuration now?" \
		12 60
		STATUS=$?
		if [ $STATUS -eq 0 ]; then
			dialog --title "$TITLE" \
				--msgbox "The installer is going to drop to a shell chrooted to the new system. Configure the system and then exit the shell to continue installation." 12 60
			prepare_chroot
			chroot /mnt /usr/bin/env -i \
				HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
				PATH=/bin:/usr/bin:/sbin:/usr/sbin \
				/bin/bash --login
		fi
	else
		return
	fi
}

# Install the bootloader
install_bootloader () {
	if [ ! -e /sys/firmware/efi ]; then
		dialog --title "$TITLE - Install Bootloader" \
		--yesno "Do you want to install GRUB2 to the MBR? If you choose no, additional configuration will be necessary to boot your system. Unless you know what you're doing, select yes." \
		12 60
		
		STATUS=$?
		
		if [ $STATUS -eq 0 ]; then
			install_bios_bootloader
		fi
	else
		dialog --title "$TITLE - Install Bootloader" \
		--yesno "Your system appears to be using UEFI. Do you want to install GRUB2 to the MBR anyway? You probably don't need to unless you plan on using legacy boot." \
		12 60
		
		STATUS=$?
		
		if [ $STATUS -eq 0 ]; then
			install_bios_bootloader
		fi
		
		dialog --title "$TITLE - Install Bootloader" \
		--yesno "Would you like to create an UEFI entry to boot Cucumber Linux? If you choose no, additional configuration will be necessary to boot your system. Unless you know what you're doing, select yes." \
		12 60
		
		STATUS=$?
		
		if [ $STATUS -eq 0 ]; then
			install_uefi_bootloader
		fi
	fi
}

# Install the UEFI bootloader
install_uefi_bootloader () {
	if [ -z "$(mount | grep "/mnt/boot/efi")" ]; then
		dialog --title "$TITLE" \
		--msgbox "Error: /boot/efi isn't mounted. Setting up UEFI is not possible." 12 60
		return 1
	fi
	
	dialog --inputbox "Enter the path of the drive containing your EFI partition. Enter only the path of the drive, not the full partition path (i.e. enter /dev/sda, not /dev/sda1)." 12 60 /dev/sda 2> /tmp/choice	
	EFI_DRIVE=$(cat /tmp/choice)
	dialog --inputbox "Enter the number of the partition containing your EFI partition. Do not enter the drive path (i.e. enter 1 for /dev/sda1)." 12 60 1 2> /tmp/choice	
	EFI_PART=$(cat /tmp/choice)
	
	echo 100 | dialog --title "$TITLE - Setting up UEFI" \
	--gauge "UEFI." 8 60
	
	# Determine the necessary bootloader variables
	KERNEL_ARGS=""
	# Check for Serial Console
	if [ ! -z "$SERIAL" ]; then
		KERNEL_ARGS+="console=tty1 console=$SERIAL "
	fi
	ROOT_PARTITION=$(cat /tmp/fstab | grep "	/	" | awk '{ print $1 }')
	ROOT_PARTITION=${ROOT_PARTITION:5}
	ROOT_PARTITION=$(blkid -U $ROOT_PARTITION)
	KERNEL_ARGS+="root=$ROOT_PARTITION rw"

	# Chroot and setup UEFI from there
	prepare_chroot
	chroot /mnt /usr/bin/env -i \
		HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		/bin/bash --login << EOF
mkdir -p /boot/efi/EFI/cucumber
cp /boot/vmlinuz /boot/efi/EFI/cucumber/vmlinuz.efi
if [ ! -e /boot/efi/EFI/cucumber/vmlinuz-fallback.efi ]; then
	cp /boot/efi/EFI/cucumber/vmlinuz{,-fallback}.efi
fi
		
modprobe efivarfs
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
efibootmgr -c -d $EFI_DRIVE -p $EFI_PART -L "Cucumber Linux (Fallback Kernel)" -l "\\EFI\\cucumber\\vmlinuz-fallback.efi" -u "$KERNEL_ARGS"
efibootmgr -c -d $EFI_DRIVE -p $EFI_PART -L "Cucumber Linux" -l "\\EFI\\cucumber\\vmlinuz.efi" -u "$KERNEL_ARGS"

EOF
}

# Install the BIOS bootloader
install_bios_bootloader () {
	# Determine the necessary bootloader variables
	GRUB_COMMANDS=""
	KERNEL_LOCATION=""
	KERNEL_ARGS=""
	# Check for a seperate /boot partition
	if [ -z "$(cat /mnt/etc/fstab | grep "	/boot	")" ]; then
		KERNEL_LOCATION+="/boot"
	fi
	# Check for Serial Console
	if [ ! -z "$SERIAL" ]; then
		SERIAL_PORT=$(echo $SERIAL | rev | cut -d S -f 1 | rev)
		GRUB_COMMANDS+="serial --unit=$SERIAL_PORT --speed=9600; terminal_input --append serial; terminal_output --append serial; "
		KERNEL_ARGS+="console=tty1 console=$SERIAL "
	fi
	ROOT_PARTITION=$(cat /tmp/fstab | grep "	/	" | awk '{ print $1 }')
	ROOT_PARTITION=${ROOT_PARTITION:5}
	ROOT_PARTITION=$(blkid -U $ROOT_PARTITION)
	KERNEL_ARGS+="root=$ROOT_PARTITION rw"

	# Begin the actual installation process
	dialog --inputbox "Enter the drive to install GRUB2 on (usually /dev/sda):" 8 60 "/dev/sda" 2> /tmp/choice

	choice=$(cat /tmp/choice)
	echo 100 | dialog --title "$TITLE - Installing GRUB2" \
	--gauge "GRUB2." 8 60

	# Chroot and install grub from there
	prepare_chroot
	chroot /mnt /usr/bin/env -i \
		HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin \
		/bin/bash --login << EOF
grub-install $choice
EOF

	dialog --title "$TITLE - Install Bootloader" \
		--yesno "Do you want to install a new grub.cfg? If you choose no, additional configuration will be necessary to boot your system. If you choose yes, any other existing operating systems you may have installed will temporarily be rendered unbootable." \
		12 60
		
	STATUS=$?

	if [ $STATUS -eq 0 ]; then
		cat > /mnt/boot/grub/grub.cfg <<EOF
set default="0"
set timeout="5"
$GRUB_COMMANDS

menuentry "Cucumber Linux $VERSION" {
	linux $KERNEL_LOCATION/vmlinuz $KERNEL_ARGS
	boot
}
menuentry "Cucumber Linux $VERSION (fallback kernel)" {
	linux $KERNEL_LOCATION/vmlinuz-fallback $KERNEL_ARGS
	boot
}
EOF
	fi
}

############################## MAIN MENU ###############################
while [ true ]
do

	dialog --title "$TITLE" --nocancel \
		--menu "$RESPIN_NAME $VERSION Installer" 14 70 7 \
		"Install"	"Install $RESPIN_NAME" \
		"Upgrade"	"Upgrade an existing $RESPIN_NAME installation" \
		"Advanced"	"Advanced installation options" \
		"Menu"		"Go to a specific step of the installation" \
		"Shell"		"Drop to a root shell" \
		"Restart"	"Restart the system" \
		"Shutdown"	"Shut down the system" 2> /tmp/choice

	choice=$(cat /tmp/choice)

	case $choice in
		"Install")
			install_system
			;;
		"Upgrade")
			upgrade_system
			;;
		"Advanced")
			advanced_install_options
			;;
		"Menu")
			installer_menu
			;;
		"Shell")
			/bin/bash
			;;
		"Restart")
			init 6
			;;
		"Shutdown")
			init 0
			;;
	esac

done
