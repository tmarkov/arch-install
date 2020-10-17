#!/bin/bash

function progress() {
  dialog --infobox "$1" 3 42
}

SYSTEMD="iptsd"
SYSTEMD_DESKTOP="NetworkManager bluetooth avahi-daemon"
UGROUPS="audio video storage optical network users wheel games rfkill scanner power lp"
PACKAGES="base-devel linux- cmake dosfstools gptfdisk intel-ucode neovim openssh git wget htop ncdu screen net-tools unrar unzip p7zip rfkill bind-tools alsa-utils"
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
PACKAGE_EXT_APPS="mpv atom firefox vlc gimp libreoffice lib32-libpulse pulseaudio-zeroconf picard audacity onboard redshift xournalpp"
PACKAGE_EXT_APPS_GAMING="steam"
PACKAGE_EXT_APPS_GTK="gtk-recordmydesktop openshot gcolor2 meld gparted evince"
PACKAGE_EXT_APPS_QT="qbittorrent"

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

echo 'screen_color = (CYAN,BLACK,ON)' > ~/.dialogrc

# clean previous install attempts
umount -R /mnt &> /dev/null || true
if [ -b /dev/mapper/lvm-system ]; then
  vgchange -an lvm && sleep 2
fi

if [ -b /dev/mapper/cryptlvm ]; then
  cryptsetup luksClose /dev/mapper/cryptlvm
fi

# KEYMAP
while [ -z $KEYMAP ]; do
  KEYMAP=$(dialog --menu "Select your keyboard layout:" 0 0 0\
    de German\
    fr French\
    us English\
    "" Custom 3>&1 1>&2 2>&3)
  if test $? -eq 1; then exit 1; fi

  if [ -z "$KEYMAP" ]; then
    KEYMAP=$(dialog --clear --title "Keymap" --inputbox "Please enter your keymap" 0 0 "" 3>&1 1>&2 2>&3)
  fi
done

loadkeys $KEYMAP

# WIFI
if iwconfig | grep IEEE &> /dev/null; then
  if dialog --clear --title "WiFi" --yesno "Connect to WiFi?" 0 0 3>&1 1>&2 2>&3; then
    wifi-menu
  fi
fi

# MIRROR
if dialog --clear --title "Mirror" --yesno "Select a mirror?" 0 0 3>&1 1>&2 2>&3; then
  vim /etc/pacman.d/mirrorlist
fi

# ROOTDEV
ROOTDEV=$(dialog --clear --title "Harddisk" --radiolist "Please select the target device" 0 0 0 \
$(ls /dev/sd? /dev/vd? /dev/mmcblk? /dev/nvme?n? -1 2> /dev/null | while read line; do
echo "$line" "$line" on; done) 3>&1 1>&2 2>&3)
if test $? -eq 1; then exit 1; fi
if grep -q "mmcblk" <<< $ROOTDEV || grep -q "nvme" <<< $ROOTDEV; then
  RDAPPEND=p
fi

# UEFI
if dialog --clear --title "UEFI" --yesno "Use UEFI Boot?" 0 0 3>&1 1>&2 2>&3; then
  UEFI=y
  PACKAGES="$PACKAGES efibootmgr"
else
  UEFI=n
  PACKAGES="$PACKAGES grub"
fi

DISKPW="..."
while ! [ "$DISKPW" = "$DISKPW2" ]; do
  DISKPW=$(dialog --clear --title "Disk Encryption" --insecure --passwordbox "Enter your disk encryption password" 0 0 3>&1 1>&2 2>&3)
  if test $? -eq 1; then exit 1; fi
  DISKPW2=$(dialog --clear --title "Disk Encryption" --insecure --passwordbox "Repeat your disk encryption password" 0 0 3>&1 1>&2 2>&3)
  if test $? -eq 1; then exit 1; fi

  echo -n "$DISKPW" > /tmp/DISKPW
done

# try to unlock previous installation
progress "Trying to unlock disks..."
cryptsetup luksOpen ${ROOTDEV}${RDAPPEND}2 cryptlvm -d /tmp/DISKPW &> /dev/tty2
vgchange -ay &> /dev/tty2
sleep 2

if ! [ -b /dev/mapper/lvm-system ]; then
  WIPE=y
else
  WIPE=n
fi

if [ "$WIPE" = "n" ]; then
  if ! dialog --clear --title "Reuse" --yesno "Do you want to reuse the existing installation?" 0 0 3>&1 1>&2 2>&3; then
    WIPE=y
  fi
fi

if [ "$WIPE" = "y" ]; then
  # close active installation
  progress "Reload disks..."
  vchange -an lvm &> /dev/tty2
  cryptsetup luksClose cryptlvm &> /dev/tty2

  ROOTFS_SIZE=$(dialog --clear --title "Rootfs Size" --inputbox "Please enter the desired size of the root partition" 0 0 "25G" 3>&1 1>&2 2>&3)
  SWAP_SIZE=$(dialog --clear --title "Swap Size" --inputbox "Please enter the desired size of the swap partition" 0 0 "8.8G" 3>&1 1>&2 2>&3)
  if test $? -eq 1; then exit 1; fi
fi

DESKTOP=$(dialog --clear --title "Desktop Selection" --radiolist "Please select your Desktop" 0 0 0 \
  1 "GNOME Desktop" on\
  2 "KDE Plasma Desktop" off\
  3 "MATE Desktop" off\
  4 "Cinnamon Desktop" off\
  5 "Xfce Desktop" off\
  6 "Deepin Desktop Environment" off\
  7 "HTPC (Kodi & GNOME)" off\
  8 "No Desktop" off\
  9 "Headless (Remote)" off 3>&1 1>&2 2>&3)
if test $? -eq 1; then exit 1; fi

case $DESKTOP in
  "1")
    DESKTOP="GNOME"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_GNOME $PACKAGE_DESKTOP_GNOME_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_GNOME_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_GNOME_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="off"
  ;;
  "2")
    DESKTOP="KDE"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_QT $PACKAGE_DESKTOP_KDE $PACKAGE_DESKTOP_KDE_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_KDE_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_KDE_DM"
    EXT_APPS_GTK="off"
    EXT_APPS_QT="on"
  ;;
  "3")
    DESKTOP="MATE"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_MATE $PACKAGE_DESKTOP_MATE_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_MATE_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_MATE_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="off"
  ;;
  "4")
    DESKTOP="CINNAMON"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_CINNAMON $PACKAGE_DESKTOP_CINNAMON_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_CINNAMON_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_CINNAMON_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="off"
  ;;
  "5")
    DESKTOP="XFCE"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_XFCE $PACKAGE_DESKTOP_XFCE_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_XFCE_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_XFCE_DM"
    EXT_APPS_GTK="on"
    EXT_APPS_QT="off"
  ;;
  "6")
    DESKTOP="DEEPIN"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_QT $PACKAGE_DESKTOP_DEEPIN $PACKAGE_DESKTOP_DEEPIN_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_DEEPIN_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_DEEPIN_DM"
    EXT_APPS_GTK="off"
    EXT_APPS_QT="on"
  ;;
  "7")
    DESKTOP="HTPC"
    PACKAGES="$PACKAGES $PACKAGE_DESKTOP $PACKAGE_DESKTOP_GTK $PACKAGE_DESKTOP_HTPC $PACKAGE_DESKTOP_HTPC_DM"
    SYSTEMD="$SYSTEMD $SYSTEMD_DESKTOP $PACKAGE_DESKTOP_HTPC_DM"
    UGROUPS="$UGROUPS $PACKAGE_DESKTOP_HTPC_DM"
    EXT_APPS_GTK="off"
    EXT_APPS_QT="off"
  ;;
  "8")
    DESKTOP="MINIMAL"
    EXT_APPS_GTK="off"
    EXT_APPS_QT="off"
  ;;
  "9")
    DESKTOP="HEADLESS"
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

EXT_PACKAGES=$(dialog --clear --title "Additional Software" --checklist "Select Additional Software" 0 0 0 \
  EXT_FONTS "Fonts" $WANT_FONTS\
  EXT_CODECS "Codecs" $WANT_CODECS\
  EXT_CONSOLE "Console Applications" on\
  EXT_APPS "Desktop Applications" $HAS_DESKTOP\
  EXT_APPS_GAMING "Desktop Gaming Applications" $HAS_DESKTOP\
  EXT_APPS_GTK "Desktop GTK Applications" $EXT_APPS_GTK\
  EXT_APPS_QT "Desktop Qt Applications" $EXT_APPS_QT 3>&1 1>&2 2>&3)
if test $? -eq 1; then exit 1; fi

for item in $EXT_PACKAGES; do
  if [ "$item" = "EXT_FONTS" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_FONTS"
  elif [ "$item" = "EXT_CODECS" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_CODECS"
  elif [ "$item" = "EXT_CONSOLE" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_CONSOLE"
  elif [ "$item" = "EXT_APPS" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS"
    UGROUPS="$UGROUPS vboxusers"
  elif [ "$item" = "EXT_APPS_GAMING" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS_GAMING"
  elif [ "$item" = "EXT_APPS_GTK" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS_GTK"
  elif [ "$item" = "EXT_APPS_QT" ]; then
    PACKAGES="$PACKAGES $PACKAGE_EXT_APPS_QT"
  fi
done

if lspci | grep -i "3d\|video\|vga" | grep -iq intel; then
  HAS_INTEL=on
else
  HAS_INTEL=off
fi

if lspci | grep -i "3d\|video\|vga" | grep -iq nvidia; then
  HAS_NVIDIA=on
else
  HAS_NVIDIA=off
fi

if [ "$HAS_INTEL" = "on" ] && [ "$HAS_NVIDIA" = "on" ]; then
  HAS_OPTIMUS=on
else
  HAS_OPTIMUS=off
fi

if [ "$(cat /sys/class/graphics/fb0/virtual_size)" = "3000,2000" ]; then
  MATEBOOK=on
else
  MATEBOOK=off
fi

TWEAKS=$(dialog --clear --title "Tweaks" --checklist "Select Custom Tweaks" 0 0 0 \
  SURFACE "Install surface kernel" on\
  NO_HIDPI "Disable HiDPI Scaling" off\
  OPTIMUS "NVIDIA Hybrid Graphics" $HAS_OPTIMUS\
  INTEL "Latest Intel Graphic Tweaks" $HAS_INTEL\
  FIX_GPD "Hardware: GPD Win" off\
  HIBERNATE "Enable Hibernation" on 3>&1 1>&2 2>&3)
if test $? -eq 1; then exit 1; fi

for item in $TWEAKS; do
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

HOSTNAME=$(dialog --clear --title "Hostname" --inputbox "Please enter your hostname" 0 0 "" 3>&1 1>&2 2>&3)
if test $? -eq 1; then exit 1; fi

USERNAME=$(dialog --clear --title "Username" --inputbox "Please enter your username" 0 0 "" 3>&1 1>&2 2>&3)
if test $? -eq 1; then exit 1; fi

while ! [ "$USERPW" = "$USERPW2" ] || [ -z "$USERPW" ]; do
  USERPW=$(dialog --clear --title "User Password" --insecure --passwordbox "Enter your user password" 0 0 3>&1 1>&2 2>&3)
  if test $? -eq 1; then exit 1; fi
  USERPW2=$(dialog --clear --title "User Password" --insecure --passwordbox "Repeat your user password" 0 0 3>&1 1>&2 2>&3)
  if test $? -eq 1; then exit 1; fi
done

if [ "$WIPE" = "y" ]; then
  cryptsize=$(parted <<<'unit MB print all' | grep ${ROOTDEV} | cut -d " " -f 3)
  echo "\Z1WARNING: All data on '$ROOTDEV' will be deleted!\Zn" > /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "${ROOTDEV}" >> /tmp/install-summary.log
  echo "\Zb - ${ROOTDEV}${RDAPPEND}1 - Boot (512M)\Zn" >> /tmp/install-summary.log
  echo "\Zb - ${ROOTDEV}${RDAPPEND}2 - Encrypted LVM\Zn" >> /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "Encrypted LVM" >> /tmp/install-summary.log
  echo "\Zb - lvm-system ($ROOTFS_SIZE)\Zn" >> /tmp/install-summary.log
  echo "\Zb - lvm-swap ($SWAP_SIZE)\Zn" >> /tmp/install-summary.log
  echo "\Zb - lvm-home\Zn" >> /tmp/install-summary.log
else
  echo "\Z1WARNING: '/boot' ($ROOTDEV${RDAPPEND}1) and 'lvm-system' will be deleted!\Zn" > /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "${ROOTDEV}" >> /tmp/install-summary.log
  echo "\Zb - ${ROOTDEV}${RDAPPEND}1 - Boot (format)\Zn" >> /tmp/install-summary.log
  echo "\Zb - ${ROOTDEV}${RDAPPEND}2 - Encrypted LVM (keep)\Zn" >> /tmp/install-summary.log
  echo "" >> /tmp/install-summary.log
  echo "Encrypted LVM" >> /tmp/install-summary.log
  echo "\Zb - lvm-system (format)\Zn" >> /tmp/install-summary.log
  echo "\Zb - lvm-swap ($SWAP_SIZE)\Zn" >> /tmp/install-summary.log
  echo "\Zb - lvm-home (keep)\Zn" >> /tmp/install-summary.log
fi

echo "" >> /tmp/install-summary.log
echo "Profile: \Zb$DESKTOP\Zn" >> /tmp/install-summary.log
echo "" >> /tmp/install-summary.log
echo "User: \Zb$USERNAME\Zn" >> /tmp/install-summary.log
echo "Keymap: \Zb$KEYMAP\Zn" >> /tmp/install-summary.log
echo "Hostname: \Zb$HOSTNAME\Zn" >> /tmp/install-summary.log
echo "" >> /tmp/install-summary.log
echo "Packages: \Zb$PACKAGES\Zn" >> /tmp/install-summary.log
echo "" >> /tmp/install-summary.log
echo "Do you want to continue?" >> /tmp/install-summary.log

if ! dialog --clear --title "Summary" --colors --yesno "$(cat /tmp/install-summary.log)" 0 0 3>&1 1>&2 2>&3; then
  exit 1
fi

progress "Setting Up ${ROOTDEV}..."
if [ "$WIPE" = "y" ]; then
  dd if=/dev/zero of=${ROOTDEV} bs=4M conv=fsync count=1 &> /dev/tty2

  if [ "$UEFI" = "y" ]; then
    parted ${ROOTDEV} -s mklabel gpt &> /dev/tty2
    parted ${ROOTDEV} -s mkpart ESP fat32 1MiB 513MiB &> /dev/tty2
    parted ${ROOTDEV} -s set 1 boot on &> /dev/tty2
    parted ${ROOTDEV} -s mkpart primary 513MiB 100% &> /dev/tty2

    progress "Setting Up ${ROOTDEV}${RDAPPEND}1..."
    mkfs.fat -F 32 -n EFIBOOT ${ROOTDEV}${RDAPPEND}1 &> /dev/tty2
  else
    parted ${ROOTDEV} -s mklabel msdos &> /dev/tty2
    parted ${ROOTDEV} -s mkpart primary 1MiB 513MiB &> /dev/tty2
    parted ${ROOTDEV} -s set 1 boot on &> /dev/tty2
    parted ${ROOTDEV} -s mkpart primary 513MiB 100% &> /dev/tty2

    progress "Setting Up ${ROOTDEV}${RDAPPEND}1..."
    mkfs.ext4 -F ${ROOTDEV}${RDAPPEND}1 -L boot &> /dev/tty2
  fi

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2..."
  cryptsetup -c aes-xts-plain64 -s 512 luksFormat ${ROOTDEV}${RDAPPEND}2 -d /tmp/DISKPW --batch-mode &> /dev/tty2
  cryptsetup luksOpen ${ROOTDEV}${RDAPPEND}2 cryptlvm -d /tmp/DISKPW &> /dev/tty2

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm)..."
  pvcreate /dev/mapper/cryptlvm &> /dev/tty2
  vgcreate lvm /dev/mapper/cryptlvm &> /dev/tty2
  lvcreate -L ${ROOTFS_SIZE} lvm -n system &> /dev/tty2
  lvcreate -L ${SWAP_SIZE} lvm -n swap &> /dev/tty2
  lvcreate -l 100%FREE lvm -n home &> /dev/tty2

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-system)..."
  mkfs.ext4 /dev/mapper/lvm-system -L system &> /dev/tty2
  
  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-swap)..."
  mkswap /dev/mapper/lvm-system -L system &> /dev/tty2

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-home)..."
  mkfs.ext4 /dev/mapper/lvm-home -L home &> /dev/tty2
else
  progress "Setting Up ${ROOTDEV}${RDAPPEND}1..."
  if [ "$UEFI" = "y" ]; then
    mkfs.fat 32 -n EFIBOOT ${ROOTDEV}${RDAPPEND}1 &> /dev/tty2
  else
    mkfs.ext4 ${ROOTDEV}${RDAPPEND}1 -L boot &> /dev/tty2
  fi

  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-system)..."
  mkfs.ext4 /dev/mapper/lvm-system -L system &> /dev/tty2
  
  progress "Setting Up ${ROOTDEV}${RDAPPEND}2 (lvm-swap)..."
  mkswap /dev/mapper/lvm-system -L system &> /dev/tty2
fi

progress "Mount Partitions..."
mount /dev/mapper/lvm-system /mnt &> /dev/tty2

mkdir /mnt/boot &> /dev/tty2
mount ${ROOTDEV}${RDAPPEND}1 /mnt/boot &> /dev/tty2

if [ -z "$DISKPW" ]; then
  cp /tmp/DISKPW /mnt/boot/.key
  DUMMY_KEY="cryptkey=${ROOTDEV}${RDAPPEND}1:ext4:/.key"
fi

mkdir /mnt/home &> /dev/tty2
mount /dev/mapper/lvm-home /mnt/home &> /dev/tty2

progress "Install Base System..."
sed -i "s/#Color/Color/" /etc/pacman.conf &> /dev/tty2
while ! pacstrap /mnt base &> /dev/tty2; do
  echo "Failed: repeating" &> /dev/tty2
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

ln -sf /usr/share/zoneinfo/Europe/Sofia /mnt/etc/localtime &> /dev/tty2
echo $HOSTNAME > /mnt/etc/hostname

sed -i "s/#Color/Color/" /mnt/etc/pacman.conf &> /dev/tty2
sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /mnt/etc/pacman.conf &> /dev/tty2

if [ "$INTEL" = "y" ]; then
  echo "options i915 enable_guc=3" >> /mnt/etc/modprobe.d/i915.conf
  echo "options i915 enable_fbc=1" >> /mnt/etc/modprobe.d/i915.conf
  echo "options i915 fastboot=1" >> /mnt/etc/modprobe.d/i915.conf
  sed -i "s/MODULES=\"\"/MODULES=\"i915\"/" /mnt/etc/mkinitcpio.conf &> /dev/tty2
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
sed -i "s/block filesystems/block keymap encrypt lvm2 filesystems/" /mnt/etc/mkinitcpio.conf &> /dev/tty2

# ln -s /dev/null /mnt/etc/udev/rules.d/80-net-setup-link.rules &> /dev/tty2

arch-chroot /mnt /bin/bash -c "locale-gen" &> /dev/tty2

progress "Add linux-surface repository..."
arch-chroot /mnt /bin/bash -c "wget -qO - https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | pacman-key --add -" &> /dev/tty2
arch-chroot /mnt /bin/bash -c "pacman-key --finger 56C464BAAC421453" &> /dev/tty2
arch-chroot /mnt /bin/bash -c "pacman-key --lsign-key 56C464BAAC421453" &> /dev/tty2

cat > /mnt/etc/pacman.conf << EOF
[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
EOF

progress "Update Package List..."
arch-chroot /mnt /bin/bash -c "while ! pacman -Sy; do echo repeat...; done" &> /dev/tty2

ID=0
MAX=$(echo $PACKAGES | wc -w)
for package in $PACKAGES; do
  ID=$(expr $ID + 1)
  PERC=$(expr $ID \* 100 / $MAX)

  echo $PERC | dialog --gauge "Validate: '$package'" 7 100 0
  if arch-chroot /mnt /bin/bash -c "pacman -Sp $package" &> /dev/null; then
    export PACKAGES_VALID="$PACKAGES_VALID $package"
  else
    export PACKAGES_INVALID="$PACKAGES_INVALID $package"
  fi
done

if ! [ -z "$PACKAGES_INVALID" ]; then
  dialog --yes-label "Continue" --no-label "Abort" --clear --title "Warning" --yesno "The following packages can not be installed:\n $PACKAGES_INVALID\n\nPlease report this issue on the bugtracker: https://gitlab.com/shagu/arch-install/issues" 0 0
  if test $? -eq 1; then exit 1; fi
fi

ID=0
MAX=$(echo $PACKAGES_VALID | wc -w)
for package in $PACKAGES_VALID; do
  ID=$(expr $ID + 1)
  PERC=$(expr $ID \* 100 / $MAX)

  echo $PERC | dialog --gauge "Install Packages: '$package'" 7 100 0
  arch-chroot /mnt /bin/bash -c "while ! pacman -S --noconfirm --needed $package; do echo repeat...; done" | while read line; do
    echo "$line" &> /dev/tty2
    if grep -q "^::" <<< $line; then
      echo $PERC | dialog --gauge "Install Packages: '$package'\n$(sed 's/^:: //g' <<< $line)" 7 100 0
    fi
  done
done

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
  sed -i "s/#greeter-session=.*/greeter-session=lightdm-deepin-greeter/" /mnt/etc/lightdm/lightdm.conf &> /dev/tty2
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
  sed "s/-a //g" -i /mnt/usr/share/wine/wine.inf &> /dev/tty2
fi

progress "Install Bootloader..."
arch-chroot /mnt /bin/bash -c "mkinitcpio -p linux" &> /dev/tty2

if [ "$UEFI" = "y" ]; then
  arch-chroot /mnt /bin/bash -c "bootctl --path=/boot install" &> /dev/tty2
  echo "title   Arch Linux" > /mnt/boot/loader/entries/arch.conf
  echo "linux   /vmlinuz-linux" >> /mnt/boot/loader/entries/arch.conf
  echo "initrd  /intel-ucode.img" >> /mnt/boot/loader/entries/arch.conf
  echo "initrd  /initramfs-linux.img" >> /mnt/boot/loader/entries/arch.conf
  echo "options root=/dev/mapper/lvm-system $RESUME rw cryptdevice=${ROOTDEV}${RDAPPEND}2:cryptlvm $DUMMY_KEY quiet" >> /mnt/boot/loader/entries/arch.conf
else
  sed -i "s|GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"cryptdevice=${ROOTDEV}${RDAPPEND}2:cryptlvm $DUMMY_KEY ${CUSTOM_CMDLINE}\"|" /mnt/etc/default/grub &> /dev/tty2
  sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=3/" /mnt/etc/default/grub &> /dev/tty2
  sed -i "s/GRUB_GFXMODE=auto/GRUB_GFXMODE=1920x1080,auto/" /mnt/etc/default/grub &> /dev/tty2
  arch-chroot /mnt /bin/bash -c "grub-install --target=i386-pc ${ROOTDEV}" &> /dev/tty2
  arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg" &> /dev/tty2
fi

progress "Create User..."
echo "${USERNAME} ALL=(ALL) ALL" >> /mnt/etc/sudoers
if [ "$SURFACE_TWEAKS" = "y" ]; then
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/detach.sh"
fi

arch-chroot /mnt /bin/bash -c "useradd -m ${USERNAME}" &> /dev/tty2
for group in $UGROUPS; do
  arch-chroot /mnt /bin/bash -c "gpasswd -a ${USERNAME} ${group}" &> /dev/tty2
done

arch-chroot /mnt /bin/bash -c "echo \"${USERNAME}:${USERPW}\" | chpasswd" &> /dev/tty2
arch-chroot /mnt /bin/bash -c "echo \"root:${USERPW}\" | chpasswd" &> /dev/tty2

ln -s /home/${USERNAME}/.bashrc /mnt/root/.bashrc &> /dev/tty2
ln -s /home/${USERNAME}/.zshrc /mnt/root/.zshrc &> /dev/tty2

if [ "$DESKTOP" = "HTPC" ]; then
  # setting up HTPC user
  arch-chroot /mnt /bin/bash -c "useradd -m kodi" &> /dev/tty2
  for group in $UGROUPS; do
    arch-chroot /mnt /bin/bash -c "gpasswd -a kodi ${group}" &> /dev/tty2
  done
  arch-chroot /mnt /bin/bash -c "echo \"kodi:${USERPW}\" | chpasswd" &> /dev/tty2

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
  arch-chroot /mnt /bin/bash -c "groupadd nopasswdlogin" &> /dev/tty2
  arch-chroot /mnt /bin/bash -c "gpasswd -a kodi nopasswdlogin" &> /dev/tty2
fi

progress "Configure Services..."
for service in $SYSTEMD; do
  arch-chroot /mnt /bin/bash -c "systemctl enable ${service}" &> /dev/tty2
done

sync

dialog --title "Installtion" --msgbox "Installation completed. Press Enter to reboot into the new system." 0 0
reboot
