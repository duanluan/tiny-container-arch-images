#!/bin/bash
# 启动 AVNC 所需的 XFCE + TigerVNC + PipeWire。
# 由 .tiny.yaml 的 avnc.command 调用。
# 日志统一写到 /tmp/avnc-start.log，方便排查。
exec >>/tmp/avnc-start.log 2>&1
set -x

mkdir -p /run/dbus
sudo dbus-daemon --system --fork 2>/dev/null || true
eval "$(dbus-launch --sh-syntax)" 2>/dev/null || true

export XDG_RUNTIME_DIR="/tmp/runtime-tiny"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# tiny 不是 root，Xvnc/ICE 不会自己创建这些目录
sudo mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
sudo chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix
sudo /usr/lib/polkit-1/polkitd >/dev/null 2>&1 || true &

# PipeWire 失败也不阻塞 Xvnc
pipewire >/tmp/pipewire.log 2>&1 &
for _ in $(seq 1 50); do [ -S "$XDG_RUNTIME_DIR/pipewire-0" ] && break; sleep 0.1; done
wireplumber >/tmp/wireplumber.log 2>&1 &
pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 &

VNC=Xtigervnc
[ -x /usr/bin/Xvnc ] && VNC=Xvnc
"$VNC" -geometry "${AVNC_GEOMETRY:-1400x876}" -pn -rfbport -1 \
    -SendPrimary=off -SetPrimary=off -FrameRate=120 \
    -rfbunixpath /tmp/.tiny.vnc -alwaysshared -a 5 -once -depth 24 \
    -SecurityTypes=None -desktop "Tiny-Arch-XFCE" :6 +extension MIT-SHM >/tmp/xvnc.log 2>&1 &

for _ in $(seq 1 100); do [ -S /tmp/.tiny.vnc ] && break; sleep 0.1; done
if [ ! -S /tmp/.tiny.vnc ]; then
    echo "ERROR: /tmp/.tiny.vnc not created"
    exit 1
fi

startxfce4 >/tmp/xfce.log 2>&1 &
echo "VNC socket ready"
