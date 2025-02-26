#!/bin/bash

# Arch Linux Installation Script for VM on Unraid
# Features:
# - ext4 filesystem
# - KDE Plasma desktop
# - Additional tools: git, vscode, brave browser, zsh, oh-my-zsh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_section() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_step() {
    echo -e "${YELLOW}-->${NC} $1"
}

error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

prompt() {
    read -p "$1 [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Check if booted in UEFI mode
if [ -d /sys/firmware/efi/efivars ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

print_section "Starting Arch Linux installation in $BOOT_MODE mode"

# Verify internet connection
if ! ping -c 1 archlinux.org >/dev/null 2>&1; then
    error "No internet connection. Please connect and try again."
fi

# Set time and date
print_step "Setting up system clock"
timedatectl set-ntp true

# Disk setup
print_section "Disk Setup"
echo "Available disks:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS

# Select disk
read -p "Enter the disk to install Arch Linux on (e.g., sda, vda): " DISK
DISK_PATH="/dev/$DISK"

if [ ! -b "$DISK_PATH" ]; then
    error "Disk $DISK_PATH does not exist"
fi

print_step "Selected disk: $DISK_PATH"
prompt "WARNING: All data on $DISK_PATH will be erased. Continue?" || exit 1

# Partition the disk based on boot mode
print_step "Partitioning disk"
if [ "$BOOT_MODE" = "UEFI" ]; then
    # UEFI partitioning
    parted -s "$DISK_PATH" mklabel gpt
    parted -s "$DISK_PATH" mkpart "EFI" fat32 1MiB 513MiB
    parted -s "$DISK_PATH" set 1 esp on
    parted -s "$DISK_PATH" mkpart "root" ext4 513MiB 100%
    
    EFI_PARTITION="${DISK_PATH}1"
    ROOT_PARTITION="${DISK_PATH}2"
    
    print_step "Formatting EFI partition"
    mkfs.fat -F32 "$EFI_PARTITION"
else
    # BIOS partitioning
    parted -s "$DISK_PATH" mklabel msdos
    parted -s "$DISK_PATH" mkpart primary ext4 1MiB 100%
    parted -s "$DISK_PATH" set 1 boot on
    
    ROOT_PARTITION="${DISK_PATH}1"
fi

print_step "Formatting root partition with ext4"
mkfs.ext4 "$ROOT_PARTITION"

# Mount partitions
print_step "Mounting partitions"
mount "$ROOT_PARTITION" /mnt

if [ "$BOOT_MODE" = "UEFI" ]; then
    mkdir -p /mnt/boot/efi
    mount "$EFI_PARTITION" /mnt/boot/efi
fi

# Install essential packages
print_section "Installing base system"
pacstrap /mnt base base-devel linux linux-firmware

# Generate fstab
print_step "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot operations
print_section "Configuring system"
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
print_step "Setting timezone"
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Set locale
print_step "Setting locale"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
print_step "Setting hostname"
echo "archvm" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 archvm.localdomain archvm" >> /etc/hosts

# Set root password
print_step "Setting root password"
echo "root:password" | chpasswd

# Install and configure bootloader
print_step "Installing bootloader"
pacman -S --noconfirm grub

if [ "$BOOT_MODE" = "UEFI" ]; then
    pacman -S --noconfirm efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK_PATH"
fi

grub-mkconfig -o /boot/grub/grub.cfg

# Install necessary packages
print_step "Installing necessary packages"
pacman -S --noconfirm networkmanager sudo vim git

# Enable NetworkManager
systemctl enable NetworkManager

# Create a user
print_step "Creating user"
useradd -m -G wheel -s /bin/bash archuser
echo "archuser:password" | chpasswd

# Give sudo privileges
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# Install KDE Plasma
print_step "Installing KDE Plasma desktop environment"
pacman -S --noconfirm xorg plasma plasma-wayland-session kde-applications sddm

# Enable SDDM
systemctl enable sddm

# Install requested additional software
print_step "Installing additional requested software"

# Install zsh
pacman -S --noconfirm zsh

# Install git (already installed above, but ensure it's here)
pacman -S --noconfirm git

# Install VS Code
pacman -S --noconfirm code

# Install yay (AUR helper for Brave browser)
print_step "Installing yay (AUR helper)"
sudo -u archuser bash -c "
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"

# Install Brave browser from AUR
print_step "Installing Brave browser from AUR"
sudo -u archuser bash -c "
yay -S --noconfirm brave-bin
"

# Install Oh My Zsh
print_step "Installing Oh My Zsh"
sudo -u archuser bash -c "
sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended
chsh -s \$(which zsh)
"

EOF

print_section "Installation completed successfully!"
print_step "You can now reboot into your new Arch Linux system"
print_step "Login credentials:"
print_step "Username: archuser"
print_step "Password: password"
print_step "IMPORTANT: Please change these default passwords after logging in"

# Ask for reboot
if prompt "Would you like to reboot now?"; then
    print_step "Rebooting..."
    reboot
else
    print_step "You can reboot manually when ready"
fi
