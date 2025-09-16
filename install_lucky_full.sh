#!/bin/bash
set -e

# 📁 工作目录
WORKDIR="/tmp/lucky_install"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 📦 LuCI 应用列表
LUCI_PKGS=(
  "luci-app-homeproxy"
  "luci-app-zerotier"
)

# 🌐 Lucky IPK 包链接
LUCKY_IPKS=(
  "https://p.061024.xyz/d/IPK/lucky_2.17.5_Openwrt_arm64.ipk?sign=BZcT_8JH_91sfqAxtAglZrhkgXZqiFUGjCZ8Iyi78-w=:0"
  "https://p.061024.xyz/d/IPK/luci-app-lucky_2.2.2-r1_all.ipk?sign=XPmZNPkxNtMAJRuZFb2HeWYbCABTsQv9MTobCmZpJ2c=:0"
  "https://p.061024.xyz/d/IPK/luci-i18n-lucky-zh-cn_25.051.13443.e78d498_all.ipk?sign=9PAkVc7p6B8dh7-3Juwhn7uL-ZiDsmCPCg9Di6m9d_g=:0"
)

# 📦 安装 LuCI 应用
echo "🔧 安装 LuCI 应用..."
opkg update
for pkg in "${LUCI_PKGS[@]}"; do
  echo "📦 安装 $pkg..."
  opkg install "$pkg" || echo "⚠️ 安装失败：$pkg"
done

# 📥 安装 Lucky IPK 包
echo "📥 安装 Lucky IPK 包..."
for url in "${LUCKY_IPKS[@]}"; do
  fname=$(basename "${url%%\?*}")
  echo "⬇️ 下载 $fname..."
  wget -O "$fname" "$url"
  echo "📦 安装 $fname..."
  opkg install "$fname" || echo "⚠️ 安装失败：$fname"
done

# 🔄 自动更新 Lucky 主程序（动态版本）
echo "🔍 正在检测 Lucky 最新版本..."
BASE_URL="https://release.66666.host"
LATEST_VER=$(wget -qO- "$BASE_URL" | grep -oP 'v2\.\d+\.\d+/' | sort -V | tail -n1 | tr -d '/')
echo "🆕 最新版本目录：$LATEST_VER"

DOWNLOAD_PAGE="$BASE_URL/$LATEST_VER/${LATEST_VER}_lucky/"
PAGE_HTML=$(wget -qO- "$DOWNLOAD_PAGE")
LATEST_FILE=$(echo "$PAGE_HTML" | grep -oP 'lucky_2\.\d+\.\d+_Linux_arm64\.tar\.gz' | sort -V | tail -n1)
FULL_URL="$DOWNLOAD_PAGE$LATEST_FILE"

echo "⬇️ 下载最新版 Lucky: $LATEST_FILE"
wget -O "$LATEST_FILE" "$FULL_URL"
tar -xvzf "$LATEST_FILE"
mv lucky /usr/bin/lucky
chmod +x /usr/bin/lucky

# 🧼 清理
rm -rf "$WORKDIR"

echo "🎉 所有组件安装完成！Lucky 已更新为 $LATEST_FILE"
echo "🌐 访问地址：http://你的路由器IP:16601"
echo "🔐 默认账号：666，密码：666"
