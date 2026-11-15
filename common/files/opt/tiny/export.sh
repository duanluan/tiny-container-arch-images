#!/bin/bash
# 在容器内导出可再次导入 Tiny Container 的 rootfs.tar.zst。
# 由 .tiny.yaml 的 export_command 以 root 身份调用，输出到 /Public/rootfs.tar.zst
# （对应 Android 侧 filesDir/public/rootfs.tar.zst）。
set -eu

echo "==> 清理缓存与隐私文件"
pacman -Scc --noconfirm >/dev/null 2>&1 || true
rm -rf /var/cache/pacman/pkg/* /var/log/* 2>/dev/null || true
for d in /tmp/. /root/.cache /home/tiny/.cache; do
    [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
done
rm -f /root/.bash_history /home/tiny/.bash_history /home/tiny/.Xauthority 2>/dev/null || true

echo "==> 准备 bind 源文件"
mkdir -p /boot /media /mnt /proc /sys/.empty
for f in /proc/loadavg /proc/stat /proc/uptime /proc/version /proc/vmstat; do
    [ -e "$f" ] || : > "$f"
done

echo "==> 打包"
cd /
tar --zstd -cpf /Public/rootfs.tar.zst \
    .tiny.yaml bin boot etc home lib media mnt opt root sbin srv usr var \
    --transform='s|^sys/fs/selinux$|sys/.empty|' \
    --transform='s|^proc/loadavg$|proc/.loadavg|' \
    --transform='s|^proc/stat$|proc/.stat|' \
    --transform='s|^proc/uptime$|proc/.uptime|' \
    --transform='s|^proc/version$|proc/.version|' \
    --transform='s|^proc/vmstat$|proc/.vmstat|' \
    --transform='s|^proc/bus/pci/devices$|proc/.devices|' \
    --transform='s|^proc/sys/kernel/cap_last_cap$|proc/.sysctl_entry_cap_last_cap|' \
    --transform='s|^proc/sys/kernel/overflowuid$|proc/.overflowuid|' \
    --transform='s|^proc/sys/kernel/overflowgid$|proc/.overflowgid|' \
    --transform='s|^proc/sys/fs/inotify/max_user_watches$|proc/.sysctl_inotify_max_user_watches|' \
    sys/fs/selinux \
    proc/loadavg \
    proc/stat \
    proc/uptime \
    proc/version \
    proc/vmstat \
    proc/bus/pci/devices \
    proc/sys/kernel/cap_last_cap \
    proc/sys/kernel/overflowuid \
    proc/sys/kernel/overflowgid \
    proc/sys/fs/inotify/max_user_watches \
    2>/dev/null || exit 1

echo "==> 完成: /Public/rootfs.tar.zst"
ls -lh /Public/rootfs.tar.zst
