FROM alpine:latest

ARG STRONGSWAN_VERSION=6.0.7

# 1. 安装运行时依赖和编译工具链
RUN apk update && apk add --no-cache \
    # 运行时必要的网络与核心库
    iptables ip6tables iproute2 bash tzdata openssl curl \
    # 编译期所需的工具和头文件
    build-base openssl-dev linux-headers curl-dev wget tar bzip2

# 2. 下载并解压源码
WORKDIR /tmp
RUN wget https://download.strongswan.org/strongswan-${STRONGSWAN_VERSION}.tar.bz2 && \
    tar xjf strongswan-${STRONGSWAN_VERSION}.tar.bz2

# 3. 配置编译参数、编译并安装
WORKDIR /tmp/strongswan-${STRONGSWAN_VERSION}
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --libexecdir=/usr/lib \
    --with-rundir=/var/run \
    --enable-swanctl \
    --enable-vici \
    --enable-openssl \
    --enable-curl \
    --enable-eap-identity \
    --enable-eap-mschapv2 \
    --enable-eap-md5 \
    --enable-eap-tls \
    --enable-eap-peap \
    --enable-eap-ttls \
    --enable-nonce \
    --enable-pem \
    --enable-x509 \
    --enable-pkcs1 \
    --enable-revocation \
    --disable-gmp \
    --disable-ikev1 \
    --disable-scripts \
    && make -j$(nproc) \
    && make install

# 4. 卸载编译工具链并清理临时目录以压缩镜像体积
RUN apk del build-base openssl-dev linux-headers curl-dev wget tar bzip2 && \
    rm -rf /tmp/*

# 设置时区
ENV TZ=Asia/Shanghai

# 复制并赋予启动脚本执行权限
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 暴露 IKEv2 必需的端口
EXPOSE 500/udp 4500/udp

ENTRYPOINT ["/entrypoint.sh"]
