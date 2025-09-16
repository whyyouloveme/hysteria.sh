#!/bin/bash
stty erase ^H

# 顺序循环颜色输出函数：红 黄 蓝 紫 青
colors=(31 33 34 35 36)  # 红 黄 蓝 紫 青
color_index=0

color_echo() {
    local color=${colors[$color_index]}
    echo -e "\e[${color}m$1\e[0m"
    color_index=$(( (color_index + 1) % ${#colors[@]} ))
}

blue_prompt() {
    local blue=34
    echo -ne "\e[${blue}m$1\e[0m"
}

blue_prompt "请输入 Xray 监听端口: "
read PORT
if [ -z "$PORT" ]; then
    echo "❌ 端口不能为空！"
    exit 1
fi

blue_prompt "请输入服务器 IP 或域名: "
read SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo "❌ 服务器 IP 不能为空！"
    exit 1
fi

# 安装依赖
color_echo "正在更新并安装软件依赖..."
apt update && apt install -y unzip curl openssl uuid-runtime

UUID=$(uuidgen)

mkdir -p /root/Xray && cd /root/Xray

color_echo "正在下载 Xray..."
curl -sL -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip

color_echo "正在解压缩 Xray..."
unzip -q xray.zip

color_echo "正在删除不需要的文件..."
rm -rf README.md LICENSE xray.zip
curl -sL -o geosite.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
curl -sL -o geoip.dat https://github.com/Loyalsoldier/geoip/releases/latest/download/geoip-only-cn-private.dat

color_echo "正在赋予执行权限..."
chmod +x xray

color_echo "正在生成证书文件..."
openssl ecparam -genkey -name prime256v1 -out "/root/Xray/private.key"
openssl req -new -x509 -days 3650 -key "/root/Xray/private.key" -out "/root/Xray/cert.pem" -subj "/CN=bing.com"

color_echo "正在创建配置文件..."
cat <<EOF > /root/Xray/config.json
{
    "log": {
        "loglevel": "none"
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "domain": [
                    "geosite:category-ads-all"
                ],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": [
                    "geoip:cn",
                    "geoip:private"
                ],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "block"
            }
        ]
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/vless?ed=2560"
                },
                "security": "tls",
                "tlsSettings": {
                    "certificates": [
                        {
                            "certificateFile": "/root/Xray/cert.pem",
                            "keyFile": "/root/Xray/private.key"
                        }
                    ]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
EOF

color_echo "正在创建 Xray 自启动服务..."
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=/root/Xray/xray run -c /root/Xray/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable xray
systemctl restart xray

# 输出 VLESS 客户端链接
VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=tls&sni=bing.com&type=ws&host=bing.com&path=/vless%3Fed%3D2560&allowInsecure=1#VLESS"

echo
color_echo "=============================="
color_echo "✅ 部署完成！"
echo
color_echo "VLESS 链接："
color_echo "$VLESS_URL"
echo
color_echo "=============================="
