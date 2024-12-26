arch=6.12.6

source "variables.sh"
source "core.sh"

archlinux_install_package() {
  tl_set_variables

  # Get the first argument and put the remaining ones in an array
  local package_name
  package_name="$1"

  # Download the package
  local package_file_name
  package_file_name="$(archlinux_download_package "$package_name")"

  # If package_file_name is empty, exit with a descriptive error message
  if [ -z "$package_file_name" ]; then
    tl_log 'Error: Failed to download package "%s"\n' "$package_file_name"
    tl_log 'Package "%s" not found\n' "$package_name"
    exit 1
  fi

  local bsdtar_args
  bsdtar_args=()

  bsdtar_args+=(
    -v
    #     --strip-components=1
    -xjf
  )
  # Get all the arguments after the first one
  shift
  bsdtar_args+=(
    "$package_file_name"
    "$@"
  )

  tl_run bsdtar "${bsdtar_args[@]}"
}

# Download an Arch Linux package by the name, and return the absolute path to the file
archlinux_download_package() {
  tl_set_variables

  local package_name="$1"
  local out_archive_dir

  # Output directory is either $2 or $packages_dir/$package_name
  #   out_archive_dir="${2:-$packages_dir/$package_name}"
  out_archive_dir="$packages_dir/$package_name"
  tl_mkdir "$out_archive_dir" || exit 1

  local repo

  # If the path is something like `$repo_name/$pkg_name`, split it by / and set $package_name to the second item of the array,
  # and the first one as the repository name
  if [[ "$package_name" =~ ^([^/]+)/(.*) ]]; then
    repo="${BASH_REMATCH[1]}"
    package_name="${BASH_REMATCH[2]}"
  fi

  local input_package_info_file
  input_package_info_file="$out_archive_dir/tmp.json"

  node "${workdir}"/parse-package-name.js "$package_name" >"$input_package_info_file"

  package_name="$(tl_jq "$input_package_info_file" -r '.name')"
  repo="$(tl_jq "$input_package_info_file" -r '.repo' | grep -v 'null')"

  local search_params=()
  search_params+=("name=$package_name")

  #   if [ -n "$repo" ]; then
  #     search_params+=("repo=$repo")
  #   fi

  #   possible_repositories=(
  #     core extra multilib
  #   )
  #
  #   for repo in "${possible_repositories[@]}"; do
  #     search_params+=("repo=$repo")
  #   done

  local node_args
  node_args=(
    "${workdir}"/url.js
    "${search_params[*]}"
  )
  query_parameters="$(node "${node_args[@]}")"

  tl_log 'Query parameters: %s\n' "$query_parameters"

  local package_information_file="$out_archive_dir/tl_package.json"
  curl_args=(
    "https://archlinux.org/packages/search/json/?$query_parameters"
    -o "$package_information_file"
  )
  tl_run curl "${curl_args[@]}"

  local result_count
  result_count="$(tl_jq "$package_information_file" '.results | length')"

  # If length is below one, exit with a descriptive error message
  if [ "$result_count" -lt 1 ]; then
    tl_log "No results for $package_name"
    exit 1
  fi

  local filename
  filename="$(tl_jq "$package_information_file" -r '.results[0].filename')"

  # If filename is empty, exit with a descriptive error message
  if [ -z "$filename" ]; then
    tl_log "No filename for $package_name"
    exit 1
  fi

  local version
  version="$(tl_jq "$package_information_file" -r '.results[0].version')"

  # If `repo` is empty, get it from the package information file
  if [ -z "$repo" ]; then
    repo="$(tl_jq "$package_information_file" -r '.results[0].repo')"
  fi

  local arch
  arch="$(tl_jq "$package_information_file" -r '.results[0].arch' | grep -v 'null')"

  # If `arch` is empty, set it to `any`
  if [ -z "$arch" ] && [ -z "$ARCH" ]; then
    arch="any"
  elif [ -n "$ARCH" ]; then
    arch="$ARCH"
  fi

  local al_package_compressed_file_name
  al_package_compressed_file_name="$filename"

  local al_package_url
  #   # https://geo.mirror.pkgbuild.com/core/os/x86_64/filesystem-2024.11.21-1-any.pkg.tar.zst
  #   mirror=https://mirror.cmt.de/archlinux
  #   #  mirror=https://geo.mirror.pkgbuild.com
  #   al_package_url="$mirror/$repo/os/$arch/$al_package_compressed_file_name"
  #   #   al_package_url="https://archlinux.org/packages/$repo/os/$arch/$package_name"

  # Print the file name
  tl_log 'Found "%s" version "%s"\n' "$filename" "$version"

  local downloaded=0

  mirrors=(
    'https://archlinux.c3sl.ufpr.br/'
    'https://america.mirror.pkgbuild.com/'
    'https://arch.mirror.constant.com/'
    'http://arch.mirror.constant.com/'
    'http://mirrors.bjg.at/arch/'
    'http://archlinux.c3sl.ufpr.br/'
    'http://mirrors.bloomu.edu/archlinux/'
    'https://mirrors.bloomu.edu/archlinux/'
    'https://us.arch.niranjan.co/'
    'https://mirrors.vectair.net/archlinux/'
    'http://us.arch.niranjan.co/'
    'https://mirror.arizona.edu/archlinux/'
    'http://arlm.tyzoid.com/'
    'https://arlm.tyzoid.com/'
    'http://mirror.arizona.edu/archlinux/'
    'https://mirrors.sonic.net/archlinux/'
    'http://mirrors.sonic.net/archlinux/'
    'https://arch.hu.fo/archlinux/'
    'http://mirrors.vectair.net/archlinux/'
    'http://arch.hu.fo/archlinux/'
  )

  local downloaded=0

  for mirror in "${mirrors[@]}"; do
    if [ "$downloaded" -eq 1 ]; then
      break
    fi

    al_package_url="$mirror/$repo/os/$arch/$al_package_compressed_file_name"

    tl_download \
      "$al_package_url" \
      -P "$out_archive_dir" || continue

    downloaded=1
  done

  printf '%s' "$out_archive_dir/$filename"
}
