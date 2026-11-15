# Tiny Container Arch Images

给 [Tiny Container Arch](https://github.com/duanluan/tiny-container-arch)
用的 Arch Linux ARM（aarch64）容器镜像。

镜像发布在本仓库的 [Releases](https://github.com/duanluan/tiny-container-arch-images/releases)：

- `arch-rootfs.tar.zst`：XFCE + TigerVNC + PipeWire + 中文字体
- `SHA256SUMS`：校验和

## 使用

1. 安装 App：[Tiny Container Arch Releases](https://github.com/duanluan/tiny-container-arch/releases)
2. 下载本仓库最新 Release 里的 `arch-rootfs.tar.zst`
3. App → 容器管理 → 导入 → 选择该文件
4. 进入容器终端确认：
   ```bash
   cat /etc/os-release   # Arch Linux ARM
   pacman -Q | wc -l
   ```
5. 想用桌面：到“功能”页启用 **AVNC 图形界面**，重启容器。

## 构建

依赖：

- Docker（当前用户在 `docker` 组）
- `zstd`
- x86_64 主机上的 arm64 模拟（脚本会自动用 `tonistiigi/binfmt` 注册）
- 首次构建下载官方 `ArchLinuxARM-aarch64-latest.tar.gz`（约 791 MB）

```bash
# 最小命令行容器
./build.sh

# 推荐：XFCE + TigerVNC + PipeWire + 中文字体
./build.sh --xfce
```

产物：

- `dist/arch-rootfs.tar.zst`
- `dist/rootfs.tar.zst`（副本）

可选环境变量见 `./build.sh --help`。

## 发布

```bash
# 先构建
./build.sh --xfce

# 发布到本仓库 Releases（默认 tag: arch-YYYYMMDD）
./release.sh
```

也可以指定 tag：

```bash
./release.sh arch-20261115
```

## 目录结构

```
.
├── build.sh                  # 主机侧：导入 rootfs → docker build → 导出 → 组装 tar.zst
├── release.sh                # 发布到 GitHub Releases
├── common/
│   ├── setup-common.sh       # tiny 用户、sudo、polkit、locale、清理
│   └── files/
│       ├── etc/sudoers.d/99-tiny
│       ├── etc/polkit-1/rules.d/99-allow-all.rules
│       └── opt/tiny/export.sh    # App 内“导出容器”时使用
│           opt/tiny/start-avnc.sh # AVNC + XFCE 启动脚本
├── arch/
│   ├── Dockerfile            # 基于官方 ArchLinuxARM-aarch64 rootfs
│   ├── setup.sh              # 镜像源、升级、删内核/固件、装软件
│   └── tiny.yaml             # 容器配置模板 → 打包为 /.tiny.yaml
├── dist/                     # 产物（git 忽略）
├── .cache/                   # 下载的 rootfs（git 忽略）
└── .work/                    # 中间目录（git 忽略）
```

## 镜像里有什么

- 用户 `tiny` / 密码 `tiny`，uid 1000，免密 sudo；`root` / 密码 `tiny`
- `LANG=en_US.UTF-8`，时区 `Asia/Shanghai`
- DNS：223.5.5.5 / 119.29.29.29 / 8.8.8.8
- pacman 镜像指向清华 TUNA，并配置 USTC/BFSU 回退
- 移除了 `linux-aarch64`、`linux-firmware`、内核模块（proot 里用不到）
- 关闭 pacman 的 Landlock/seccomp 沙箱（proot/qemu 下会失败）
- 初始化 pacman keyring
- XFCE 版额外带 XFCE、TigerVNC、PipeWire、WirePlumber、中文字体

## 已知问题 / TODO

- [ ] 音频/麦克风转发模块尚未编译（需要 PipeWire 模块源码）。
- [ ] 预览图 `opt/tiny/preview.png`。
- [ ] 真机验证 AVNC / X11、输入法、打印、外部存储。
- [ ] 可选：用 GitHub Actions 自动构建并发布。

## 与 App 仓库的关系

- App（代码、APK）：[duanluan/tiny-container-arch](https://github.com/duanluan/tiny-container-arch)
- 本仓库只负责容器镜像，避免镜像 Release 干扰 App 的更新检查。

## License

GPL-3.0-or-later，见 `COPYING`。
