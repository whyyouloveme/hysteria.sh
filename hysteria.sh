#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){ echo -e "\033[31m\033[01m$1\033[0m"; }
green(){ echo -e "\033[32m\033[01m$1\033[0m"; }
yellow(){ echo -e "\033[33m\033[01m$1\033[0m"; }

# ------------------ 系统判断 ------------------
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")

[[ $EUID -ne 0 ]] && red "请在root用户下运行" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" \
     "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" \
     "$(lsb_release -sd 2>/dev/null)" \
     "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" \
     "$(grep . /etc/redhat-release 2>/dev/null)" \
     "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int=0; int<${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持的操作系统" && exit 1
[[ -z $(type -P curl) ]] && ${PACKAGE_INSTALL[int]} curl

realip(){ ip=$(curl -s4m8 ip.gs -k) || ip=$(curl -s6m8 ip.gs -k); }

# ------------------ 默认自签证书 ------------------
inst_cert(){
    green "使用默认自签证书"
    mkdir -p /etc/hysteria
    cert_path="/etc/hysteria/cert.crt"
    key_path="/etc/hysteria/private.key"
    openssl ecparam -genkey -name prime256v1 -out "$key_path"
    openssl req -new -x509 -days 36500 -key "$key_path" -out "$cert_path" -subj "/CN=www.bing.com"
    chmod 777 "$cert_path" "$key_path"
    hy_domain="www.bing.com"
}

# ------------------ Hysteria 安装参数 ------------------
inst_port(){
    read -p "设置 Hysteria 2 端口 [1-65535]（回车随机）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    yellow "端口：$port"
}

inst_pwd(){
    read -p "设置密码（回车随机生成）：" auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "密码：$auth_pwd"
}

inst_site(){
    read -p "伪装网站 [默认 maimai.sega.jp]：" proxysite
    [[ -z $proxysite ]] && proxysite="maimai.sega.jp"
    yellow "伪装网站：$proxysite"
}

# ------------------ 安装 Hysteria ------------------
insthysteria(){
    realip
    if [[ ! ${SYSTEM} == "CentOS" ]]; then ${PACKAGE_UPDATE[int]}; fi
    ${PACKAGE_INSTALL[int]} curl wget sudo iptables-persistent netfilter-persistent
    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh
    bash install_server.sh
    rm -f install_server.sh
    [[ ! -f "/usr/local/bin/hysteria" ]] && red "安装失败" && exit 1

    inst_cert; inst_port; inst_pwd; inst_site

    cat << EOF > /etc/hysteria/config.yaml
listen: :$port

tls:
  cert: $cert_path
  key: $key_path

quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$proxysite
    rewriteHost: true

acl:
  inline:
    - reject(geosite:category-ads-all)
    - reject(geoip:private)
    - reject(geoip:cn)
    - v6_only(suffix:youtube.com)
    - v4_only(suffix:google.com)
    - direct(all)
  geoUpdateInterval: 24h

outbounds:
  - name: v4_only
    type: direct
    direct:
      mode: 4
  - name: v6_only
    type: direct
    direct:
      mode: 6
EOF

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) ]] && green "Hysteria 启动成功" || red "启动失败"
}

# ------------------ 卸载 ------------------
unsthysteria(){
    systemctl stop hysteria-server >/dev/null 2>&1
    systemctl disable hysteria-server >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    green "已卸载完成"
}

starthysteria(){ systemctl start hysteria-server; systemctl enable hysteria-server >/dev/null 2>&1; }
stophysteria(){ systemctl stop hysteria-server; systemctl disable hysteria-server >/dev/null 2>&1; }

hysteriaswitch(){
    yellow "操作：1启动 2关闭 3重启"
    read -rp "选项 [1-3]: " switchInput
    case $switchInput in
        1) starthysteria ;;
        2) stophysteria ;;
        3) stophysteria && starthysteria ;;
        *) exit 1 ;;
    esac
}

# ------------------ 修改配置 ------------------
change_port(){
    oldport=$(grep 'listen:' /etc/hysteria/config.yaml | awk -F ":" '{print $2}')
    read -p "新端口 [回车随机]：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    sed -i "s/:$oldport/:$port/" /etc/hysteria/config.yaml
    systemctl restart hysteria-server
    green "端口已修改为 $port"
}

change_password(){
    oldpass=$(grep 'password:' /etc/hysteria/config.yaml | awk '{print $2}')
    read -p "新密码 [回车随机]：" auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    sed -i "s/$oldpass/$auth_pwd/" /etc/hysteria/config.yaml
    systemctl restart hysteria-server
    green "密码已修改为 $auth_pwd"
}

change_site(){
    oldsite=$(grep 'url:' /etc/hysteria/config.yaml | awk '{print $2}' | sed 's/https:\/\///')
    read -p "新伪装网站 [回车保持原值 $oldsite]：" proxysite
    [[ -z $proxysite ]] && proxysite=$oldsite
    sed -i "s#$oldsite#$proxysite#g" /etc/hysteria/config.yaml
    systemctl restart hysteria-server
    green "伪装网站已修改为 $proxysite"
}

changeconf(){
    yellow "修改选项：1端口 2密码 3伪装网站"
    read -rp "选项 [1-3]：" confInput
    case $confInput in
        1) change_port ;;
        2) change_password ;;
        3) change_site ;;
        *) exit 1 ;;
    esac
}

# ------------------ 更新核心 ------------------
update_core(){
    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh
    bash install_server.sh
    rm -f install_server.sh
    green "核心更新完成"
}

# ------------------ 菜单 ------------------
menu(){
    clear
    echo "1. 安装 Hysteria 2"
    echo "2. 卸载 Hysteria 2"
    echo "3. 启动/关闭/重启"
    echo "4. 修改配置(端口/密码/伪装网站)"
    echo "5. 更新核心"
    echo "0. 退出"
    read -rp "选项 [0-5]: " menuInput
    case $menuInput in
        1) insthysteria ;;
        2) unsthysteria ;;
        3) hysteriaswitch ;;
        4) changeconf ;;
        5) update_core ;;
        *) exit 1 ;;
    esac
}

menu
