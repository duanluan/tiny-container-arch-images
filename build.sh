#!/usr/bin/env bash
# 构建 Arch Linux ARM 容器镜像，输出可导入 Tiny Container 的 rootfs.tar.zst。
#
# 用法：
#   ./build.sh                      # 最小命令行容器
#   ./build.sh --xfce               # XFCE/TigerVNC/PipeWire + 字体
#   ./build.sh --with-app-assets    # 同时复制到 App 仓库的 assets
#
# 可用环境变量：
#   MIRROR           pacman 主镜像，默认清华 TUNA
#   MIRROR_FALLBACKS 备用镜像（空格分隔）
#   TZ_NAME          时区，默认 Asia/Shanghai
#   IMAGE_TAG        本地 Docker 镜像标签
#   ZSTD_LEVEL       压缩级别，默认 3
#   ARCH_ROOTFS_URL  Arch Linux ARM rootfs 地址
#   APP_DIR          App 仓库路径（--with-app-assets 用）
#   FORCE_BASE_IMPORT=1  rootfs 更新后强制重新导入
#   KEEP_WORK=1      保留 .work 中间目录
set -euo pipefail

cd -- "$(dirname -- "$0")"
HERE="$(pwd)"
APP_DIR="${APP_DIR:-$HERE/../tiny-container-arch}"
DIST="$HERE/dist"
WORK="$HERE/.work"
CACHE="$HERE/.cache"

ARCH_DIR="$HERE/arch"
BASE_IMAGE="${BASE_IMAGE:-tiny-container-arch-base:local}"
MIRROR="${MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm}"
IMAGE_TAG="${IMAGE_TAG:-tiny-container-arch:local}"
ARCH_ROOTFS_URL="${ARCH_ROOTFS_URL:-https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz}"

INSTALL_XFCE=0
INSTALL_FONTS=0
WITH_APP_ASSETS=0
ZSTD_LEVEL="${ZSTD_LEVEL:-3}"
TZ_NAME="${TZ_NAME:-Asia/Shanghai}"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --xfce)            INSTALL_XFCE=1; INSTALL_FONTS=1 ;;
        --fonts)           INSTALL_FONTS=1 ;;
        --with-app-assets) WITH_APP_ASSETS=1 ;;
        --mirror)          MIRROR="$2"; shift ;;
        --tag)             IMAGE_TAG="$2"; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 echo "未知参数: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

die() { echo "错误: $*" >&2; exit 1; }

# .work/rootfs 由 root 容器解包，普通用户 rm 不掉，统一用容器清理
clean_work() {
    [ -d "$WORK" ] || return 0
    docker run --rm -v "$HERE:/host" debian:stable-slim \
        rm -rf /host/.work >/dev/null 2>&1 || true
    rm -rf "$WORK" 2>/dev/null || true
}

command -v docker >/dev/null 2>&1 || die "需要安装 Docker"
command -v zstd >/dev/null 2>&1 || die "需要安装 zstd"
docker info >/dev/null 2>&1 || die "Docker 未运行，或当前用户不在 docker 组"

# qemu binfmt：x86_64 主机执行 arm64 的 pacman 依赖它
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "==> 注册 arm64 binfmt（系统重启后需要重新注册）"
    docker run --privileged --rm tonistiigi/binfmt --install arm64
fi

rootfs_tarball="$CACHE/ArchLinuxARM-aarch64-latest.tar.gz"
mkdir -p "$CACHE"

downloaded=0
if [ ! -f "$rootfs_tarball" ]; then
    echo "==> 下载 Arch Linux ARM rootfs（约 791 MB，只需一次）"
    curl -L --fail --retry 3 --progress-bar \
        -o "$rootfs_tarball.part" "$ARCH_ROOTFS_URL"
    mv "$rootfs_tarball.part" "$rootfs_tarball"
    downloaded=1
fi

if curl -fsSL --max-time 30 "$ARCH_ROOTFS_URL.md5" -o "$CACHE/rootfs.md5"; then
    echo "==> 校验 rootfs MD5"
    expected="$(awk '{print $1}' "$CACHE/rootfs.md5")"
    actual="$(md5sum "$rootfs_tarball" | awk '{print $1}')"
    [ "$expected" = "$actual" ] || die "rootfs MD5 不匹配（expected=$expected actual=$actual）"
else
    echo "==> 未找到 .md5，跳过校验"
fi

# 复用已导入的镜像，避免每次构建都重新 import（会破坏 Docker 构建缓存）。
# rootfs 更新后可用 FORCE_BASE_IMPORT=1 强制重新导入。
if [ "$downloaded" = "1" ] || [ "${FORCE_BASE_IMPORT:-0}" = "1" ] \
    || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "==> 导入 Arch Linux ARM rootfs 为基础镜像: $BASE_IMAGE"
    docker import --platform linux/arm64 "$rootfs_tarball" "$BASE_IMAGE" >/dev/null
else
    echo "==> 复用已导入的基础镜像: $BASE_IMAGE"
fi

echo "==> 构建 Arch Linux ARM 镜像: $IMAGE_TAG"
echo "    base=$BASE_IMAGE"
echo "    mirror=$MIRROR tz=$TZ_NAME xfce=$INSTALL_XFCE fonts=$INSTALL_FONTS"
docker build \
    --platform linux/arm64 \
    --build-arg "BASE_IMAGE=$BASE_IMAGE" \
    --build-arg "MIRROR=$MIRROR" \
    --build-arg "TZ_NAME=$TZ_NAME" \
    --build-arg "INSTALL_XFCE=$INSTALL_XFCE" \
    --build-arg "INSTALL_FONTS=$INSTALL_FONTS" \
    -f "$ARCH_DIR/Dockerfile" \
    -t "$IMAGE_TAG" "$HERE"

echo "==> 导出容器文件系统"
clean_work
mkdir -p "$WORK" "$DIST"

cid="$(docker create --platform linux/arm64 "$IMAGE_TAG" /bin/true)"
cleanup() { docker rm -f "$cid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker export "$cid" -o "$WORK/rootfs.tar"
cleanup
trap - EXIT

echo "==> 组装 rootfs.tar（保持 root 属主、.tiny.yaml 放在最前）"
docker run --rm --platform linux/amd64 \
    -v "$WORK:/work" \
    -v "$ARCH_DIR/tiny.yaml:/src/tiny.yaml:ro" \
    debian:stable-slim bash -eo pipefail -c '
        cd /work
        rm -rf rootfs
        mkdir -p rootfs
        tar -xf rootfs.tar -C rootfs
        cp /src/tiny.yaml rootfs/.tiny.yaml

        # /etc/resolv.conf 在 Docker 里是 bind mount，只能在解包后的目录里写
        rm -f rootfs/etc/resolv.conf
        {
            printf "nameserver 223.5.5.5\n"
            printf "nameserver 119.29.29.29\n"
            printf "nameserver 8.8.8.8\n"
        } > rootfs/etc/resolv.conf
        printf "tiny-container\n" > rootfs/etc/hostname
        [ -f rootfs/etc/hosts ] || printf "127.0.0.1 localhost\n::1 localhost\n" > rootfs/etc/hosts

        # boot_command 里 --bind 的源必须存在
        mkdir -p rootfs/boot rootfs/media rootfs/mnt rootfs/proc rootfs/sys/.empty

        printf "0.00 0.00 0.00 1/1 1\n" > rootfs/proc/.loadavg
        printf "0.00 0.00\n"              > rootfs/proc/.uptime
        printf "Linux version 6.17.0-PRoot-Distro (tiny@container) #1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000 aarch64 GNU/Linux\n" > rootfs/proc/.version
        : > rootfs/proc/.vmstat
        : > rootfs/proc/.devices
        printf "40\n"    > rootfs/proc/.sysctl_entry_cap_last_cap
        printf "65534\n" > rootfs/proc/.overflowuid
        printf "65534\n" > rootfs/proc/.overflowgid
        printf "65536\n" > rootfs/proc/.sysctl_inotify_max_user_watches
        {
            printf "cpu  0 0 0 0 0 0 0 0 0 0\n"
            for i in 1 2 3 4 5 6 7; do printf "cpu%d 0 0 0 0 0 0 0 0 0 0\n" "$i"; done
            printf "intr 0\nctxt 0\nbtime 0\nprocesses 1\nprocs_running 1\nprocs_blocked 0\nsoftirq 0 0 0 0 0 0 0 0 0 0\n"
        } > rootfs/proc/.stat

        cd rootfs
        tar -cpf /work/rootfs.tar \
            .tiny.yaml \
            bin boot etc home lib media mnt opt root sbin srv usr var proc sys
    '

echo "==> 压缩"
output="$DIST/arch-rootfs.tar.zst"
zstd -T0 -"$ZSTD_LEVEL" -f -q "$WORK/rootfs.tar" -o "$output"
cp -f "$output" "$DIST/rootfs.tar.zst"

# 用 sed 而不是 head：head 提前退出会让 tar 收到 SIGPIPE，配合 pipefail 会误报失败
first_entry="$(tar --zstd -tf "$output" | sed -n '1p')"
[ "$first_entry" = ".tiny.yaml" ] || die "rootfs.tar.zst 的第一个条目不是 .tiny.yaml（实际: $first_entry）"
grep -q '^code: "arch"' "$ARCH_DIR/tiny.yaml" || die "$ARCH_DIR/tiny.yaml 的 code 不是 arch"

if [ "$WITH_APP_ASSETS" = "1" ]; then
    assets="$APP_DIR/app/src/main/assets"
    mkdir -p "$assets"
    cp -f "$output" "$assets/rootfs.tar.zst"
    echo "==> 已复制到 $assets/rootfs.tar.zst（该文件在 .gitignore 中）"
fi

if [ "${KEEP_WORK:-0}" != "1" ]; then
    clean_work
fi

echo
echo "完成: $output"
ls -lh "$output"
echo
echo "导入方式（任选其一）："
echo "  1. adb push $output /sdcard/Download/ 然后在 App 里“导入容器”"
echo "  2. ./build.sh --xfce --with-app-assets 后重新构建 APK，首启会自动安装内置容器"
