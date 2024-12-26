#!/bin/bash

# Set variables
srcdir=
mount_point=
mount_device=
disk_file_name=
packages_dir=
workdir=

tl_set_variables() {
  # If `workdir` is not set, set it to the current directory
  workdir="${workdir:-$(pwd)}"

  srcdir="${workdir}/src"
  tl_mkdir "$srcdir"

  packages_dir="${srcdir}/packages"
  tl_mkdir "$packages_dir"

  # Final root file system
  mount_point="${srcdir}/mnt"
  tl_mkdir "$mount_point"

  # Create BusyBox folder
  srcdir_busybox="${srcdir}/busybox"
  tl_mkdir "$srcdir_busybox"

  # Set mount device
  mount_device="/dev/nbd0"

  # Set HDD path
  disk_file_name="${srcdir}/hdd.qcow2"
}
