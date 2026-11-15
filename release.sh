#!/usr/bin/env bash
# 把构建好的镜像发布到 GitHub Releases。
#
# 用法：
#   ./release.sh                # tag: arch-YYYYMMDD
#   ./release.sh arch-20261115  # 指定 tag
#
# 发布前先构建：
#   ./build.sh --xfce
set -euo pipefail

cd -- "$(dirname -- "$0")"

REPO="${RELEASE_REPO:-duanluan/tiny-container-arch-images}"
TAG="${1:-arch-$(date +%Y%m%d)}"
ASSET="dist/arch-rootfs.tar.zst"

[ -f "$ASSET" ] || {
    echo "找不到 $ASSET，请先运行: ./build.sh --xfce" >&2
    exit 1
}

echo "==> 生成 SHA256SUMS"
(
    cd dist
    sha256sum arch-rootfs.tar.zst > SHA256SUMS
)

echo "==> 创建 Release: $TAG ($REPO)"
gh release create "$TAG" \
    "$ASSET" \
    "dist/SHA256SUMS" \
    -R "$REPO" \
    --title "Arch Linux ARM XFCE ${TAG#arch-}" \
    --notes "Arch Linux ARM (aarch64) 容器，预装 XFCE、TigerVNC、PipeWire。

- 用法：下载 \`arch-rootfs.tar.zst\`，在 Tiny Container Arch 里导入
- 校验：见 \`SHA256SUMS\`
- App：https://github.com/duanluan/tiny-container-arch/releases" \
    --latest

echo
echo "完成: https://github.com/$REPO/releases/tag/$TAG"
