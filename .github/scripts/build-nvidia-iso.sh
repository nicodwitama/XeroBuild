#!/usr/bin/env bash
# Run inside the disposable Arch Linux build container used by the workflow.
set -Eeuo pipefail
export LC_ALL=C.UTF-8
export TZ=Asia/Jakarta
umask 022

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || fail 'An x86_64 Linux builder is required.'
[[ $EUID == 0 ]] || fail 'Run this script as root inside a privileged Arch Linux container.'
[[ -f /etc/arch-release ]] || fail 'The builder must run Arch Linux.'

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
output_dir=${OUTPUT_DIR:-/workspace/out}
work_dir=${WORK_DIR:-/work}
archiso_version=91-1
chaotic_key=3056513887B78AEB
mkdir -p "$output_dir" "$work_dir"
output_dir=$(realpath -- "$output_dir")
work_dir=$(realpath -- "$work_dir")
profile_dir="$work_dir/profile"
build_dir="$work_dir/archiso"
[[ ! -e $profile_dir && ! -e $build_dir ]] || fail 'Use a fresh WORK_DIR for each build.'

trap 'printf "Build failed at line %s (exit %s). See build.log.\n" "$LINENO" "$?" >&2' ERR

# Refresh keys before updating a fresh rolling-release container.
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed archlinux-keyring
pacman -Su --noconfirm --needed archiso curl gnupg git kmod mkinitcpio
# Check verification tools before spending time installing and compressing the ISO.
for tool in mkarchiso lsinitcpio modinfo xorriso; do
    command -v "$tool" >/dev/null || fail "Missing builder tool: $tool"
done

# XeroBuild/archiso.readme explicitly targets archiso 91-1.
# Verify the archived package against Arch's trusted keyring before downgrading.
if [[ $(pacman -Q archiso) != "archiso $archiso_version" ]]; then
    package="archiso-${archiso_version}-any.pkg.tar.zst"
    archive_url="https://archive.archlinux.org/packages/a/archiso/$package"
    curl --fail --location --retry 3 "$archive_url" --output "$work_dir/$package"
    curl --fail --location --retry 3 "$archive_url.sig" --output "$work_dir/$package.sig"
    pacman-key --verify "$work_dir/$package.sig" "$work_dir/$package"
    pacman -U --noconfirm "$work_dir/$package"
fi
[[ $(pacman -Q archiso) == "archiso $archiso_version" ]] || fail 'Unexpected archiso version.'

# Bootstrap Chaotic-AUR using the primary key published in its setup guide.
pacman-key --recv-key "$chaotic_key" --keyserver hkps://keyserver.ubuntu.com
pacman-key --lsign-key "$chaotic_key"
chaotic_sources=(
    https://cdn-mirror.chaotic.cx/chaotic-aur
    https://mirror.freedif.org/chaotic-aur/chaotic-aur
)
for package in chaotic-keyring chaotic-mirrorlist; do
    filename="$package.pkg.tar.zst"
    downloaded=false
    for mirror in "${chaotic_sources[@]}"; do
        if curl --fail --location --retry 2 --connect-timeout 20 --max-time 180 \
                "$mirror/$filename" --output "$work_dir/$filename" \
            && curl --fail --location --retry 2 --connect-timeout 20 --max-time 180 \
                "$mirror/$filename.sig" --output "$work_dir/$filename.sig"; then
            downloaded=true
            break
        fi
    done
    [[ $downloaded == true ]] || fail "Unable to fetch $package from the Chaotic mirrors."
    pacman-key --verify "$work_dir/$filename.sig" "$work_dir/$filename"
done
pacman -U --noconfirm "$work_dir/chaotic-keyring.pkg.tar.zst" "$work_dir/chaotic-mirrorlist.pkg.tar.zst"
pacman-key --populate chaotic
# Keep a direct mirror as a fallback if the automatic mirror router is unavailable.
# shellcheck disable=SC2016 # pacman expands $repo and $arch itself.
printf '\nServer = https://mirror.freedif.org/chaotic-aur/$repo/$arch\n' >> /etc/pacman.d/chaotic-mirrorlist

cp -a -- "$repo_dir/nVidia" "$profile_dir"
for package in linux linux-headers nvidia-open-dkms linux-firmware-nvidia; do
    grep -qx "$package" "$profile_dir/packages.x86_64" || fail "Missing profile package: $package"
done

# Use official Arch CDN mirrors for the build. Live-system mirrors stay upstream.
# shellcheck disable=SC2016 # pacman expands $repo and $arch itself.
printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\nServer = https://fastly.mirror.pkgbuild.com/$repo/os/$arch\n' \
    > /etc/pacman.d/mirrorlist

# Resolve every package and group before beginning the large rootfs installation.
pacman --config "$profile_dir/pacman.conf" -Sy --noconfirm
mapfile -t profile_packages < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$profile_dir/packages.x86_64")
pacman --config "$profile_dir/pacman.conf" -Sp --noconfirm --print-format '%n %v' \
    "${profile_packages[@]}" > "$output_dir/resolved-packages-report.txt"

{
    printf 'Source commit: %s\n' "${XERO_SOURCE_COMMIT:-unknown}"
    printf 'Upstream baseline: e84a9160c81124e1032b0272b216df1ee238354c\n'
    printf 'Built at: %s\n' "$(date -Iseconds)"
    printf 'Target: NVIDIA GeForce RTX 5060 / x86_64\n'
    printf 'Profile: nVidia (upstream NVIDIA open DKMS modules)\n'
    printf 'Boot: BIOS + UEFI; physical GPU behavior is not tested by CI.\n'
    pacman -Q archiso
} > "$output_dir/build-info.txt"

mkarchiso -v -w "$build_dir" -o "$output_dir" "$profile_dir"

# Pacman may continue after a failing DKMS hook; explicitly require built modules.
airootfs="$build_dir/x86_64/airootfs"
[[ -d $airootfs ]] || fail 'Cannot locate the built live root filesystem.'
mapfile -t kernels < <(find "$airootfs/usr/lib/modules" -mindepth 2 -maxdepth 2 -name pkgbase -exec dirname {} \;)
[[ ${#kernels[@]} == 1 ]] || fail 'Expected exactly one kernel in the live image.'
kernel_version=${kernels[0]##*/}
{
    printf 'Kernel: %s\n' "$kernel_version"
    for module in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
        modinfo -b "$airootfs" -k "$kernel_version" "$module"
    done
} > "$output_dir/nvidia-driver-report.txt"
grep -Eq '^license:[[:space:]]+Dual MIT/GPL' "$output_dir/nvidia-driver-report.txt" \
    || fail 'Expected the NVIDIA open kernel modules.'
# archiso moves boot files out of airootfs before compressing the live filesystem.
lsinitcpio "$build_dir/x86_64/boot/initramfs-linux.img" > "$output_dir/initramfs-report.txt"
for module in nvidia nvidia-modeset nvidia-uvm nvidia-drm; do
    module_pattern=${module//-/[-_]}
    grep -Eq "/${module_pattern}\\.ko(\\.(zst|xz|gz))?$" "$output_dir/initramfs-report.txt" \
        || fail "Missing initramfs module: $module"
done

shopt -s nullglob
isos=("$output_dir"/xerolinux-nvidia-*.iso)
[[ ${#isos[@]} == 1 ]] || fail 'Expected exactly one completed NVIDIA ISO.'
iso=${isos[0]}
xorriso -indev "$iso" -report_el_torito plain > "$output_dir/boot-report.txt" 2>&1
xorriso -indev "$iso" -report_system_area plain > "$output_dir/hybrid-report.txt" 2>&1
grep -q BIOS "$output_dir/boot-report.txt" || fail 'Missing BIOS boot image.'
grep -q UEFI "$output_dir/boot-report.txt" || fail 'Missing UEFI boot image.'
grep -qi isohybrid "$output_dir/hybrid-report.txt" || fail 'Missing USB hybrid boot metadata.'
(
    cd -- "$output_dir"
    sha256sum -- "${iso##*/}" > SHA256SUMS
    sha256sum --check SHA256SUMS
)
stat --printf='ISO size: %s bytes\n' "$iso" >> "$output_dir/build-info.txt"
printf 'Build and structural checks completed: %s\n' "$iso"
