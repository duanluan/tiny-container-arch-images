# Arch Linux ARM 容器构建文件
#
# build.sh 会先把官方 ArchLinuxARM-aarch64-latest.tar.gz 通过
# `docker import` 导入成 tiny-container-arch-base:local，再执行本文件。
ARG BASE_IMAGE=tiny-container-arch-base:local
FROM ${BASE_IMAGE}

ARG MIRROR=https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm
ARG TZ_NAME=Asia/Shanghai
ARG INSTALL_FONTS=0
ARG INSTALL_XFCE=0

ENV MIRROR=${MIRROR} \
    TZ_NAME=${TZ_NAME} \
    INSTALL_FONTS=${INSTALL_FONTS} \
    INSTALL_XFCE=${INSTALL_XFCE}

COPY common/ /tmp/common/
COPY arch/setup.sh /tmp/setup.sh

RUN sh /tmp/setup.sh

CMD ["/bin/bash"]
