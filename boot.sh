#!/bin/bash -e

# This script installs BusyBox with systemd, sets up a kernel binary,
# performs image manipulations, and boots it using `qemu-system-i386`.

# Enable ZSH debug utilities
# set -o xtrace

workdir="$(pwd)"
busybox_version="1.36.1"

source "./variables.sh"
source "./core.sh"
source "./archlinux.sh"

busybox() {
  printf "%s\n" "Installing BusyBox..."

  tl_set_variables

  local dest_dir
  dest_dir="$1"

  # If second argument is not given exit with an error
  if [ -z "$dest_dir" ]; then
    tl_log 'Error: First argument is required\n'
    exit 1
  fi

  # Step 2: Download and compile BusyBox
  busybox_extracted_folder_name="busybox-${busybox_version}"
  busybox_compressed_file_name="${busybox_extracted_folder_name}.tar.bz2"

  wget_args=(
    https://busybox.net/downloads/"$busybox_compressed_file_name"
    # Set output dir to "$srcdir_busybox"
    -P "$srcdir_busybox"
  )

  tl_download "${wget_args[@]}" || exit 1

  tar_args=(
    xjf
    # Do not update files that already exists
    "${srcdir_busybox}"/"${busybox_compressed_file_name}"
  )

  # Enter `src/busybox` directory
  cd "$srcdir_busybox" || exit 1

  # Extract the folder
  tar "${tar_args[@]}" || exit 1

  cd "$srcdir_busybox/$busybox_extracted_folder_name" || exit 1

  # Create `.config` file
  make defconfig

  # Apply patches to `.config` file since the default config is set
  patch '.config' -p1 <"${workdir}/0001-disable-tc.patch"

  make -j"$(nproc)"

  make DESTDIR="$dest_dir" install # CONFIG_PREFIX="$rootfs_dir"

  printf "%s\n" "BusyBox installed successfully."
}

tl_qemu_disconnect() {
  tl_set_variables

  # Unmount in case it's already mounted
  if mountpoint -q "$mount_point"; then
    sudo umount "$mount_point" || exit 1
  fi

  tl_log 'Disconnecting %s from %s\n' "$disk_file_name" "$mount_device"

  # Disconnect mount device, just in case it's already mounted
  sudo qemu-nbd --disconnect "$mount_device"
}

tl_qemu_connect() {
  tl_set_variables

  # Load nbd module
  sudo modprobe nbd

  tl_qemu_disconnect

  tl_log 'Connecting %s to %s\n' "$disk_file_name" "$mount_device"

  # Connect the disk to a device
  sudo qemu-nbd --connect "$mount_device" "$disk_file_name"

  sudo lsblk | sort
  #   sudo lsblk --output-all --nodeps --pairs --paths | sort
}

tl_mount_disk() {
  tl_log 'Mounting disk...'

  tl_set_variables

  tl_qemu_connect

  # Mount HDD contents
  sudo mount "$mount_device" "$mount_point" || exit 1

  # Transfer the ownership to the current user
  sudo chown -v "$USER":"$USER" "$mount_point"

  tl_log 'Disk mounted successfully: %s\n' "$mount_point"
}

tl_chroot() {
  tl_run sudo chroot "$mount_point" "$@"
}

tl_create_disk() {
  tl_set_variables

  tl_log "%s\n" "Creating disk..."

  # Delete disk in case it exists
  if [ -f "$disk_file_name" ]; then
    rm -v "$disk_file_name"
  fi

  # Create disk
  qemu-img create -f qcow2 "$disk_file_name" 4G

  # Mount the disk
  tl_qemu_connect || exit 1

  # Format the disk file name
  tl_run sudo mkfs.ext4 "$mount_device" || exit 1

  # Show disk info
  sudo fdisk -l "$mount_device"

  # Unmount the disk
  tl_qemu_disconnect || exit 1

  # Mount the disk
  tl_mount_disk || exit 1

  # Install BusyBox to the mount point
  #   busybox "$mount_point" || exit 1
  tl_run rsync --progress --recursive -avz "${workdir}/rootfs/" "$mount_point" || exit 1

  packages=(
    "core/gcc-libs"
    "core/libcap"
    "core/pacman"
    "core/linux"
    "core/coreutils"
    "core/bash"
    "core/readline"
    "core/linux-headers"
    "core/filesystem"
    "core/base"
    "core/ncurses"
    "core/libarchive"
    "core/openssl"
    "core/curl"
    "core/gawk"
    "core/gettext"
    "core/grep"
    "core/acl"
    "core/xz"
    "core/lz4"
    "core/bzip2"
    "core/zlib"
    "core/libxml2"
    "core/libnghttp3"
    "core/libnghttp2"
    "core/libidn2"
    "core/util-linux-libs"
    "core/libxcrypt"
    "core/pam"
    "core/libseccomp"
    "core/libssh2"
    "core/libpsl"
    "core/krb5"
    "core/brotli"
    "core/libassuan"
    "core/libgpg-error"
    "core/icu"
    "core/libunistring"
    "core/libunistring"
    "core/e2fsprogs"
    "core/keyutils"
    "core/libgpg-error"
    "core/e2fsprogs"
    "core/zstd"
    "core/gpgme"
    "core/gnupg"
    "core/pacman-mirrorlist"
    "core/base-devel"
    "core/audit"
    "core/findutils"
    "core/grub"
    "core/libcap-ng"
    "core/mkinitcpio"

    # Python
    "extra/pyenv"
    "core/python"

    "extra/bash-completion"
    "extra/systemd"
    "extra/systemd-libs"
    "extra/glibc"
    "extra/reflector"
    "extra/neovim"
    "extra/zsh"
  )

  for package in "${packages[@]}"; do
    archlinux_install_package "$package" -C "$mount_point"
  done

  # Create the users within the root file system
  sudo systemd-sysusers --root "$mount_point" || exit 1

  # If --chroot is given, run the command in the chroot
  #   SHELL="/bin/bash"
  tl_chroot reflector \
    --verbose \
    --country 'United States' \
    --age 12 \
    --protocol https \
    --sort rate \
    --save /etc/pacman.d/mirrorlist || exit 1

  tl_chroot pacman -Syu --noconfirm || exit 1
  # Copy vmlinuz
  #   find "$mount_point" -type f -name 'vmlinuz' -exec cp -v '{}' "$srcdir" \;

  # Generate initrd
  #   mkinitcpio -c "$mount_point"/etc/mkinitcpio.conf -k "$srcdir"/vmlinuz -g "$srcdir"/initrd.img

  # Now that we are done with formatting the disk, unmount it
  tl_qemu_disconnect || exit 1

  printf "%s\n" "Disk created successfully."
}

tl_create_initrd() {
  tl_qemu_connect || exit 1

  tl_mount_disk || exit 1

  # Install MBR
  tl_chroot grub-install --target=i386-pc "$mount_device"

  tl_chroot mkinitcpio -P

  tl_qemu_disconnect || exit 1
}

boot() {
  printf "%s\n" "Booting..."

  tl_set_variables

  tl_qemu_disconnect

  cd "$srcdir" || exit 1

  # Create disk
  tl_create_disk

  # Step 6: Boot QEMU with BusyBox and systemd
  qemu-system-x86_64 \
    -kernel "$srcdir/vmlinuz" \
    -initrd "$srcdir/initrd.img" \
    -hda "$disk_file_name" \
    -append "root=/dev/sda rw console=ttyS0" \
    -nographic

  printf "%s\n" "Booted successfully."
}

# If --mount is given, the directory will simply be mounted
if [ "$1" = "--mount" ]; then
  tl_mount_disk
elif [ "$1" = "--unmount" ]; then
  tl_qemu_disconnect
else
  boot || exit 1
fi

exit 0
