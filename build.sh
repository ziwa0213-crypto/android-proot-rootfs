#!/usr/bin/env bash
#
# android-proot-rootfs 构建脚本（单文件版）
#
#   sudo ./build.sh <发行版> <架构> <档位>
#
#   发行版：
#     debian-12 | debian-13 | ubuntu-24.04 | ubuntu-26.04 | alpine-3.24
#     almalinux-9 | opensuse-tumbleweed | opencloudos-9 | archlinux | kalinethunter | void
#   架构  ：arm64 | amd64        （archlinux 只有 arm64）
#   档位  ：min | base | dev
#
#   例：sudo ./build.sh debian-12 arm64 base
#       sudo ./build.sh almalinux-9 arm64 base
#       sudo ./build.sh void amd64 dev
#       sudo ./build.sh ubuntu-24.04 amd64 base --mirror http://mirrors.tuna.tsinghua.edu.cn/ubuntu
#
#   LXC 源（almalinux-9 / opensuse-tumbleweed）默认用官方 images.linuxcontainers.org。
#   国内下载慢就换清华镜像（同步的是同一份，路径完全相同）：
#       --lxc-mirror https://mirrors.tuna.tsinghua.edu.cn/lxc-images/images
#
#   tarball 源（void / archlinux）同理，--tarball-mirror 传「镜像站上这个发行版的根目录」：
#       --tarball-mirror https://mirrors.tuna.tsinghua.edu.cn/voidlinux
#       --tarball-mirror https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm
#   （kalinethunter 走 kali.download，清华没有这个目录，只能用官方）
#
#   全部跑一遍：sudo ./build.sh all          （见文件末尾的矩阵定义）
#   只跑新增的几个：sudo ./build.sh new-all
#
set -euo pipefail

# ---------------------------------------------------------------- 发行版定义
# FAMILY = 怎么把根文件系统弄出来：deb | alpine | lxc | tarball | dockersave
# PM     = 装包用哪个包管理器：apt | apk | dnf | zypper | pacman | xbps
declare -A D_NAME D_VERSION D_RELEASE D_FAMILY D_MIRROR D_COMPONENTS D_KEYRING D_PM D_ARCHES
# LXC 源。默认官方；国内慢可用 --lxc-mirror 换清华（同步的是同一份，路径完全相同）：
#   https://mirrors.tuna.tsinghua.edu.cn/lxc-images/images
LXC_BASE="https://images.linuxcontainers.org/images"
# tarball 类发行版的取包根。--tarball-mirror 整段替换成镜像站上的同名目录
# （镜像保持与官方一致的路径结构，所以只换根、后面的相对路径不动）：
#   void        https://mirrors.tuna.tsinghua.edu.cn/voidlinux
#   archlinux   https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm
VOID_BASE="https://repo-default.voidlinux.org"
ARCH_BASE="http://os.archlinuxarm.org"
KALI_BASE="https://kali.download"
TARBALL_MIRROR=""
declare -A D_LXC_PROJECT D_LXC_VERSION

DISTROS=(debian-12 debian-13 ubuntu-24.04 ubuntu-26.04 alpine-3.24)
NEW_DISTROS=(almalinux-9 opensuse-tumbleweed opencloudos-9 archlinux kalinethunter void)

D_NAME[debian-12]="Debian";        D_VERSION[debian-12]="12";    D_RELEASE[debian-12]=bookworm
D_FAMILY[debian-12]=deb;           D_PM[debian-12]=apt
D_MIRROR[debian-12]="http://deb.debian.org/debian"
D_COMPONENTS[debian-12]="main,contrib,non-free,non-free-firmware"
D_KEYRING[debian-12]="/usr/share/keyrings/debian-archive-keyring.gpg"

D_NAME[debian-13]="Debian";        D_VERSION[debian-13]="13";    D_RELEASE[debian-13]=trixie
D_FAMILY[debian-13]=deb;           D_PM[debian-13]=apt
D_MIRROR[debian-13]="http://deb.debian.org/debian"
D_COMPONENTS[debian-13]="main,contrib,non-free,non-free-firmware"
D_KEYRING[debian-13]="/usr/share/keyrings/debian-archive-keyring.gpg"

D_NAME[ubuntu-24.04]="Ubuntu";     D_VERSION[ubuntu-24.04]="24.04"; D_RELEASE[ubuntu-24.04]=noble
D_FAMILY[ubuntu-24.04]=deb;        D_PM[ubuntu-24.04]=apt
D_MIRROR[ubuntu-24.04]="http://archive.ubuntu.com/ubuntu"
D_COMPONENTS[ubuntu-24.04]="main,restricted,universe,multiverse"
D_KEYRING[ubuntu-24.04]="/usr/share/keyrings/ubuntu-archive-keyring.gpg"

D_NAME[ubuntu-26.04]="Ubuntu";     D_VERSION[ubuntu-26.04]="26.04"; D_RELEASE[ubuntu-26.04]=resolute
D_FAMILY[ubuntu-26.04]=deb;        D_PM[ubuntu-26.04]=apt
D_MIRROR[ubuntu-26.04]="http://archive.ubuntu.com/ubuntu"
D_COMPONENTS[ubuntu-26.04]="main,restricted,universe,multiverse"
D_KEYRING[ubuntu-26.04]="/usr/share/keyrings/ubuntu-archive-keyring.gpg"

D_NAME[alpine-3.24]="Alpine";      D_VERSION[alpine-3.24]="3.24";  D_RELEASE[alpine-3.24]=v3.24
D_FAMILY[alpine-3.24]=alpine;      D_PM[alpine-3.24]=apk
D_MIRROR[alpine-3.24]="https://dl-cdn.alpinelinux.org/alpine"

# ---- 以下为 2026-11 新增的六个 ----
# AlmaLinux / openSUSE：从 LXC 官方镜像服务器拿现成的 rootfs.tar.xz（arm64 + amd64 都有）
D_NAME[almalinux-9]="AlmaLinux";            D_VERSION[almalinux-9]="9"
D_FAMILY[almalinux-9]=lxc;                  D_PM[almalinux-9]=dnf
D_LXC_PROJECT[almalinux-9]=almalinux;       D_LXC_VERSION[almalinux-9]=9

D_NAME[opensuse-tumbleweed]="openSUSE";     D_VERSION[opensuse-tumbleweed]="tumbleweed"
D_FAMILY[opensuse-tumbleweed]=lxc;          D_PM[opensuse-tumbleweed]=zypper
D_LXC_PROJECT[opensuse-tumbleweed]=opensuse; D_LXC_VERSION[opensuse-tumbleweed]=tumbleweed

# OpenCloudOS：官方只给 docker save 包，展开它的 layer.tar 才是 rootfs
D_NAME[opencloudos-9]="OpenCloudOS";        D_VERSION[opencloudos-9]="9"
D_FAMILY[opencloudos-9]=dockersave;         D_PM[opencloudos-9]=dnf

# Arch / Kali / Void：官方直接给 rootfs 压缩包，下下来解压即可
D_NAME[archlinux]="Arch Linux";             D_VERSION[archlinux]="aarch64"
D_FAMILY[archlinux]=tarball;                D_PM[archlinux]=pacman
D_ARCHES[archlinux]="arm64"                 # ArchLinuxARM 只有 aarch64；x86 版是 .tar.zst，应用不支持

D_NAME[kalinethunter]="Kali NetHunter";     D_VERSION[kalinethunter]="current"
D_FAMILY[kalinethunter]=tarball;            D_PM[kalinethunter]=apt

D_NAME[void]="Void Linux";                  D_VERSION[void]="current"
D_FAMILY[void]=tarball;                     D_PM[void]=xbps

# ---------------------------------------------------------------- 档位包清单
# min ⊂ base ⊂ dev（后面的档位会把前面的一起装上）
PKG_DEB_MIN="ca-certificates tzdata"
PKG_DEB_BASE="curl wget git less vim-tiny file jq tree htop unzip zip xz-utils procps psmisc iproute2 net-tools openssh-client gnupg bash-completion"
PKG_DEB_DEV="build-essential python3 python3-pip python3-venv python3-dev pkg-config libssl-dev zlib1g-dev libffi-dev cmake sqlite3"

PKG_ALPINE_MIN="ca-certificates tzdata"
PKG_ALPINE_BASE="bash curl wget git less vim nano file jq tree htop unzip zip xz procps psmisc iproute2 net-tools openssh-client gnupg bash-completion"
PKG_ALPINE_DEV="build-base python3 py3-pip py3-virtualenv python3-dev openssl-dev zlib-dev libffi-dev cmake sqlite"

# dnf：AlmaLinux(RHEL 系) / OpenCloudOS
# 注意 RHEL 系的包名和 Debian 不一样：procps-ng / iproute / openssh-clients / gnupg2
PKG_DNF_MIN="ca-certificates tzdata"
PKG_DNF_BASE="curl wget git less vim-minimal file jq tree htop unzip zip xz procps-ng psmisc iproute net-tools openssh-clients gnupg2 bash-completion"
PKG_DNF_DEV="gcc gcc-c++ make python3 python3-pip python3-devel openssl-devel zlib-devel libffi-devel cmake sqlite"

# zypper：openSUSE 的 openssl-devel 叫 libopenssl-devel，gpg 叫 gpg2，procps 不带 -ng
PKG_ZYPPER_MIN="ca-certificates timezone"
PKG_ZYPPER_BASE="curl wget git less vim file jq tree htop unzip zip xz gzip procps psmisc iproute2 net-tools openssh-clients gpg2 bash-completion"
PKG_ZYPPER_DEV="gcc gcc-c++ make python3 python3-pip python3-devel libopenssl-devel zlib-devel libffi-devel cmake sqlite3"

# pacman：Arch 基础镜像已经自带 coreutils/file/less/procps-ng/psmisc/iproute2，
# min 档不装东西（装了也只是把同一批包「重装」一遍，白花时间）
PKG_PACMAN_MIN=""
PKG_PACMAN_BASE="curl wget git less file jq tree htop unzip zip xz procps-ng psmisc iproute2 net-tools openssh gnupg bash-completion"
PKG_PACMAN_DEV="base-devel python python-pip python-virtualenv openssl zlib libffi cmake sqlite"

# xbps：Void 的 openssh 自带 client，base-devel 是元包
PKG_XBPS_MIN="ca-certificates tzdata"
PKG_XBPS_BASE="curl wget git less vim file jq tree htop unzip zip xz procps-ng psmisc iproute2 net-tools openssh gnupg bash-completion"
PKG_XBPS_DEV="base-devel python3 python3-pip python3-virtualenv python3-devel openssl-devel zlib-devel libffi-devel cmake sqlite"

pkgs_for() { # $1=pm $2=tier
  local pm="$1" tier="$2" min="" base="" dev=""
  case "$pm" in
    apt)    min="$PKG_DEB_MIN";    base="$PKG_DEB_BASE";    dev="$PKG_DEB_DEV" ;;
    apk)    min="$PKG_ALPINE_MIN"; base="$PKG_ALPINE_BASE"; dev="$PKG_ALPINE_DEV" ;;
    dnf)    min="$PKG_DNF_MIN";    base="$PKG_DNF_BASE";    dev="$PKG_DNF_DEV" ;;
    zypper) min="$PKG_ZYPPER_MIN"; base="$PKG_ZYPPER_BASE"; dev="$PKG_ZYPPER_DEV" ;;
    pacman) min="$PKG_PACMAN_MIN"; base="$PKG_PACMAN_BASE"; dev="$PKG_PACMAN_DEV" ;;
    xbps)   min="$PKG_XBPS_MIN";   base="$PKG_XBPS_BASE";   dev="$PKG_XBPS_DEV" ;;
    *) die "未知包管理器: $pm" ;;
  esac
  local out="$min"
  case "$tier" in
    min) : ;;
    base) out="$out $base" ;;
    dev)  out="$out $base $dev" ;;
    *) die "未知档位: $tier" ;;
  esac
  echo "$out" | tr -s ' ' | sed 's/^ //;s/ $//'
}

# ---------------------------------------------------------------- 小工具
log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror\033[0m %s\n' "$*" >&2; exit 1; }

host_arch() { case "$(uname -m)" in aarch64|arm64) echo arm64 ;; x86_64|amd64) echo amd64 ;; *) die "构建机架构不支持: $(uname -m)";; esac; }
arch_apk()  { case "$1" in arm64) echo aarch64 ;; amd64) echo x86_64 ;; esac; }
arch_lxc()  { case "$1" in arm64) echo arm64 ;; amd64) echo amd64 ;; esac; }
qemu_bin()  { case "$1" in arm64) echo qemu-aarch64-static ;; amd64) echo qemu-x86_64-static ;; esac; }
binfmt_magic() { case "$1" in arm64) echo qemu-aarch64 ;; amd64) echo qemu-x86_64 ;; esac; }

# binfmt 里注册的解释器绝对路径（新版 Ubuntu 是 /usr/libexec/qemu-binfmt/xxx-binfmt-P）
binfmt_interpreter() {
  local f="/proc/sys/fs/binfmt_misc/$(binfmt_magic "$1")"
  [ -r "$f" ] || return 0
  awk '/^interpreter /{print $2; exit}' "$f"
}

# 找一份能用的 qemu 静态二进制：PATH 里的优先，否则退回 binfmt 注册的那份
qemu_interpreter() {
  local q; q="$(qemu_bin "$1")"
  if command -v "$q" >/dev/null 2>&1; then command -v "$q"; return 0; fi
  local ip; ip="$(binfmt_interpreter "$1")"
  [ -n "$ip" ] && [ -x "$ip" ] && { echo "$ip"; return 0; }
  return 1
}

# mmdebstrap 只认 qemu-<arch>-static 这个名字；新版发行版包里可能只有
# /usr/libexec/qemu-binfmt/<arch>-binfmt-P，这里补一个软链哄它
ensure_qemu_static() {
  local q; q="$(qemu_bin "$1")"
  command -v "$q" >/dev/null 2>&1 && return 0
  local src; src="$(qemu_interpreter "$1")" || return 1
  mkdir -p /usr/local/bin
  ln -sf "$src" "/usr/local/bin/$q" 2>/dev/null || return 1
  hash -r
  command -v "$q" >/dev/null 2>&1
}

fetch() { # $1=url $2=输出文件
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    # --retry-all-errors 不能省：镜像常在传输中途掐连接，curl 默认不重试。
    # --speed-limit/--speed-time 也不能省：国内访问 dl-cdn.alpinelinux.org 这类源时，
    # 经常「连接建立成功、握手完成、然后每秒只有几 KB」，--connect-timeout 管不到这种，
    # 脚本就会无声无息地挂在那里。这里定成「连续 30 秒低于 1 KB/s 就放弃」，
    # 交给 --retry-all-errors 重试，重试完还不行就报错退出，不会一直吊着。
    # 1 KB/s 的阈值足够低，正常下载（哪怕几十 KB/s）不会被误杀。
    curl -fsSL --http1.1 --retry 5 --retry-all-errors --retry-delay 2 \
         --connect-timeout 20 --speed-limit 1024 --speed-time 30 \
         -A 'android-proot-rootfs/1.0' -o "$out" "$url" && return 0
    warn "curl 失败（网络中断或速度过低），改用 python3 重试"
  fi
  command -v python3 >/dev/null 2>&1 || die "下载失败：$url
  网络不通时试试 --mirror 换国内源，例如：
    Alpine  --mirror https://mirrors.tuna.tsinghua.edu.cn/alpine
    Ubuntu  --mirror http://mirrors.tuna.tsinghua.edu.cn/ubuntu"
  # python 的 urlopen(timeout=) 只管单次读写，管不住「慢速但不断」，外面再套一层 timeout
  timeout 900 python3 - "$url" "$out" <<'PY'
import sys, urllib.request
url, out = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={"User-Agent": "android-proot-rootfs/1.0"})
with urllib.request.urlopen(req, timeout=60) as r, open(out, "wb") as f:
    while True:
        b = r.read(1 << 16)
        if not b: break
        f.write(b)
PY
}

# 抓一个网页到 stdout（用来解析目录列表），失败返回 1
fetch_text() { # $1=url
  local t; t="$(mktemp)"
  if fetch "$1" "$t" 2>/dev/null; then cat "$t"; rm -f "$t"; return 0; fi
  rm -f "$t"; return 1
}

# 带缓存的下载：同一个 rootfs 在 min/base/dev 三档之间只下一次
fetch_cached() { # $1=url $2=缓存文件名
  local url="$1" name="$2"
  # 必须分两条 local 写：同一条 local 里的 $name 在展开时还看不到这条语句刚声明的 name，
  # 会按 bash 的动态作用域去取值 —— 调用者刚好没设 name 时 set -u 就报「未绑定变量」
  local dst="$CACHE/$name"
  mkdir -p "$CACHE"
  if [ -s "$dst" ]; then ok "用缓存 $name（$(du -h "$dst" | cut -f1)）"; return 0; fi
  log "下载 $name"
  fetch "$url" "$dst.part" || { rm -f "$dst.part"; die "下载失败：$url"; }
  mv "$dst.part" "$dst"
  ok "下载完成 $(du -h "$dst" | cut -f1)"
}

# ---------------------------------------------------------------- 各来源的取包
# 1) LXC 镜像服务器（官方 / 清华镜像，路径完全相同）：每天一个新目录
#    镜像站同步比官方慢，最新的几个目录常常「目录在、rootfs.tar.xz 还没到」，
#    所以从新到旧挨个探，取第一个完整的。
lxc_dates() { # $1=project $2=version $3=lxcarch —— 输出全部日期，新的在前
  { fetch_text "$LXC_BASE/$1/$2/$3/default/" || true; } \
    | grep -oE 'href="[0-9]{8}_[0-9]{2}(%3A|:)[0-9]{2}/"' \
    | sed 's/^href="//; s|/"$||; s|/$||' \
    | sort -r
}

lxc_probe() { # $1=url —— 只探是否存在，不下整个文件
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --http1.1 --connect-timeout 15 --max-time 30 -r 0-0 \
       -A 'android-proot-rootfs/1.0' -o /dev/null "$1" 2>/dev/null \
  || curl -fsSI --http1.1 --connect-timeout 15 --max-time 30 \
       -A 'android-proot-rootfs/1.0' "$1" >/dev/null 2>&1
}

lxc_rootfs() { # $1=out
  local out="$1" proj ver lac d base want have name rest cand
  proj="${D_LXC_PROJECT[$DISTRO]}"; ver="${D_LXC_VERSION[$DISTRO]}"
  lac="$(arch_lxc "$ARCH")"
  rest="$(lxc_dates "$proj" "$ver" "$lac" | head -6)"
  [ -n "$rest" ] || die "取不到 $proj/$ver/$lac 的镜像日期目录（网络？站点改版？）"

  d=""; base=""
  for cand in $rest; do
    if lxc_probe "$LXC_BASE/$proj/$ver/$lac/default/$cand/rootfs.tar.xz"; then
      d="$cand"; base="$LXC_BASE/$proj/$ver/$lac/default/$cand"; break
    fi
    warn "$proj/$ver/$lac @ $cand 还没同步完（rootfs.tar.xz 404），往前退一天"
  done
  [ -n "$d" ] || die "$proj/$ver/$lac 最近 6 个日期目录都没有 rootfs.tar.xz
  镜像站同步有延迟，过几小时再跑；或换源试试 --lxc-mirror"

  VER="$ver-$(echo "$d" | sed 's/%3A/:/')"
  log "LXC 镜像 $proj/$ver/$lac @ $d（源 $LXC_BASE）"

  name="lxc-$proj-$ver-$lac-$d.tar.xz"
  fetch_cached "$base/rootfs.tar.xz" "$name"

  want="$(fetch_text "$base/SHA256SUMS" | awk '$2=="rootfs.tar.xz"{print $1}')"
  have="$(sha256sum "$CACHE/$name" | awk '{print $1}')"
  if [ -n "$want" ]; then
    [ "$want" = "$have" ] || die "LXC rootfs 校验失败（下载被截断？）"
    ok "SHA256 校验通过"
  else
    warn "拿不到 SHA256SUMS，跳过校验"
  fi

  tar -xf "$CACHE/$name" -C "$out"
}

# 2) 官方直接给的 rootfs 压缩包
tarball_url() { # $1=arch  → 输出 url
  # 取包根：--tarball-mirror 给了就用它，否则用该发行版的官方根
  case "$DISTRO" in
    archlinux)
      case "$1" in
        arm64) echo "${TARBALL_MIRROR:-$ARCH_BASE}/os/ArchLinuxARM-aarch64-latest.tar.gz" ;;
        *) die "Arch 只有 arm64（x86 版是 .tar.zst，应用不认）" ;;
      esac ;;
    kalinethunter)
      # minimal 比 nano 小（120MB vs 170MB），full 是 1.7GB 的大全
      case "$1" in
        arm64) echo "${TARBALL_MIRROR:-$KALI_BASE}/nethunter-images/current/rootfs/kali-nethunter-rootfs-minimal-arm64.tar.xz" ;;
        amd64) echo "${TARBALL_MIRROR:-$KALI_BASE}/nethunter-images/current/rootfs/kali-nethunter-rootfs-minimal-amd64.tar.xz" ;;
      esac ;;
    void)
      local a name base
      base="${TARBALL_MIRROR:-$VOID_BASE}"; base="${base%/}"
      case "$1" in arm64) a=aarch64 ;; amd64) a=x86_64 ;; esac
      # 只取 glibc 版：musl 版能装，但 pip 装包时 wheel 覆盖率差很多
      name="$(fetch_text "$base/live/current/" \
              | grep -oE "void-$a-ROOTFS-[0-9]{8}\.tar\.xz" | sort -u | tail -1)"
      [ -n "$name" ] || die "取不到 Void $a 的 ROOTFS 文件名（源 $base/live/current/）"
      echo "$base/live/current/$name" ;;
  esac
}

tarball_rootfs() { # $1=out
  local out="$1" url name
  url="$(tarball_url "$ARCH")"
  name="$(basename "$url")"
  case "$DISTRO" in
    void)      VER="${name#void-*-ROOTFS-}"; VER="${VER%.tar.xz}" ;;
    archlinux) VER="${name#ArchLinuxARM-}"; VER="${VER%-latest.tar.gz}" ;;
  esac
  log "$DISTRO 官方 rootfs：$name"
  fetch_cached "$url" "$name"
  tar -xf "$CACHE/$name" -C "$out"
}

# 3) docker save 格式（opencloudos）：外层是 OCI/docker 打包，里面 */layer.tar 才是 rootfs
dockersave_rootfs() { # $1=out
  local out="$1" a base d f tmp layer want have
  case "$ARCH" in arm64) a=aarch64 ;; amd64) a=x86_64 ;; esac
  base="https://mirrors.opencloudos.tech/opencloudos/$D_VERSION_MAJOR/images/docker/$a"

  d="$(fetch_text "$base/" | grep -oE '>[0-9]{8}\.[0-9]+/' | tr -d '>/' | sort | tail -1)"
  [ -n "$d" ] || die "取不到 OpenCloudOS $a 的镜像目录（mirrors.opencloudos.tech 打不开？）"
  f="$(fetch_text "$base/$d/" | grep -oE "OpenCloudOS-Container-Minimal-[^\"<]+\.$a\.tar\.xz" | sort -u | head -1)"
  [ -n "$f" ] || die "取不到 OpenCloudOS Minimal $a 的包名"

  VER="${f#OpenCloudOS-Container-Minimal-}"; VER="${VER%.$a.tar.xz}"
  log "OpenCloudOS $VER（docker save 格式，稍后展开 layer.tar）"

  fetch_cached "$base/$d/$f" "$f"
  want="$(fetch_text "$base/$d/$f.sha256" | awk '{print $1}' | head -1)"
  have="$(sha256sum "$CACHE/$f" | awk '{print $1}')"
  if [ -n "$want" ]; then
    [ "$want" = "$have" ] || die "OpenCloudOS 包校验失败"
    ok "SHA256 校验通过"
  fi

  tmp="$(mktemp -d)"
  tar -xf "$CACHE/$f" -C "$tmp" --wildcards '*/layer.tar' || { rm -rf "$tmp"; die "解不出 layer.tar"; }
  layer="$(find "$tmp" -name layer.tar -print -quit)"
  [ -n "$layer" ] || { rm -rf "$tmp"; die "docker save 包里没有 layer.tar"; }
  log "展开 layer.tar（$(du -h "$layer" | cut -f1)）"
  tar -xf "$layer" -C "$out"
  rm -rf "$tmp"
}

# ---------------------------------------------------------------- chroot 辅助
MOUNTED=()
chroot_cleanup() {
  local i m
  for ((i=${#MOUNTED[@]}-1;i>=0;i--)); do
    m="${MOUNTED[i]}"
    # --bind /dev 会带进来 pts/mqueue/shm/hugepages 这些嵌套挂载，
    # 单个 umount 会 EBUSY，必须先递归（-R）；再不行就惰性卸（-l）
    umount -R "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true
  done
  MOUNTED=()
  # 兜底：mount 可能"成功但没进数组"，或者 chroot 内部又挂了东西
  if [ -n "${WORK:-}" ] && [ -d "$WORK/root" ]; then
    for m in proc sys dev; do
      umount -R "$WORK/root/$m" 2>/dev/null || umount -l "$WORK/root/$m" 2>/dev/null || true
    done
  fi
}

# 删构建临时目录。里面的内核伪文件系统删不掉是正常的（proc/dev 里的东西不受 rm 管），
# 但绝不能因此刷一屏 "不允许的操作 / 设备或资源忙" 吓人，所以先卸再删、报错全吞掉。
# ⚠️ 更关键：$WORK/root/dev 曾经 mount --bind 到宿主的 /dev，两者是同一批 inode。
#    只要还有挂载残留就 rm，等于在删宿主机的 /dev/null 之类的设备节点。
#    所以删之前必须逐个确认没挂着，有一个没卸掉就整个放弃。
rm_work() {
  chroot_cleanup
  [ -d "${WORK:-}" ] || return 0
  local m left=""
  for m in proc sys dev; do
    [ -e "$WORK/root/$m" ] || continue
    if mountpoint -q "$WORK/root/$m" 2>/dev/null; then left="$left $m"; fi
  done
  if [ -n "$left" ]; then
    warn "$WORK/root 里的挂载点（$left）没卸干净，为安全起见不删这个目录"
    warn "（继续删会连带删掉宿主机的 /dev/*）。手动清：sudo umount -R $WORK/root && sudo rm -rf $WORK"
    return 1
  fi
  rm -rf "$WORK" 2>/dev/null || true
  if [ -d "$WORK" ]; then
    warn "$WORK 还有残留，手动清：sudo rm -rf $WORK"
  fi
}

# 交叉构建时把 qemu 放进 rootfs（必须在 mount 之前做）
chroot_install_qemu() { # $1=root
  QDST=""
  [ "$ARCH" = "$(host_arch)" ] && return 0
  local qsrc ipath
  qsrc="$(qemu_interpreter "$ARCH")" || die "找不到 qemu 解释器：sudo apt install qemu-user-binfmt-hwe"
  # 必须放到 binfmt 注册的那个路径上：chroot 之后内核是按这个路径去找解释器的
  ipath="$(binfmt_interpreter "$ARCH")"
  [ -n "$ipath" ] || ipath="/usr/bin/$(basename "$qsrc")"
  mkdir -p "$1$(dirname "$ipath")"
  cp "$qsrc" "$1$ipath"
  QDST="$1$ipath"
}

chroot_prepare() { # $1=root
  local root="$1"
  mkdir -p "$root/proc" "$root/dev" "$root/sys"
  mount -t proc none "$root/proc" 2>/dev/null && MOUNTED+=("$root/proc") || true
  mount --bind /dev "$root/dev"   2>/dev/null && MOUNTED+=("$root/dev")  || true
  mount --bind /sys "$root/sys"   2>/dev/null && MOUNTED+=("$root/sys")  || true

  # 某些受限环境 mount 会"假成功"但把 chroot 弄坏，探一下
  if ! chroot "$root" /bin/true 2>/dev/null; then
    warn "挂载后 chroot 不可用，卸掉重试"
    chroot_cleanup
    chroot "$root" /bin/true 2>/dev/null || die "chroot 不可用（换真机 / sudo -i 重试）"
  fi
}

# 装包前先把 DNS 写好：zypper / dnf / pacman 没有可用 DNS 会直接死在第一秒
write_net_conf() { # $1=root
  local root="$1"
  rm -f "$root/etc/resolv.conf"
  printf '# generated by android-proot-rootfs\nnameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 223.5.5.5\noptions edns0 trust-ad\n' \
    > "$root/etc/resolv.conf"
  rm -f "$root/etc/hosts"
  printf '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n' > "$root/etc/hosts"
}

# ---------------------------------------------------------------- 装包
retry3() { # $* = 命令
  local i
  for i in 1 2 3; do
    "$@" && return 0
    [ "$i" = 3 ] && return 1
    warn "第 $i 次失败，5 秒后重试"
    sleep 5
  done
}

install_pkgs() { # $1=root $2=pm $3=tier
  local root="$1" pm="$2" tier="$3" pkgs
  pkgs="$(pkgs_for "$pm" "$tier")"
  if [ -z "$pkgs" ]; then ok "此档位无需额外装包（镜像已自带）"; return 0; fi
  log "装包（$pm / $tier）：$pkgs"

  case "$pm" in
    apt)
      chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive HOME=/root \
        /usr/bin/apt-get update -qq || warn "apt-get update 有警告，继续"
      retry3 chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive HOME=/root \
        /usr/bin/apt-get install -y --no-install-recommends $pkgs \
        || die "apt-get install 失败"
      ;;
    apk)
      # 网络抖动时 apk 不重试，这里重试 3 次
      retry3 chroot "$root" /sbin/apk add --no-cache $pkgs || die "apk add 失败"
      ;;
    dnf)
      # RHEL 系各家的仓库组合不一样：AlmaLinux 9 的 BaseOS/AppStream/Extras 里就没有 htop
      # （htop 由 EPEL 提供）。一次传全部包名时，只要有一个 "No match for argument"，
      # 整个 dnf 事务就失败回滚 —— wget / git / jq 这些本来能装的也一个都装不上。
      # 所以失败后把报错点名的包剔掉重来，最多 3 轮；剔完还失败就是真错误。
      local logf="$CACHE/.dnf-$DISTRO-$ARCH.log" want="$pkgs" keep="" p round=0 dropped=""
      mkdir -p "$CACHE"
      while :; do
        round=$((round + 1))
        # 输出同时进终端和日志：dnf 的下载进度条要看得见，失败原因又要能解析
        if chroot "$root" /usr/bin/env HOME=/root LC_ALL=C \
             /usr/bin/dnf -y --setopt=install_weak_deps=False install $want \
             2>&1 | tee "$logf"; then
          break
        fi
        keep=""
        for p in $want; do
          if grep -qxF "No match for argument: $p" "$logf"; then dropped="$dropped $p"
          else keep="$keep $p"; fi
        done
        if [ "$(echo $keep)" = "$want" ]; then   # keep 拼接带前导空格，必须规范化后比
          # 不是包名不存在，多半是网络抖动，原样重试
          warn "失败原因不是包名不存在，重试一次"
          retry3 chroot "$root" /usr/bin/env HOME=/root LC_ALL=C \
            /usr/bin/dnf -y --setopt=install_weak_deps=False install $want \
            || { sed -n '/^Error/,+3p' "$logf" >&2 || true; die "dnf 装包失败"; }
          break
        fi
        if [ "$round" -ge 3 ]; then
          sed -n '/^Error/,+3p' "$logf" >&2 || true
          die "dnf 装包失败（已剔除 3 轮仍失败）"
        fi
        warn "$DISTRO 的仓库里没有：$(echo $dropped | sed 's/^ //')，剔除后重试"
        want="$keep"
        if [ -z "$want" ]; then warn "清单里的包这个发行版都没有"; break; fi
      done
      if [ -n "$dropped" ]; then
        warn "最终没有装的包（该发行版仓库未提供）：$(echo $dropped | sed 's/^ //')"
      fi
      ;;
    zypper)
      # Tumbleweed 是滚动版，zypper 会顺带升级依赖，这是它的正常行为。
      # 三个坑：
      #  1) --no-recommends 是 install 的「命令选项」，必须写在 install 之后，
      #     放前面会被当全局选项，报 "The flag --no-recommends is not known"。
      #  2) --non-interactive 下只要有一个包名不存在，zypper 就整体中止（返回 104），
      #     其余包一个都不装 —— 和 dnf 一样，失败后把报错点名的包剔掉重来。
      #  3) 容器镜像里的 keyring 有时比仓库签名旧，会报 Signature verification failed，
      #     这时降级到 --no-gpg-checks 重试一次。
      local logf="$CACHE/.zypper-$DISTRO-$ARCH.log" want="$pkgs" keep="" p round=0 dropped=""
      local gpg="--gpg-auto-import-keys"
      mkdir -p "$CACHE"
      while :; do
        round=$((round + 1))
        if chroot "$root" /usr/bin/env HOME=/root LC_ALL=C \
             /usr/bin/zypper --non-interactive $gpg install --no-recommends $want \
             2>&1 | tee "$logf"; then
          break
        fi
        if [ "$gpg" = "--gpg-auto-import-keys" ] && grep -q 'Signature verification failed' "$logf"; then
          warn "仓库签名校验失败，降级到 --no-gpg-checks 重试（镜像来自 LXC 官方源，非第三方）"
          gpg="--no-gpg-checks"
          round=$((round - 1))
          continue
        fi
        keep=""
        for p in $want; do
          if grep -qE "'$p' not found in package names|No provider of '$p' found" "$logf"; then
            dropped="$dropped $p"
          else keep="$keep $p"; fi
        done
        if [ "$(echo $keep)" = "$want" ]; then   # keep 拼接带前导空格，必须规范化后比
          # 不是包名不存在，多半是网络抖动，原样重试一次
          warn "失败原因不是包名不存在，重试一次"
          chroot "$root" /usr/bin/env HOME=/root LC_ALL=C \
            /usr/bin/zypper --non-interactive $gpg install --no-recommends $want \
            || { sed -n '/^Error/,+2p' "$logf" >&2 || true; die "zypper 装包失败"; }
          break
        fi
        if [ "$round" -ge 3 ]; then
          sed -n '/^Error/,+2p' "$logf" >&2 || true
          die "zypper 装包失败（已剔除 3 轮仍失败）"
        fi
        warn "$DISTRO 的仓库里没有：$(echo $dropped | sed 's/^ //')，剔除后重试"
        want="$keep"
        if [ -z "$want" ]; then warn "清单里的包这个发行版都没有"; break; fi
      done
      if [ -n "$dropped" ]; then
        warn "最终没有装的包（该发行版仓库未提供）：$(echo $dropped | sed 's/^ //')"
      fi
      ;;
    pacman)
      # Arch 的 rootfs 是某个时间点的快照，keyring 可能已经过期，所以装包前先 -Sy。
      #
      # 但 2024 年之后的 pacman（7.0+）还有第二道坎：下载默认在沙箱里跑 ——
      # 切到 alpm 用户、用 Landlock 把它限制成只能写 cachedir。我们的构建环境是
      # chroot（可能还套 proot / qemu），于是：
      #   error: restricting filesystem access failed because Landlock is not supported by the kernel!
      #   error: switching to sandbox user 'alpm' failed!
      #   error: could not determine cachedir mount point /var/cache/pacman/pkg/download-XXXX
      #   error: failed to commit transaction (not enough free disk space)
      # 后两条是前两条的连带（它算不出缓存目录挂在哪，就归类成空间不足），
      # 并不是真的没空间。直接关掉沙箱即可，顺手把 CheckSpace 也关掉。
      #
      # DisableSandbox 是 pacman 7.0 才有的选项，老版本写了会报
      # "directive 'DisableSandbox' in section 'options' not recognized" 然后直接退出，
      # 所以写完用 pacman-conf 验一遍（它就是 pacman.conf 的解析器），解析不过就撤掉。
      chroot "$root" /usr/bin/env HOME=/root /bin/sh -c '
        conf=/etc/pacman.conf
        [ -f "$conf" ] || exit 0
        # 官方 pacman.conf 里它是注释掉的一行（#DisableSandbox），先试着取消注释；
        # 没有这行（ArchLinuxARM 的模板可能更老）就在 [options] 下补一行。
        if grep -qE "^#?DisableSandbox" "$conf"; then
          sed -i "s/^#*DisableSandbox.*/DisableSandbox/" "$conf"
        else
          sed -i "/^\[options\]/a DisableSandbox" "$conf"
        fi
        sed -i "s/^CheckSpace/#CheckSpace/" "$conf"
        # 万一这个 pacman 还不认识 DisableSandbox（7.0 以前），写了会让它直接退出，
        # 所以用 pacman-conf（pacman.conf 的解析器）验一遍，解析不过就撤掉。
        if [ -x /usr/bin/pacman-conf ] && ! /usr/bin/pacman-conf >/dev/null 2>&1; then
          sed -i "/^DisableSandbox/d" "$conf"
          echo "warn: 这个 pacman 不认识 DisableSandbox，已撤回" >&2
        fi
      ' || warn "改 pacman.conf 失败，按原样继续"

      chroot "$root" /usr/bin/env HOME=/root /usr/bin/pacman -Sy --noconfirm || true

      # 和 dnf / zypper 一样：仓库里没有的包会让 pacman 整批中止
      # （error: target not found: xxx），其余包一个都不装。失败后把点名的包剔掉重来。
      local logf="$CACHE/.pacman-$DISTRO-$ARCH.log" want="$pkgs" keep="" p round=0 dropped="" keyring=0
      mkdir -p "$CACHE"
      while :; do
        round=$((round + 1))
        if chroot "$root" /usr/bin/env HOME=/root LC_ALL=C \
             /usr/bin/pacman -S --needed --noconfirm $want 2>&1 | tee "$logf"; then
          break
        fi
        # keyring 过期 / 未初始化是「一次性」问题，重建后重试，不占剔除轮次
        if [ "$keyring" -eq 0 ] && grep -qE "invalid or corrupted package|unknown trust|could not be looked up|PGP signature.*invalid" "$logf"; then
          keyring=1
          round=$((round - 1))
          warn "keyring 不可信，重建后重试"
          chroot "$root" /usr/bin/env HOME=/root /usr/bin/pacman-key --init || true
          chroot "$root" /usr/bin/env HOME=/root /usr/bin/pacman-key --populate archlinuxarm || true
          chroot "$root" /usr/bin/env HOME=/root /usr/bin/pacman -Sy --noconfirm || true
          continue
        fi
        keep=""
        for p in $want; do
          if grep -qxF "error: target not found: $p" "$logf"; then dropped="$dropped $p"
          else keep="$keep $p"; fi
        done
        if [ "$(echo $keep)" = "$want" ]; then   # keep 拼接带前导空格，必须规范化后比
          # 不是包名不存在，多半是网络抖动，原样重试一次
          warn "失败原因不是包名不存在，重试一次"
          chroot "$root" /usr/bin/env HOME=/root LC_ALL=C \
            /usr/bin/pacman -S --needed --noconfirm $want \
            || { sed -n '/^error/p' "$logf" | head -5 >&2 || true; die "pacman 装包失败"; }
          break
        fi
        if [ "$round" -ge 3 ]; then
          sed -n '/^error/p' "$logf" | head -5 >&2 || true
          die "pacman 装包失败（已剔除 3 轮仍失败）"
        fi
        warn "$DISTRO 的仓库里没有：$(echo $dropped | sed 's/^ //')，剔除后重试"
        want="$keep"
        if [ -z "$want" ]; then warn "清单里的包这个发行版都没有"; break; fi
      done
      if [ -n "$dropped" ]; then
        warn "最终没有装的包（该发行版仓库未提供）：$(echo $dropped | sed 's/^ //')"
      fi
      ;;
    xbps)
      # Void 的 rootfs 是某个时间点的快照，自带的 xbps 常比仓库里的旧。
      # 旧的 xbps 会拒装任何包，只丢一句 "The 'xbps' package must be updated"，
      # 所以先让它自我更新一次（-S 同步索引 / -u 更新 / -y 免确认）。
      # 另外换过 --tarball-mirror 的话，包仓库也改成同一台镜像：
      # 否则 rootfs 从清华下、装包又跑回官方源，等于没换。
      if [ -n "$TARBALL_MIRROR" ]; then
        local rc n=0
        for rc in "$root"/usr/share/xbps.d/*.conf "$root"/etc/xbps.d/*.conf; do
          [ -f "$rc" ] || continue
          if grep -q 'repo-default\.voidlinux\.org' "$rc"; then
            sed -i "s#https\?://repo-default\.voidlinux\.org#${TARBALL_MIRROR}#g" "$rc"
            n=$((n + 1))
          fi
        done
        if [ "$n" -gt 0 ]; then
          ok "xbps 仓库已指向 $TARBALL_MIRROR（改了 $n 个配置）"
        else
          warn "没找到写死 repo-default.voidlinux.org 的 xbps 配置，仓库保持原样"
        fi
      fi
      # 自我更新失败不当作致命：少数情况下旧 xbps 依然能装，让它继续试
      retry3 chroot "$root" /usr/bin/env HOME=/root /usr/bin/xbps-install -S -u -y xbps \
        || warn "xbps 自我更新失败，仍尝试装包"
      retry3 chroot "$root" /usr/bin/env HOME=/root /usr/bin/xbps-install -S -y $pkgs \
        || die "xbps 装包失败"
      ;;
    *) die "未知包管理器: $pm" ;;
  esac
  ok "装包完成"
}

# ---------------------------------------------------------------- 收尾
# 纯文件操作，不需要执行目标架构的二进制，交叉构建也安全
postprocess() { # $1=root $2=pm
  local root="$1" pm="$2"
  log "清理缓存与体积"

  # 各包管理器的下载缓存
  rm -rf "$root"/var/cache/apt/archives/*.deb 2>/dev/null || true
  rm -rf "$root"/var/cache/apt/*.bin 2>/dev/null || true
  rm -rf "$root"/var/lib/apt/lists/* 2>/dev/null || true
  rm -rf "$root"/var/cache/apk/* 2>/dev/null || true
  rm -rf "$root"/var/cache/dnf/* 2>/dev/null || true
  rm -rf "$root"/var/cache/yum/* 2>/dev/null || true
  rm -rf "$root"/var/cache/zypp/*/* 2>/dev/null || true
  rm -rf "$root"/var/cache/pacman/pkg/* 2>/dev/null || true
  rm -rf "$root"/var/cache/xbps/* 2>/dev/null || true
  rm -rf "$root"/var/log/* 2>/dev/null || true
  rm -rf "$root"/tmp/* "$root"/var/tmp/* 2>/dev/null || true
  rm -rf "$root"/usr/share/man/* "$root"/usr/share/info/* 2>/dev/null || true
  case "$pm" in
    apk|pacman|xbps) rm -rf "$root"/usr/share/doc/* "$root"/usr/share/locale/* 2>/dev/null || true ;;
  esac

  # /proc /sys /dev 由 proot 从宿主机绑进来，不能带内容；
  # 但如果是真挂载就先别删（会删到宿主机上）
  local d
  for d in proc sys dev; do
    if mountpoint -q "$root/$d" 2>/dev/null; then warn "$root/$d 仍是挂载状态，跳过"; continue; fi
    rm -rf "$root/$d"/* 2>/dev/null || true
  done

  : > "$root/etc/machine-id" 2>/dev/null || true

  # DNS 必须是普通文件：openSUSE 的 /etc/resolv.conf 是软链到 /run/netconfig/，
  # 在 proot 里解析不了，会让 apt/zypper/pacman 全部连不上网
  write_net_conf "$root"
  chmod 644 "$root/etc/resolv.conf" "$root/etc/hosts"

  # 同理，openSUSE 的 /etc/hostname 也可能是软链，先断开再写
  rm -f "$root/etc/hostname"
  echo "localhost" > "$root/etc/hostname"

  mkdir -p "$root/tmp" "$root/var/tmp" "$root/root" "$root/workspace"
  chmod 1777 "$root/tmp" "$root/var/tmp"
  chmod 700 "$root/root"
  chmod 755 "$root" "$root/workspace"

  # 有 bash 就把 root 的登录 shell 换过去
  if [ -x "$root/bin/bash" ] && [ -f "$root/etc/passwd" ]; then
    sed -i 's|^root:\([^:]*\):0:0:\([^:]*\):\([^:]*\):[^:]*$|root:\1:0:0:\2:\3:/bin/bash|' "$root/etc/passwd"
  fi

  if [ "$pm" = apt ]; then
    mkdir -p "$root/etc/default"
    echo "LANG=C.UTF-8" > "$root/etc/default/locale"
    # 装包时不要尝试拉起服务（proot 里没有 init）
    mkdir -p "$root/usr/sbin"
    printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
    chmod 755 "$root/usr/sbin/policy-rc.d"
    mkdir -p "$root/etc/apt/apt.conf.d"
    cat > "$root/etc/apt/apt.conf.d/99-android-proot" <<'APTEOF'
Acquire::Retries "5";
Acquire::Languages "none";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APTEOF
  else
    # systemd 系（openSUSE / Alma / OpenCloudOS / Arch / Void）读的是 locale.conf
    echo "LANG=C.UTF-8" > "$root/etc/locale.conf" 2>/dev/null || true
  fi

  # SELinux 的 relabel 标记在 proot 里没人处理，留着只会误导
  rm -f "$root/.autorelabel" 2>/dev/null || true

  cat > "$root/etc/android-proot-release" <<EOF
distro=$DISTRO
version=$VER
arch=$ARCH
tier=$TIER
built=$BUILT
EOF
  chmod 644 "$root/etc/android-proot-release"
  ok "收尾完成"
}

# ---------------------------------------------------------------- 打包 + 自检
fix_links() { # $1=root  修 proot(--link2symlink) 留下的绝对软链
  command -v python3 >/dev/null 2>&1 || { warn "缺 python3，跳过 link2symlink 修正"; return 0; }
  python3 - "$1" <<'PYFIX' || warn "link2symlink 修正失败，产物可能含坏链"
import os, sys
root = os.path.abspath(sys.argv[1])
renamed = {}
def newname(t):
    d, b = os.path.split(t)
    if b.startswith(".l2s."):
        b = b[len(".l2s."):]
    return os.path.join(d, "." + b + ".real")
def store(t):
    # 存储文件改名成正常名字；同一目标只改一次
    n = renamed.get(t)
    if n is None:
        n = newname(t)
        if os.path.lexists(n):
            os.remove(n)
        os.rename(t, n)
        renamed[t] = n
    return n
for dirpath, dirnames, filenames in os.walk(root):
    for name in list(dirnames) + filenames:
        p = os.path.join(dirpath, name)
        try:
            t = os.readlink(p)          # 不是软链就抛 OSError；不能用 islink()，
        except OSError:                 # 悬空链在 proot 下 lstat 会返回 EPERM
            continue
        if "/.l2s." not in t:
            continue
        abs_t = t if os.path.isabs(t) else os.path.normpath(os.path.join(dirpath, t))
        n = renamed.get(abs_t)          # 先查表：多个名字常共用一个存储，第一个
        if n is None:                   # 已经把它改名了，后面的不能再 lstat
            try:
                os.lstat(abs_t)         # 存储文件还在吗
            except OSError:
                continue                # 内容已经丢了，交给下面的清理
            n = store(abs_t)
        os.remove(p)
        os.symlink(os.path.relpath(n, dirpath), p)
orphan = 0
for dirpath, dirnames, filenames in os.walk(root):
    for name in list(dirnames) + filenames:
        if name.startswith(".l2s."):
            try:
                os.remove(os.path.join(dirpath, name)); orphan += 1
            except OSError:
                pass
print(f"修正 {len(renamed)} 组，清理 {orphan} 个残留", file=sys.stderr)
PYFIX
}

pack() { # $1=root $2=输出 $3=epoch
  local root="$1" out="$2" epoch="$3"
  local gz
  if command -v pigz >/dev/null 2>&1; then gz=(pigz -9 -n -p "$(nproc)" -c); else gz=(gzip -9 -n -c); fi
  mkdir -p "$(dirname "$out")"
  log "打包 $(basename "$out")（未压缩 $(du -sh "$root" 2>/dev/null | cut -f1)）"

  local tarargs=(--numeric-owner --owner=0 --group=0 --sort=name --mtime="@$epoch" --format=gnu)
  local terr; terr="$(mktemp)"

  # .l2s. 是 proot 独有的名字，正常的 dpkg/apk 永远不会产生，所以真机上这一步空转。
  # 但只要有就必须先修：否则 tar 会「成功」地把绝对软链原样打进包里（运行时全是坏链）。
  if find "$root" -name '.l2s.*' -print -quit 2>/dev/null | grep -q .; then
    log "修正 proot 的 link2symlink 残留（绝对软链 → 相对软链）"
    fix_links "$root"
  fi

  # 先用最严格的方式打一遍：真机上这就是全部逻辑，行为与引入 proot 兼容之前完全一致。
  # 只有真的撞上 proot 的 --link2symlink 残留（tar 报 Cannot stat/Cannot open）才降级：
  # 修一遍软链 → 加 --ignore-failed-read 重打 → 报出仍然缺了多少条目。
  if ! tar "${tarargs[@]}" -C "$root" -cf - . 2>"$terr" | "${gz[@]}" > "$out"; then
    if grep -qE "Cannot stat|Cannot open" "$terr" 2>/dev/null; then
      warn "打包遇到读不到的条目，按 proot 的 link2symlink 残留处理"
      fix_links "$root"
      tar "${tarargs[@]}" --ignore-failed-read -C "$root" -cf - . 2>"$terr" | "${gz[@]}" > "$out"
      local lost; lost="$(grep -cE "Cannot stat|Cannot open" "$terr" 2>/dev/null || true)"
      if [ "${lost:-0}" -gt 0 ]; then
        warn "二次打包仍跳过 $lost 个条目 —— 产物不完整，这个环境的 proot 丢了数据："
        grep -E "Cannot stat|Cannot open" "$terr" | head -5 >&2
      fi
    else
      rm -f "$terr"; die "打包失败（原因见上）"
    fi
  fi
  rm -f "$terr"
}

verify() { # $1=产物
  local f="$1"
  gzip -t "$f" 2>/dev/null || die "gzip 校验失败，包被截断：$f"

  local tf; tf="$(mktemp)"
  tar -tzf "$f" > "$tf" || { rm -f "$tf"; die "tar 列不出内容：$f"; }

  # 不能写 tar | grep -q：set -o pipefail 下 grep 提前退出会让上游吃 SIGPIPE(141)，
  # 明明匹配上了也会被当成失败。先落盘再 grep 最稳。
  if ! grep -qE '(^|/)bin/sh$' "$tf"; then
    printf '%s\n' '--- 包里前 10 条 ---' >&2
    head -10 "$tf" >&2
    printf '%s\n' '--- 含 bin/sh 的条目 ---' >&2
    grep -E 'bin/sh$' "$tf" | head -10 >&2 || true
    rm -f "$tf"
    die "缺少 bin/sh —— 应用会认为这不是可用 rootfs"
  fi

  # proot 的命令行是以 /usr/bin/env -i 开头的，没有它一条命令都跑不起来
  if ! grep -qE '(^|/)usr/bin/env$' "$tf"; then
    rm -f "$tf"
    die "缺少 /usr/bin/env —— 应用执行命令时起不来"
  fi

  # /etc/resolv.conf 必须是普通文件。注意不能拿 tar -tv 的 $NF 判断：
  # 软链那一行的最后一列是链接目标，不是文件名，$NF==... 永远不成立
  if tar -tvzf "$f" 2>/dev/null | grep -E '^l' | grep -qE 'etc/resolv\.conf'; then
    rm -f "$tf"
    die "/etc/resolv.conf 是软链，proot 里会 DNS 全挂"
  fi

  local n; n="$(wc -l < "$tf")"
  rm -f "$tf"
  ok "自检通过：$n 个条目，$(du -h "$f" | cut -f1)"
}

# ---------------------------------------------------------------- Alpine
build_alpine() { # $1=root
  local root="$1" apk_arch rel ver mini
  apk_arch="$(arch_apk "$ARCH")"
  rel="$RELEASE"
  ver="$(fetch_text "$MIRROR/$rel/releases/$apk_arch/" \
        | grep -oE "alpine-minirootfs-${rel#v}\.[0-9]+-${apk_arch}\.tar\.gz" \
        | sed -E "s/alpine-minirootfs-(.*)-${apk_arch}\.tar\.gz/\1/" | sort -V | tail -1)"
  [ -n "$ver" ] || die "取不到 Alpine $rel 的 minirootfs 版本"
  VER="$ver"

  mini="$WORK/minirootfs.tar.gz"
  log "Alpine $ver ($apk_arch) minirootfs"
  fetch "$MIRROR/$rel/releases/$apk_arch/alpine-minirootfs-$ver-$apk_arch.tar.gz" "$mini"
  fetch "$MIRROR/$rel/releases/$apk_arch/alpine-minirootfs-$ver-$apk_arch.tar.gz.sha256" "$mini.sha256"
  # 官方 .sha256 里写的是原始文件名，本地存成了 minirootfs.tar.gz，只能自己比
  local want have
  want="$(awk '{print $1}' "$mini.sha256" | head -1)"
  have="$(sha256sum "$mini" | awk '{print $1}')"
  [ "$want" = "$have" ] || die "minirootfs 校验失败（下载被截断？）"
  ok "minirootfs 校验通过"

  tar -xzf "$mini" -C "$root"

  mkdir -p "$root/etc/apk"
  printf '%s\n%s\n' "$MIRROR/$rel/main" "$MIRROR/$rel/community" > "$root/etc/apk/repositories"
  printf 'nameserver 1.1.1.1\nnameserver 223.5.5.5\n' > "$root/etc/resolv.conf"
  # 没有 IPv6 的网络里，DNS 往往先返回 AAAA，musl 的解析器会直接把 apk 判成
  # "DNS: transient error"（glibc 的 apt 不受影响）。把镜像的 IPv4 钉进 /etc/hosts，
  # apk 就只会看到可达的地址。getent 不存在时跳过，不影响正常网络。
  local mhost mip
  mhost="${MIRROR#*://}"; mhost="${mhost%%/*}"
  printf '127.0.0.1 localhost\n' > "$root/etc/hosts"
  if command -v getent >/dev/null 2>&1; then
    mip="$(getent ahostsv4 "$mhost" 2>/dev/null | awk 'NR==1{print $1}')"
    [ -n "$mip" ] && printf '%s %s\n' "$mip" "$mhost" >> "$root/etc/hosts"
  fi
  echo "alpine-minirootfs-$ver-$apk_arch" > "$root/etc/android-proot-base"
}

# ---------------------------------------------------------------- Debian/Ubuntu
build_deb() { # $1=root
  local root="$1"
  command -v mmdebstrap >/dev/null 2>&1 || die "缺 mmdebstrap：sudo apt install mmdebstrap"
  [ -f "$KEYRING" ] || die "缺 keyring $KEYRING：sudo apt install debian-archive-keyring ubuntu-keyring"

  local pkgs; pkgs="$(pkgs_for apt "$TIER")"
  log "mmdebstrap $RELEASE/$ARCH"
  log "包：$pkgs"

  # path-exclude 让 dpkg 在解包阶段就跳过文档，比装完再删干净；copyright 保留以满足分发合规
  mmdebstrap \
    --architectures="$ARCH" \
    --variant=minbase \
    --components="$COMPONENTS" \
    --include="$pkgs" \
    --keyring="$KEYRING" \
    --aptopt='Acquire::Languages "none"' \
    --aptopt='Acquire::Retries "5"' \
    --dpkgopt='path-exclude=/usr/share/doc/*' \
    --dpkgopt='path-include=/usr/share/doc/*/copyright' \
    --dpkgopt='path-exclude=/usr/share/man/*' \
    --dpkgopt='path-exclude=/usr/share/info/*' \
    --dpkgopt='path-exclude=/usr/share/locale/*' \
    --dpkgopt='path-include=/usr/share/locale/zh_CN/*' \
    --dpkgopt='path-include=/usr/share/locale/zh_TW/*' \
    "$RELEASE" "$root" "$MIRROR"
  ok "bootstrap 完成"
}

# ---------------------------------------------------------------- 单包
build_one() { # $1=distro $2=arch $3=tier
  DISTRO="$1"; ARCH="$2"; TIER="$3"
  [ -n "${D_NAME[$DISTRO]:-}" ] || die "没有这个发行版: $DISTRO"
  if [ -n "$TARBALL_MIRROR" ] && [ "${D_FAMILY[$DISTRO]}" != tarball ]; then
    warn "--tarball-mirror 对 $DISTRO 不生效（它不是 tarball 取包，用 --lxc-mirror 或 --mirror）"
  fi
  VER="${D_VERSION[$DISTRO]}"; RELEASE="${D_RELEASE[$DISTRO]:-}"
  FAMILY="${D_FAMILY[$DISTRO]}"; PM="${D_PM[$DISTRO]}"
  COMPONENTS="${D_COMPONENTS[$DISTRO]:-}"
  KEYRING="${D_KEYRING[$DISTRO]:-}"
  VERSION_MAJOR="${D_VERSION[$DISTRO]%%.*}"
  D_VERSION_MAJOR="$VERSION_MAJOR"

  # 有些发行版只有部分架构
  local supported="${D_ARCHES[$DISTRO]:-arm64 amd64}"
  case " $supported " in
    *" $ARCH "*) : ;;
    *) die "$DISTRO 不支持 $ARCH（支持：$supported）" ;;
  esac

  if [ -n "$MIRROR_ARG" ]; then MIRROR="$MIRROR_ARG"; else MIRROR="${D_MIRROR[$DISTRO]:-}"; fi
  # Ubuntu 的 arm64 包在 ubuntu-ports，不在主归档；按架构自动挑对
  if [ "$ARCH" != amd64 ] && [ "${D_NAME[$DISTRO]}" = "Ubuntu" ]; then
    case "$MIRROR" in
      *ports.ubuntu.com*|*ubuntu-ports*) : ;;
      *archive.ubuntu.com*) MIRROR="http://ports.ubuntu.com/ubuntu-ports"; warn "arm64 改用 $MIRROR" ;;
      */ubuntu) MIRROR="${MIRROR}-ports"; warn "arm64 改用 $MIRROR" ;;
    esac
  fi

  [ "$(id -u)" -eq 0 ] || die "需要 root：sudo ./build.sh ..."

  # 交叉构建检查：qemu 二进制或 binfmt 注册，有一样就够
  if [ "$ARCH" != "$(host_arch)" ]; then
    if ! qemu_interpreter "$ARCH" >/dev/null 2>&1; then
      die "交叉构建 $ARCH 需要 qemu：
  Ubuntu/Debian: sudo apt install qemu-user-binfmt-hwe     （老版本叫 qemu-user-static）
  装完确认：ls /proc/sys/fs/binfmt_misc/ | grep $(binfmt_magic "$ARCH")"
    fi
    ensure_qemu_static "$ARCH" || warn "没能建 qemu-$( [ "$ARCH" = arm64 ] && echo aarch64 || echo x86_64 )-static 软链，mmdebstrap 可能会报错"
  fi

  BUILT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local epoch; epoch="$(date -u -d "$BUILT" +%s)"

  CACHE="$PWD/.work/cache"
  WORK="$PWD/.work/$DISTRO-$ARCH-$TIER"
  local root="$WORK/root"
  rm_work || die "构建目录里还有没卸干净的挂载点，先按上面的提示手动清理再重跑"
  mkdir -p "$root"

  log "构建 ${D_NAME[$DISTRO]} $VER（$ARCH / $TIER）"

  trap chroot_cleanup EXIT

  case "$FAMILY" in
    deb)
      build_deb "$root"
      ;;
    alpine)
      build_alpine "$root"
      chroot_install_qemu "$root"
      chroot_prepare "$root"
      install_pkgs "$root" "$PM" "$TIER"
      ;;
    lxc)
      lxc_rootfs "$root"
      chroot_install_qemu "$root"
      write_net_conf "$root"
      chroot_prepare "$root"
      install_pkgs "$root" "$PM" "$TIER"
      ;;
    tarball)
      tarball_rootfs "$root"
      chroot_install_qemu "$root"
      write_net_conf "$root"
      chroot_prepare "$root"
      install_pkgs "$root" "$PM" "$TIER"
      ;;
    dockersave)
      dockersave_rootfs "$root"
      chroot_install_qemu "$root"
      write_net_conf "$root"
      chroot_prepare "$root"
      install_pkgs "$root" "$PM" "$TIER"
      ;;
    *) die "未知 family: $FAMILY" ;;
  esac

  chroot_cleanup
  [ -n "${QDST:-}" ] && rm -f "$QDST"

  postprocess "$root" "$PM"

  local name="$DISTRO-$ARCH-$TIER.tar.gz"
  local out="$PWD/out/$name"
  pack "$root" "$out" "$epoch"
  ( cd "$PWD/out" && sha256sum "$name" > "$name.sha256" )
  verify "$out"
  # sudo 构建出来的文件归 root，普通用户跑 make-index.py 时会 Permission denied
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    chown "$SUDO_USER": "$out" "$out.sha256" "$PWD/out" 2>/dev/null || true
  fi

  # proot 下残留的自指软链会让 rm -rf 返回非 0，别让它在成功之后把整个构建判成失败
  [ "${KEEP:-0}" -eq 1 ] || rm_work
  echo; ok "产物 out/$name（$(du -h "$out" | cut -f1)）"
}

# ---------------------------------------------------------------- 入口
MIRROR_ARG=""; KEEP=0; TARGETS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mirror) MIRROR_ARG="$2"; shift 2 ;;
    --lxc-mirror) LXC_BASE="${2%/}"; shift 2 ;;
    --tarball-mirror) TARBALL_MIRROR="${2%/}"; shift 2 ;;
    --keep)   KEEP=1; shift ;;
    all)      TARGETS=("${DISTROS[@]}" "${NEW_DISTROS[@]}"); shift ;;
    all-new|new-all) TARGETS=("${NEW_DISTROS[@]}"); shift ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

if [ ${#TARGETS[@]} -eq 0 ]; then
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 1
fi

if [ ${#TARGETS[@]} -ge 3 ] && [ -n "${D_NAME[${TARGETS[0]}]:-}" ]; then
  build_one "${TARGETS[0]}" "${TARGETS[1]}" "${TARGETS[2]}"
else
  # 多发行版模式：每个发行版按 ARCHES × TIERS 展开
  ARCHES="${ARCHES:-arm64 amd64}"
  TIERS="${TIERS:-min base dev}"
  [ -n "${ONLY_TIERS:-}" ] && TIERS="$ONLY_TIERS"
  for d in "${TARGETS[@]}"; do
    for a in $ARCHES; do
      for t in $TIERS; do
        build_one "$d" "$a" "$t" || warn "失败：$d $a $t"
      done
    done
  done
fi
