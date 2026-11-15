#!/bin/sh
# 发行版无关的容器初始化。由各发行版的 setup.sh source 后调用。
# 所有函数都假定以 root 身份、在目标 rootfs 里执行。

setup_user() {
    old_user="${1:-}"

    if id -u tiny >/dev/null 2>&1; then
        :
    elif [ -n "$old_user" ] && id -u "$old_user" >/dev/null 2>&1; then
        # 发行版自带的 uid 1000 用户（Manjaro: builder，Arch: alarm）改名为 tiny
        usermod -l tiny -d /home/tiny -m -s /bin/bash "$old_user"
        groupmod -n tiny "$old_user" 2>/dev/null || true
    elif id -u 1000 >/dev/null 2>&1; then
        u="$(id -un 1000)"
        usermod -l tiny -d /home/tiny -m -s /bin/bash "$u"
        groupmod -n tiny "$u" 2>/dev/null || true
    else
        useradd -m -s /bin/bash -u 1000 tiny
    fi

    echo 'tiny:tiny' | chpasswd
    echo 'root:tiny' | chpasswd
    groupadd -f wheel
    usermod -aG wheel tiny
}

setup_common_files() {
    install -Dm440 /tmp/common/files/etc/sudoers.d/99-tiny /etc/sudoers.d/99-tiny
    install -Dm644 /tmp/common/files/etc/polkit-1/rules.d/99-allow-all.rules /etc/polkit-1/rules.d/99-allow-all.rules
    install -Dm755 /tmp/common/files/opt/tiny/export.sh /opt/tiny/export.sh
    install -Dm755 /tmp/common/files/opt/tiny/start-avnc.sh /opt/tiny/start-avnc.sh
    mkdir -p /opt/tiny/font /opt/tiny/extra
}

setup_locale_tz() {
    tz="${1:-Asia/Shanghai}"

    grep -q '^en_US.UTF-8' /etc/locale.gen 2>/dev/null || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
    locale-gen
    printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf

    if [ ! -e "/usr/share/zoneinfo/$tz" ]; then
        echo "无效的时区: $tz" >&2
        exit 1
    fi
    ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
    printf '%s\n' "$tz" > /etc/timezone
}

cleanup_image() {
    pacman -Scc --noconfirm || true
    rm -rf /var/cache/pacman/pkg/* /var/log/* /tmp/common /tmp/setup.sh
    rm -rf /builder
}
