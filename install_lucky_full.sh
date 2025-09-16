#!/bin/bash
set -e

# 📁 工作目录与日志
WORKDIR="/tmp/lucky_install"
BACKUPDIR="/etc/lucky_backup"
LOGFILE="/tmp/lucky_install.log"
mkdir -p "$WORKDIR" "$BACKUPDIR"
exec > >(tee -a "$LOGFILE") 2>&1

# 📦 LuCI 应用列表
LUCI_PKGS=("luci-app-homeproxy" "luci-app-zerotier")

# 🌐 Lucky IPK 包链接
LUCKY_IPKS=(
  "https://p.061024.xyz/d/IPK/lucky_2.17.5_Openwrt_arm64.ipk?sign=BZcT_8JH_91sfqAxtAglZrhkgXZqiFUGjCZ8Iyi78-w=:0"
  "https://p.061024.xyz/d/IPK/luci-app-lucky_2.2.2-r1_all.ipk?sign=XPmZNPkxNtMAJRuZFb2HeWYbCABTsQv9MTobCmZpJ2c=:0"
  "https://p.061024.xyz/d/IPK/luci-i18n-lucky-zh-cn_25.051.13443.e78d498_all.ipk?sign=9PAkVc7p6B8dh7-3Juwhn7uL-ZiDsmCPCg9Di6m9d_g=:0"
)

# 🧠 菜单交互
echo "🧩 请选择要安装的模块："
echo "1. 安装 LuCI 应用"
echo "2. 安装 Lucky IPK 包"
echo "3. 更新 Lucky 主程序（最新版）"
echo "4. 全部安装"
read -p "请输入选项（1/2/3/4）: " CHOICE

# 🔐 备份配置
echo "🔐 正在备份配置文件..."
cp -r /etc/config "$BACKUPDIR/config"
[ -d /etc/lucky ] && cp -r /etc/lucky "$BACKUPDIR/lucky"

# ✅ 安装 LuCI 应用
if [[ "$CHOICE" == "1" || "$CHOICE" == "4" ]]; then
  echo "🔧 安装 LuCI 应用..."
  opkg update
  for pkg in "${LUCI_PKGS[@]}"; do
    if opkg list-installed | grep -q "$pkg"; then
      echo "✅ 已安装：$pkg，跳过"
    else
      echo "📦 安装 $pkg..."
      opkg install "$pkg" || echo "⚠️ 安装失败：$pkg"
    fi
  done
fi

# 📥 安装 Lucky IPK 包
if [[ "$CHOICE" == "2" || "$CHOICE" == "4" ]]; then
  echo "📥 安装 Lucky IPK 包..."
  for url in "${LUCKY_IPKS[@]}"; do
    fname=$(basename "${url%%\?*}")
    echo "⬇️ 下载 $fname..."
    wget -O "$WORKDIR/$fname" "$url"
    echo "📦 安装 $fname..."
    if ! opkg install "$WORKDIR/$fname"; then
      echo "❌ 安装失败：$fname，正在回滚配置..."
      cp -r "$BACKUPDIR/config" /etc/config
      [ -d "$BACKUPDIR/lucky" ] && cp -r "$BACKUPDIR/lucky" /etc/lucky
      exit 1
    fi
  done
fi

# 🔄 自动更新 Lucky 主程序（动态版本）
if [[ "$CHOICE" == "3" || "$CHOICE" == "4" ]]; then
  echo "🔍 正在检测 Lucky 最新版本..."
  BASE_URL="https://release.66666.host"
  LATEST_VER=$(wget -qO- "$BASE_URL" | grep -oP 'v2\.\d+\.\d+/' | sort -V | tail -n1 | tr -d '/')
  echo "🆕 最新版本目录：$LATEST_VER"

  DOWNLOAD_PAGE="$BASE_URL/$LATEST_VER/${LATEST_VER}_lucky/"
  PAGE_HTML=$(wget -qO- "$DOWNLOAD_PAGE")
  LATEST_FILE=$(echo "$PAGE_HTML" | grep -oP 'lucky_2\.\d+\.\d+_Linux_arm64\.tar\.gz' | sort -V | tail -n1)
  FULL_URL="$DOWNLOAD_PAGE$LATEST_FILE"

  echo "⬇️ 下载最新版 Lucky: $LATEST_FILE"
  wget -O "$WORKDIR/$LATEST_FILE" "$FULL_URL"
  tar -xvzf "$WORKDIR/$LATEST_FILE" -C "$WORKDIR"
  mv "$WORKDIR/lucky" /usr/bin/lucky
  chmod +x /usr/bin/lucky
  echo "✅ Lucky 主程序已更新为 $LATEST_FILE"
fi

# 🧼 清理
rm -rf "$WORKDIR"

echo "🎉 安装完成！日志保存在 $LOGFILE"
echo "🌐 访问 Lucky：http://你的路由器IP:16601"
echo "🔐 默认账号：666，密码：666"
