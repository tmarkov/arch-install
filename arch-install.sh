#!/bin/bash

function progress() {
  read -p "$1 Press any key to continue."
}

SYSTEMD="iptsd"
SYSTEMD_DESKTOP="NetworkManager bluetooth avahi-daemon"
UGROUPS="audio video storage optical network users wheel games rfkill scanner power lp"
PACKAGES="base-devel cmake dosfstools gptfdisk intel-ucode neovim openssh git wget htop ncdu screen net-tools unrar unzip p7zip rfkill bind-tools alsa-utils"
PACKAGES_LINUX_SURFACE="linux-surface-headers linux-surface iptsd"
PACKAGE_DESKTOP="xorg xorg-drivers xorg-apps xf86-input-evdev xf86-input-synaptics"
PACKAGE_DESKTOP_GTK="paprefs qt5-styleplugins"
PACKAGE_DESKTOP_QT="qt5"
PACKAGE_DESKTOP_MATE="mate mate-extra lightdm-gtk-greeter-settings networkmanager pulseaudio network-manager-applet blueman gvfs-smb gvfs-mtp totem gnome-keyring"
PACKAGE_DESKTOP_MATE_DM="lightdm"
PACKAGE_DESKTOP_KDE="plasma kde-applications"
PACKAGE_DESKTOP_KDE_DM="sddm"
PACKAGE_DESKTOP_GNOME="gnome gnome-extra chrome-gnome-shell flatpak-builder networkmanager"
PACKAGE_DESKTOP_GNOME_DM="gdm"
PACKAGE_DESKTOP_CINNAMON="gnome gnome-extra networkmanager cinnamon nemo"
PACKAGE_DESKTOP_CINNAMON_DM="gdm"
PACKAGE_DESKTOP_XFCE="xfce4 xfce4-goodies lightdm-gtk-greeter-settings networkmanager pulseaudio network-manager-applet blueman gvfs-smb gvfs-mtp totem gnome-keyring"
PACKAGE_DESKTOP_XFCE_DM="lightdm"
PACKAGE_DESKTOP_DEEPIN_APPS="deepin deepin-extra networkmanager"
PACKAGE_DESKTOP_DEEPIN_DM="lightdm"
PACKAGE_DESKTOP_HTPC="gnome gnome-extra chrome-gnome-shell networkmanager steam kodi kodi kodi-addons kodi-addons-visualization"
PACKAGE_DESKTOP_HTPC_DM="gdm"
PACKAGE_EXT_CONSOLE="zsh unp lxc debootstrap rsnapshot youtube-dl samba android-tools fuseiso libnotify"
PACKAGE_EXT_OPTIMUS="bumblebee lib32-virtualgl nvidia lib32-nvidia-utils primus lib32-primus bbswitch"
PACKAGE_EXT_FONTS="ttf-liberation ttf-ubuntu-font-family ttf-droid ttf-dejavu gnu-free-fonts noto-fonts-emoji"
PACKAGE_EXT_CODECS="gst-plugins-ugly gst-plugins-bad gst-libav ffmpeg"
PACKAGE_EXT_APPS="mpv atom firefox libreoffice lib32-libpulse pulseaudio-zeroconf audacity onboard redshift xournalpp code"
PACKAGE_EXT_APPS_GAMING="steam"
PACKAGE_EXT_APPS_GTK="gtk-recordmydesktop openshot gcolor2 meld gparted evince"
PACKAGE_EXT_APPS_QT="qbittorrent"


KEYMAP='us'
ROOTDEV='/dev/nvme0n1'
UEFI=y
ROOTFS_SIZE='25G'
SWAP_SIZE='8G'
DESKTOP='MATE'
EXT_PACKAGES=("EXT_FONTS" "EXT_CODECS" "EXT_CONSOLE" "EXT_APPS" "EXT_APPS_GAMING" "EXT_APPS_GTK" "EXT_APPS_QT")
TWEAKS=("SURFACE" "INTEL" "HIBERNATE")
# TWEAKS=("SURFACE" "NO_HIDPI" "OPTIMUS" "INTEL" "FIX_GPD" "HIBERNATE")
HOSTNAME=todor-surface

# external scripts

detach='#!/bin/bash

notify_all(){
    user_list=($(who | grep -E "\(:[0-9](\.[0-9])*\)" | awk '\''{print $1 "@" $NF}'\'' | sort -u))

    for user in $user_list; do
        username=${user%@*}
        display=${user#*@}
        dbus=unix:path=/run/user/$(id -u $username)/bus

        sudo -u $username DISPLAY=${display:1:-1} \
                          DBUS_SESSION_BUS_ADDRESS=$dbus \
                          notify-send "$@"
    done
}

scmd(){
    sudo i2cset -f -y $1 0x28 0x05 0x00 0x3f 0x03 0x24 0x06 0x00 0x13 0x00 0x24 "$2" \
        0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 i
}

ibus=$(ls -lh /sys/bus/i2c/devices/ | grep "MSHW0030" | tr '\''/'\'' '\''\n'\'' | grep i2c- | grep -v MSHW0030:00 | cut -d- -f 2)

umount /run/media/*/*
if [ $(ls /run/media/* | wc -w) -eq 0 ];
then
    error="$(scmd $ibus 0x08 2>&1 && sleep 0.1 2>&1 && scmd $ibus 0x09 2>&1)"
    if [ -n "$error" ]
    then
        notify_all -h int:transient:1 "Detach failed" "$error"
    fi
else
    notify_all -h int:transient:1 "Detach failed" "Could not unmount drives"
fi'

systemd_sleep='#!/bin/bash
case $1 in
  pre)
    # unload the modules before going to sleep
    ;;
  post)
    while [ $(cat /proc/acpi/button/lid/LID0/state | grep closed | wc -l) = 1 ]
    do
      echo $(date) >> /var/log/resuspend
      echo freeze > /sys/power/state
    done
    ;;
esac'

# clean previous install attempts
umount -R /mnt &> /dev/null || true
if [ -b /dev/mapper/lvm-system ]; then
  vgchange -an lvm && sleep 2
fi

if [ -b /dev/mapper/cryptlvm ]; then
  cryptsetup luksClose /dev/mapper/cryptlvm
fi

loadkeys $KEYMAP

if grep -q "mmcblk" <<< $ROOTDEV || grep -q "nvme" <<< $ROOTDEV; then
  RDAPPEND=p
fi

# UEFI
if [ "$UEFI" = "y" ]; then
  PACKAGES="$PACKAGES efibootmgr"
else
  PACKAGES="$PACKAGES grub"
fi

DISKPW="..."
while ! [ "$DISKPW" = "$DISKPW2" ]; do
  read -sp "Enter your disk encryption password: " DISKPW
  echo
  read -sp "Repeat your disk encryption password: " DISKPW2
  echo

  echo -n "$DISKPW" > /tmp/DISKPW
done

# try to unlock previous installation
echo "Trying to unlock disks..."
cryptsetup luksOpen ${ROOTDEV}${RDAPPEND}2 cryptlvm -d /tmp/DISKPW
vgchange -ay
sleep 2

read -p "Mount and exit script (y/n)?" mountexit
if [ "$mountexit" = 'y' ]; then
  mount /dev/mapper/lvm-system /mnt
  mount ${ROOTDEV}${RDAPPEND}1 /mnt/boot
  mount /dev/mapper/lvm-home /mnt/home

  exit 1
fi

if ! [ -b /dev/mapper/lvm-system ]; then
  WIPE=y
else
  WIPE=n
fi

if [ "$WIPE" = "n" ]; then
  read -p "Do you want to WIPE the existing installation (y/n)? " WIPE
  echo
fi

if [ "$WIPE" = "y" ]; then
  # close active installation
  echo "Reload disks..."
  vgchange -an lvm
  cryptsetup luksClose cryptlvm
fi

case $DESKTOP in
  "GNOME")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_GNOME $PACKAGE_DESKTOP_GNOME_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_GNOME_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_GNOME_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="on"
  ;;
  "KDE")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_QT $PACKAGE_DESKTOP_KDE $PACKAGE_DESKTOP_KDE_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_KDE_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_KDE_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="on"
  ;;
  "MATE")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_MATE $PACKAGE_DESKTOP_MATE_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_MATE_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_MATE_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="on"
  ;;
  "CINNAMON")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_CINNAMON $PACKAGE_DESKTOP_CINNAMON_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_CINNAMON_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_CINNAMON_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="on"
  ;;
  "XFCE")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_XFCE $PACKAGE_DESKTOP_XFCE_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_XFCE_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_XFCE_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="on"
  ;;
  "DEEPIN")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_QT $PACKAGE_DESKTOP_DEEPIN $PACKAGE_DESKTOP_DEEPIN_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_DEEPIN_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_DEEPIN_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="on"
  ;;
  "HTPC")
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_HTPC $PACKAGE_DESKTOP_HTPC_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_HTPC_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_HTPC_DM"
    EXT_APPS_GTK="off"
    EXT_APPS_QT="off"
  ;;
  "MINIMAL")
    EXT_APPS_GTK="off"
    EXT_APPS_QT="off"
  ;;
  "HEADLESS")
    PACKAGES="dropbear dhcpcd $PACKAGES"
    SYSTEMD="$SYSTEMD sshd dhcpcd@eth0"
    EXT_APPS_GTK="off"
    EXT_APPS_QT="off"
  ;;
esac

if [ "$DESKTOP" = "MINIMAL" ] || [ "$DESKTOP" = "HEADLESS" ] || [ "$DESKTOP" = "HTPC" ]; then
  HAS_DESKTOP=off
else
  HAS_DESKTOP=on
fi

WANT_FONTS=$HAS_DESKTOP
WANT_CODECS=$HAS_DESKTOP

if [ "$DESKTOP" = "HTPC" ]; then
  WANT_FONTS=on
  WANT_CODECS=on
fi


for item in ${EXT_PACKAGES[@]}; do
  echo $item
  if [ "$item" = "EXT_FONTS" ]; then
    echo "Adding fonts"
    PACKAGES="$PACKAGES $PACKAGE_EXT_FONTS"
  elif [ "$item" = "EXT_CODECS" ]; then
    echo "Adding codecs"
    PACKAGES="$PACKAGES $PACKAGE_EXT_CODECS"
  elif [ "$item" = "EXT_CONSOLE" ]; then
    echo "Adding console"
    PACKAGES="$PACKAGES $PACKAGE_EXT_CONSOLE"
  elif [ "$item" = "EXT_APPS" ]; then
    echo "Adding apps"
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS"
  elif [ "$item" = "EXT_APPS_GAMING" ]; then
    echo "Adding gaming"
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS_GAMING"
  elif [ "$item" = "EXT_APPS_GTK" ]; then
    echo "Adding gtk apps"
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS_GTK"
  elif [ "$item" = "EXT_APPS_QT" ]; then
    echo "Adding qt apps"
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS_QT"
  fi
done

for item in ${TWEAKS[@]}; do
  if [ "$item" = "OPTIMUS" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_OPTIMUS"
    SYSTEMD="$SYSTEMD bumblebeed"
    UGROUPS="$UGROUPS bumblebee"
  elif [ "$item" = "INTEL" ]; then
    INTEL=y
  elif [ "$item" = "NO_HIDPI" ]; then
    NO_HIDPI=y
  elif [ "$item" == "FIX_GPD" ]; then
    CUSTOM_CMDLINE="$CUSTOM_CMDLINE fbcon=rotate:1 dmi_product_name=GPD-WINI55"
  elif [ "$item" == "HIBERNATE" ]; then
    RESUME="resume=/dev/mapper/lvm-swap"
  elif [ "$item" == "SURFACE" ]; then
    PACKAGES="$PACKAGES $PACKAGES_LINUX_SURFACE"
    SURFACE_TWEAKS=y
  fi
done

read -p 'Enter your username: ' USERNAME

while ! [ "$USERPW" = "$USERPW2" ] || [ -z "$USERPW" ]; do
  read -sp "Enter your password: " USERPW
  echo
  read -sp "Repeat your password: " USERPW2
  echo
done

if [ "$WIPE" = "y" ]; then
  cryptsize=$(parted <<<'unit MB print all' | grep ${ROOTDEV} | cut -d " " -f 3)
  echo "--- WARNING: All data on '$ROOTDEV' will be deleted! ---" > /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "Installing on ${ROOTDEV}" >> /tmp/install-summary.log
  echo " - ${ROOTDEV}${RDAPPEND}1 - Boot (512M)" >> /tmp/install-summary.log
  echo " - ${ROOTDEV}${RDAPPEND}2 - Encrypted LVM" >> /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "Encrypted LVM" >> /tmp/install-summary.log
  echo " - lvm-system ($ROOTFS_SIZE)" >> /tmp/install-summary.log
  echo " - lvm-swap ($SWAP_SIZE)" >> /tmp/install-summary.log
  echo " - lvm-home" >> /tmp/install-summary.log
else
  echo "--- WARNING: '/boot' ($ROOTDEV${RDAPPEND}1) and 'lvm-system' will be deleted! ---" > /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "Installing on ${ROOTDEV}" >> /tmp/install-summary.log
  echo " - ${ROOTDEV}${RDAPPEND}1 - Boot (format)" >> /tmp/install-summary.log
  echo " - ${ROOTDEV}${RDAPPEND}2 - Encrypted LVM (keep)" >> /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "Encrypted LVM" >> /tmp/install-summary.log
  echo " - lvm-system (format)" >> /tmp/install-summary.log
  echo " - lvm-swap ($SWAP_SIZE)" >> /tmp/install-summary.log
  echo " - lvm-home (keep)" >> /tmp/install-summary.log
fi

echo "" >> /tmp/install-summary.log
echo "Profile: $DESKTOP" >> /tmp/install-summary.log
echo "" >> /tmp/install-summary.log
echo "User: $USERNAME" >> /tmp/install-summary.log
echo "Keymap: $KEYMAP" >> /tmp/install-summary.log
echo "Hostname: $HOSTNAME" >> /tmp/install-summary.log
echo "" >> /tmp/install-summary.log
echo "Packages: $PACKAGES" >> /tmp/install-summary.log

cat /tmp/install-summary.log
read -p "Do you want to continue (y/n)? " cont
if [ "$cont" != "y" ]; then
  exit 1
fi

progress "Setting Up ${ROOTDEV}..."
if [ "$WIPE" = "y" ]; then
  dd if=/dev/zero of=${ROOTDEV} bs=4M conv=fsync count=1

  if [ "$UEFI" = "y" ]; then
    parted ${ROOTDEV} -s mklabel gpt
    parted ${ROOTDEV} -s mkpart ESP fat32 1MiB 513MiB
    parted ${ROOTDEV} -s set 1 boot on
    parted ${ROOTDEV} -s mkpart primary 513MiB 100%

    progress "Setting Up ${ROOTDEV}${RDAPPEND}1..."
    mkfs.fat -F 32 -n EFIBOOT ${ROOTDEV}${RDAPPEND}1
  else
    parted ${ROOTDEV} -s mklabel msdos
    parted ${ROOTDEV} -s mkpart primary 1MiB 513MiB
    parted ${ROOTDEV} -s set 1 boot on
    parted ${ROOTDEV} -s mkpart primary 513MiB 100%

    progress "Setting Up ${ROOTDEV}${RDAPPEND}1..."
    mkfs.ext4 -F ${ROOTDEV}${RDAPPEND}1 -L boot
  fi

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2..."
  cryptsetup -c aes-xts-plain64 -s 512 luksFormat ${ROOTDEV}${RDAPPEND}2 -d /tmp/DISKPW --batch-mode
  cryptsetup luksOpen ${ROOTDEV}${RDAPPEND}2 cryptlvm -d /tmp/DISKPW

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm)..."
  pvcreate /dev/mapper/cryptlvm
  vgcreate lvm /dev/mapper/cryptlvm
  lvcreate -L ${ROOTFS_SIZE} lvm -n system
  lvcreate -L ${SWAP_SIZE} lvm -n swap
  lvcreate -l 100%FREE lvm -n home

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-system)..."
  mkfs.ext4 /dev/mapper/lvm-system -L system
  
  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-swap)..."
  mkswap /dev/mapper/lvm-swap -L system

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-home)..."
  mkfs.ext4 /dev/mapper/lvm-home -L home
else
  progress "Setting Up ${ROOTDEV}${RDAPPEND}1..."
  if [ "$UEFI" = "y" ]; then
    mkfs.fat 32 -n EFIBOOT ${ROOTDEV}${RDAPPEND}1
  else
    mkfs.ext4 ${ROOTDEV}${RDAPPEND}1 -L boot
  fi

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-system)..."
  mkfs.ext4 /dev/mapper/lvm-system -L system
  
  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-swap)..."
  mkswap /dev/mapper/lvm-swap -L system
fi

progress "Mount Partitions..."
mount /dev/mapper/lvm-system /mnt

mkdir /mnt/boot
mount ${ROOTDEV}${RDAPPEND}1 /mnt/boot

if [ -z "$DISKPW" ]; then
  cp /tmp/DISKPW /mnt/boot/.key
  DUMMY_KEY="cryptkey=${ROOTDEV}${RDAPPEND}1:ext4:/.key"
fi

mkdir /mnt/home
mount /dev/mapper/lvm-home /mnt/home

progress "Install Base System..."
sed -i "s/#Color/Color/" /etc/pacman.conf
while ! pacstrap /mnt base linux-lts linux-firmware wget; do
  echo "Failed: exiting"
  exit 1
done

progress "Configure Base System..."
genfstab -p /mnt > /mnt/etc/fstab

cat > /mnt/etc/locale.gen << EOF
bg_BG.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF

cat > /mnt/etc/locale.conf << EOF
LANG="en_US.UTF-8"
LC_MESSAGES="en_US.UTF-8"
LC_MONETARY="bg_BG.UTF-8"
LC_PAPER="bg_BG.UTF-8"
LC_MEASUREMENT="bg_BG.UTF-8"
LC_ADDRESS="bg_BG.UTF-8"
LC_TIME="bg_BG.UTF-8"
EOF

cat > /mnt/etc/vconsole.conf << EOF
KEYMAP="$KEYMAP"
FONT=ter-132n
FONT_MAP=
EOF

ln -sf /usr/share/zoneinfo/Europe/Sofia /mnt/etc/localtime
echo $HOSTNAME > /mnt/etc/hostname

sed -i "s/#Color/Color/" /mnt/etc/pacman.conf
sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /mnt/etc/pacman.conf

if [ "$INTEL" = "y" ]; then
  echo "options i915 enable_guc=3" >> /mnt/etc/modprobe.d/i915.conf
  echo "options i915 enable_fbc=1" >> /mnt/etc/modprobe.d/i915.conf
  echo "options i915 fastboot=1" >> /mnt/etc/modprobe.d/i915.conf
  sed -i "s/MODULES=\"\"/MODULES=\"i915\"/" /mnt/etc/mkinitcpio.conf
fi

if [ "$NO_HIDPI" = "y" ]; then
  echo "GDK_SCALE=1" >> /mnt/etc/environment
  echo "GDK_DPI_SCALE=1" >> /mnt/etc/environment
  echo "QT_SCALE_FACTOR=1" >> /mnt/etc/environment
  echo "QT_AUTO_SCREEN_SCALE_FACTOR=0" >> /mnt/etc/environment
fi

if [ "$SURFACE_TWEAKS" = "y" ]; then
  echo $detach > /mnt/usr/local/bin/detach.sh
  chmod +x /mnt/usr/local/bin/detach.sh
  echo $systemd_sleep > /mnt/lib/systemd/system-sleep/sleep
  chmod +x /mnt/lib/systemd/system-sleep/sleep
fi

# use default encrypt hook
sed -i "s/block filesystems/block keymap encrypt lvm2 filesystems/" /mnt/etc/mkinitcpio.conf

# ln -s /dev/null /mnt/etc/udev/rules.d/80-net-setup-link.rules

arch-chroot /mnt /bin/bash -c "locale-gen"

progress "Add linux-surface repository..."

arch-chroot /mnt /bin/bash -c "wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | pacman-key --add -"
arch-chroot /mnt /bin/bash -c "pacman-key --finger 56C464BAAC421453"
arch-chroot /mnt /bin/bash -c "pacman-key --lsign-key 56C464BAAC421453"

cat >> /mnt/etc/pacman.conf << EOF
[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
EOF

progress "Update Package List..."
arch-chroot /mnt /bin/bash -c "while ! pacman -Sy; do echo repeat...; done"

echo "Validating packages..."
ID=0
MAX=$(echo $PACKAGES | wc -w)
for package in $PACKAGES; do
  ID=$(expr $ID + 1)
  PERC=$(expr $ID \* 100 / $MAX)

  if arch-chroot /mnt /bin/bash -c "pacman -Sp $package" &> /dev/null; then
    echo "$ID / $MAX: OK"
    export PACKAGES_VALID="$PACKAGES_VALID $package"
  else
    echo "$ID / $MAX: FAIL"
    export PACKAGES_INVALID="$PACKAGES_INVALID $package"
  fi
done

if ! [ -z "$PACKAGES_INVALID" ]; then
  read -p "The following packages can not be installed:\n $PACKAGES_INVALID\n Continue (y/n)?" cont
  if [ "$cont" != "y" ]; then exit 1; fi
fi

echo "Installing packages..."
ID=0
MAX=$(echo $PACKAGES_VALID | wc -w)
for package in $PACKAGES_VALID; do
  ID=$(expr $ID + 1)
  PERC=$(expr $ID \* 100 / $MAX)
  echo "$PERC"
  arch-chroot /mnt /bin/bash -c "while ! pacman -S --noconfirm --needed $package; do echo repeat...; done"
done

progress "Install Pamac..."
git clone https://aur.archlinux.org/pamac-aur.git /mnt/tmp/build_pamac
arch-chroot /mnt /bin/bash -c "makepkg -sic BUILDDIR='/tmp/build_pamac'"
rm -r /mnt/tmp/build_pamac

progress "Configure Desktop..."

case $DESKTOP in
"KDE")
  cat > /mnt/etc/sddm.conf << EOF
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=
RebootCommand=

[Theme]
Current=breeze
CursorTheme=breeze_cursors

[Users]
MaximumUid=65000
MinimumUid=1000
EOF
  ;;
"DEEPIN")
  sed -i "s/#greeter-session=.*/greeter-session=lightdm-deepin-greeter/" /mnt/etc/lightdm/lightdm.conf
  ;;
*)
  echo "QT_QPA_PLATFORMTHEME=gtk2" >> /mnt/etc/environment
  echo "QT_STYLE_OVERRIDE=gtk" >> /mnt/etc/environment
  ;;
esac

if [ "$DESKTOP" = "GNOME" ]; then
  ln -s /home/$USERNAME/.config/monitors.xml /mnt/var/lib/gdm/.config/
fi

if echo "$PACKAGES" | grep -q " wine "; then
  # disable wine filetype associations
  sed "s/-a //g" -i /mnt/usr/share/wine/wine.inf
fi

progress "Install Bootloader..."
arch-chroot /mnt /bin/bash -c "mkinitcpio -p linux-surface"
arch-chroot /mnt /bin/bash -c "mkinitcpio -p linux-lts"

if [ "$UEFI" = "y" ]; then
  arch-chroot /mnt /bin/bash -c "bootctl --path=/boot install"
  
  echo "title   Arch Linux - Surface Kernel" > /mnt/boot/loader/entries/arch-surface.conf
  echo "linux   /vmlinuz-linux-surface" >> /mnt/boot/loader/entries/arch-surface.conf
  echo "initrd  /intel-ucode.img" >> /mnt/boot/loader/entries/arch-surface.conf
  echo "initrd  /initramfs-linux-surface.img" >> /mnt/boot/loader/entries/arch-surface.conf
  echo "options root=/dev/mapper/lvm-system $RESUME rw cryptdevice=${ROOTDEV}${RDAPPEND}2:cryptlvm $DUMMY_KEY quiet" >> /mnt/boot/loader/entries/arch-surface.conf
  
  echo "title   Arch Linux - LTS Kernel" > /mnt/boot/loader/entries/arch-lts.conf
  echo "linux   /vmlinuz-linux-lts" >> /mnt/boot/loader/entries/arch-lts.conf
  echo "initrd  /intel-ucode.img" >> /mnt/boot/loader/entries/arch-lts.conf
  echo "initrd  /initramfs-linux-lts.img" >> /mnt/boot/loader/entries/arch-lts.conf
  echo "options root=/dev/mapper/lvm-system $RESUME rw cryptdevice=${ROOTDEV}${RDAPPEND}2:cryptlvm $DUMMY_KEY quiet" >> /mnt/boot/loader/entries/arch-lts.conf
else
  sed -i "s|GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"cryptdevice=${ROOTDEV}${RDAPPEND}2:cryptlvm $DUMMY_KEY ${CUSTOM_CMDLINE}\"|" /mnt/etc/default/grub
  sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/" /mnt/etc/default/grub
  sed -i "s/GRUB_GFXMODE=auto/GRUB_GFXMODE=1920x1080,auto/" /mnt/etc/default/grub
  arch-chroot /mnt /bin/bash -c "grub-install --target=i386-pc ${ROOTDEV}"
  arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
fi

progress "Create root password..."
arch-chroot /mnt /bin/bash -c "passwd"

progress "Create User..."
echo "${USERNAME} ALL=(ALL) ALL" >> /mnt/etc/sudoers
if [ "$SURFACE_TWEAKS" = "y" ]; then
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/detach.sh"
fi

arch-chroot /mnt /bin/bash -c "useradd -m ${USERNAME}"
for group in $UGROUPS; do
  arch-chroot /mnt /bin/bash -c "gpasswd -a ${USERNAME} ${group}"
done

arch-chroot /mnt /bin/bash -c "echo \"${USERNAME}:${USERPW}\" | chpasswd"
arch-chroot /mnt /bin/bash -c "echo \"root:${USERPW}\" | chpasswd"

ln -s /home/${USERNAME}/.bashrc /mnt/root/.bashrc
ln -s /home/${USERNAME}/.zshrc /mnt/root/.zshrc

if [ "$DESKTOP" = "HTPC" ]; then
  # setting up HTPC user
  arch-chroot /mnt /bin/bash -c "useradd -m kodi"
  for group in $UGROUPS; do
    arch-chroot /mnt /bin/bash -c "gpasswd -a kodi ${group}"
  done
  arch-chroot /mnt /bin/bash -c "echo \"kodi:${USERPW}\" | chpasswd"

  # enable auto-login after 3 seconds
  cat > /mnt/etc/gdm/custom.conf << "EOF"
[daemon]
# WaylandEnable=false
TimedLoginEnable=true
TimedLogin=kodi
TimedLoginDelay=3

[security]

[xdmcp]

[chooser]

[debug]
EOF

  # set default session to kodi
  cat > /mnt/var/lib/AccountsService/users/kodi << "EOF"
[User]
Language=
XSession=kodi
EOF

  # allow passwordless login for kodi
  echo 'auth sufficient pam_succeed_if.so user ingroup nopasswdlogin' >> /mnt/etc/pam.d/gdm-password
  arch-chroot /mnt /bin/bash -c "groupadd nopasswdlogin"
  arch-chroot /mnt /bin/bash -c "gpasswd -a kodi nopasswdlogin"
fi

progress "Configure Services..."
for service in $SYSTEMD; do
  arch-chroot /mnt /bin/bash -c "systemctl enable ${service}"
done

sync

reboot
