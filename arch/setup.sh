#!/bin/sh
# 在 Arch Linux ARM (aarch64) rootfs 里执行一次，初始化成可直接使用的容器。
set -eu

: "${MIRROR:=https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm}"
# 大包（mesa 等）偶尔会超时，按顺序尝试多个国内镜像
: "${MIRROR_FALLBACKS:=https://mirrors.ustc.edu.cn/archlinuxarm https://mirrors.bfsu.edu.cn/archlinuxarm}"
: "${TZ_NAME:=Asia/Shanghai}"
: "${INSTALL_FONTS:=0}"
: "${INSTALL_XFCE:=0}"

log() { printf '\n==> %s\n' "$*"; }

log "关闭 pacman 沙箱（Landlock/seccomp 在 proot 和 qemu 下不可用）"
sed -i \
    -e 's/^#DisableSandboxFilesystem/DisableSandboxFilesystem/' \
    -e 's/^#DisableSandboxSyscalls/DisableSandboxSyscalls/' \
    /etc/pacman.conf

log "配置 pacman 镜像: $MIRROR"
{
    printf 'Server = %s/$arch/$repo\n' "$MIRROR"
    for m in $MIRROR_FALLBACKS; do
        [ "$m" = "$MIRROR" ] && continue
        printf 'Server = %s/$arch/$repo\n' "$m"
    done
} > /etc/pacman.d/mirrorlist
pacman -Syy --noconfirm --disable-download-timeout

# 官方 generic rootfs 里没有 /etc/pacman.d/gnupg，必须先初始化才能校验签名
if [ ! -d /etc/pacman.d/gnupg ]; then
    log "初始化 pacman keyring"
    pacman-key --init
    pacman-key --populate archlinuxarm
fi

# 先删内核/固件，避免 -Syu 时白白下载并重建 initramfs
log "移除 proot 里用不到的内核与固件"
for pkg in linux-aarch64 linux-firmware; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
        pacman -Rns --noconfirm "$pkg" || true
    fi
done
rm -rf /boot/* /usr/lib/modules/* /usr/lib/firmware/* 2>/dev/null || true

log "滚动升级到最新（官方 rootfs 约每季度重建一次）"
pacman -Syu --noconfirm --disable-download-timeout

log "安装基础软件包"
pacman -S --needed --noconfirm --disable-download-timeout \
    sudo bash coreutils procps-ng iproute2 which nano less tar zstd \
    ca-certificates curl wget

if [ "$INSTALL_FONTS" = "1" ]; then
    log "安装字体"
    pacman -S --needed --noconfirm --disable-download-timeout noto-fonts noto-fonts-cjk ttf-dejavu
fi

if [ "$INSTALL_XFCE" = "1" ]; then
    log "安装 XFCE 桌面、TigerVNC 与 PipeWire"
    pacman -S --needed --noconfirm --disable-download-timeout \
        xfce4 tigervnc dbus polkit \
        pipewire pipewire-pulse wireplumber \
        xorg-xauth xorg-xsetroot xkeyboard-config
fi

. /tmp/common/setup-common.sh

log "创建 tiny 用户（Arch 自带 alarm，uid 1000）"
setup_user alarm

log "安装 sudo / polkit / 导出脚本"
setup_common_files

log "配置 locale / 时区"
setup_locale_tz "$TZ_NAME"

log "清理构建缓存"
cleanup_image

log "初始化完成"
