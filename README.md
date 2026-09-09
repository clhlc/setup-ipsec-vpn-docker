# StrongSwan IKEv2 VPN 部署与多平台适配指南

这是一个基于 StrongSwan (swanctl) 部署的 IPsec IKEv2 VPN 完整配置指南。经过深度调优，本配置完美解决了多平台（iOS、macOS、Windows 11、Android）原生客户端的兼容性问题，彻底解决了因 UDP 分片丢包、证书信任链、加密算法不匹配导致的连接超时（Timeout）假死现象。

## 🌟 核心特性与避坑总结

* **全平台兼容**：支持 iOS / macOS / Windows 原生客户端，以及 Android strongSwan 官方客户端。
* **强制 RSA 证书**：iOS 原生客户端通过 UI 手动配置时**严格拒绝 ECC 证书**。本方案强制使用 ZeroSSL RSA 2048 证书，确保 iOS 秒连。
* **UDP 分片控制 (MTU)**：限制了 IKE 消息的分片大小，穿透严苛的运营商 NAT 防火墙。
* **证书链极简优化**：服务端**不发送中间证书**。利用系统底层的 AIA Fetching 自动补全机制，将认证数据包强行压缩至 2 个 UDP 分片内，彻底规避 Android/Windows 处理 3+ 分片时的丢包断联 Bug。

---

## 🛠️ 1. 证书签发 (ZeroSSL RSA)

必须使用 ZeroSSL 签发 **RSA 2048** 位证书。不要使用 ECC

```bash
# 1. 强制申请 RSA 2048 证书 (替换为你的域名)
export domain=vpn.yourdomain.com

cd setup-ipsec-vpn-docker

# standalone
acme.sh --issue -d $domain --standalone --keylength 2048 --server zerossl

# 或者使用dns方式
acme.sh --issue -d $domain --dns dns_cf --keylength 2048 --server zerossl

# 2. 安装证书到 StrongSwan 目录
acme.sh --install-cert -d $domain --key-file ./certs/server-key.pem --cert-file ./certs/server-cert.pem --ca-file ./certs/ca.pem
```

## 2. 部署服务

```bash
sed -i "s/vpnyourdomaincom/${domain}/g" config/swanctl.conf

docker compose up -d --build
```

## 3. 其他说明
* 用户按照格式写入 config/users.conf
* ECC-256证书支持MacOS/Windows 11/Strongswan APP
* RSA 2048证书全平台支持

## 4. 证书类型与操作系统兼容性表

|  | macOS 26 | iOS 26 | Windows 11| 安卓 (Android 16) |
| :--- | :---: | :---: | :---: | :---: |
| **Let's Encrypt RSA 2048** | &#10004; | &#10004; | &#10008; | &#10008; |
| **Let's Encrypt ECC 256** (ECDSA P-256) | &#10004; | &#10008; | &#10008; | &#10008; |
| **ZeroSSL RSA 2048** | &#10004; | &#10004; | &#10004; | &#10004; |
| **ZeroSSL ECC 256** (ECDSA P-256) | &#10004; | &#10008; | &#10004; | &#10008; |