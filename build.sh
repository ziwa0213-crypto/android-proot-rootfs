#!/usr/bin/env bash
#
# android-proot-rootfs 构建脚本（单文件版）
#
#   sudo ./build.sh <发行版> <架构> <档位>
#
#   发行版：debian-12 | debian-13 | ubuntu-24.04 | ubuntu-26.04 | alpine-3.24
#   架构  ：arm64 | amd64
#   档位  ：min | base | dev
#
#   例：sudo ./build.sh debian-12 arm64 base
#       sudo ./build.sh ubuntu-24.04 amd64 base --mirror http://mirrors.tuna.tsinghua.edu.cn/ubuntu
#
#   全部跑一遍：sudo ./build.sh all          （见文件末尾的矩阵定义）
#
set -euo pipefail

# ---------------------------------------------------------------- 发行版定义
# MIRROR 可被 --mirror 覆盖；国内建议清华/中科大，构建快 5~10 倍
declare -A D_NAME D_VERSION D_RELEASE D_FAMILY D_MIRROR D_COMPONENTS D_KEYRING

DISTROS=(debian-12 debian-13 ubuntu-24.04 ubuntu-26.04 alpine-3.24)

D_NAME[debian-12]="Debian";        D_VERSION[debian-12]="12";    D_RELEASE[debian-12]=bookworm
D_FAMILY[debian-12]=deb;           D_MIRROR[debian-12]="http://deb.debian.org/debian"
D_COMPONENTS[debian-12]="main,contrib,non-free,non-free-firmware"
D_KEYRING[debian-12]="/usr/share/keyrings/debian-archive-keyring.gpg"

D_NAME[debian-13]="Debian";        D_VERSION[debian-13]="13";    D_RELEASE[debian-13]=trixie
D_FAMILY[debian-13]=deb;           D_MIRROR[debian-13]="http://deb.debian.org/debian"
D_COMPONENTS[debian-13]="main,contrib,non-free,non-free-firmware"
D_KEYRING[debian-13]="/usr/share/keyrings/debian-archive-keyring.gpg"

D_NAME[ubuntu-24.04]="Ubuntu";     D_VERSION[ubuntu-24.04]="24.04"; D_RELEASE[ubuntu-24.04]=noble
D_FAMILY[ubuntu-24.04]=deb;        D_MIRROR[ubuntu-24.04]="http://archive.ubuntu.com/ubuntu"
D_COMPONENTS[ubuntu-24.04]="main,restricted,universe,multiverse"
D_KEYRING[ubuntu-24.04]="/usr/share/keyrings/ubuntu-archive-keyring.gpg"

D_NAME[ubuntu-26.04]="Ubuntu";     D_VERSION[ubuntu-26.04]="26.04"; D_RELEASE[ubuntu-26.04]=resolute
D_FAMILY[ubuntu-26.04]=deb;        D_MIRROR[ubuntu-26.04]="http://archive.ubuntu.com/ubuntu"
D_COMPONENTS[ubuntu-26.04]="main,restricted,universe,multiverse"
D_KEYRING[ubuntu-26.04]="/usr/share/keyrings/ubuntu-archive-keyring.gpg"

D_NAME[alpine-3.24]="Alpine";      D_VERSION[alpine-3.24]="3.24";  D_RELEASE[alpine-3.24]=v3.24
D_FAMILY[alpine-3.24]=alpine;      D_MIRROR[alpine-3.24]="https://dl-cdn.alpinelinux.org/alpine"

# ---------------------------------------------------------------- 档位包清单
# min ⊂ base ⊂ dev（后面的档位会把前面的一起装上）
PKG_DEB_MIN="ca-certificates tzdata"
PKG_DEB_BASE="curl wget git less vim-tiny file jq tree htop unzip zip xz-utils procps psmisc iproute2 net-tools openssh-client gnupg bash-completion"
PKG_DEB_DEV="build-essential python3 python3-pip python3-venv python3-dev pkg-config libssl-dev zlib1g-dev libffi-dev cmake sqlite3"

PKG_ALPINE_MIN="ca-certificates tzdata"
PKG_ALPINE_BASE="bash curl wget git less vim nano file jq tree htop unzip zip xz procps psmisc iproute2 net-tools openssh-client gnupg bash-completion"
PKG_ALPINE_DEV="build-base python3 py3-pip py3-virtualenv python3-dev openssl-dev zlib-dev libffi-dev cmake sqlite"

pkgs_for() { # $1=family $2=tier
  local fam="$1" tier="$2" out=""
  if [ "$fam" = deb ]; then
    out="$PKG_DEB_MIN"
    if [ "$tier" = base ] || [ "$tier" = dev ]; then out="$out $PKG_DEB_BASE"; fi
    if [ "$tier" = dev ]; then out="$out $PKG_DEB_DEV"; fi
  else
    out="$PKG_ALPINE_MIN"
    if [ "$tier" = base ] || [ "$tier" = dev ]; then out="$out $PKG_ALPINE_BASE"; fi
    if [ "$tier" = dev ]; then out="$out $PKG_ALPINE_DEV"; fi
  fi
  echo "$out" | tr -s ' ' | sed 's/^ //;s/ $//'
}

# ---------------------------------------------------------------- 小工具
log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror\033[0m %s\n' "$*" >&2; exit 1; }

host_arch() { case "$(uname -m)" in aarch64|arm64) echo arm64 ;; x86_64|amd64) echo amd64 ;; *) die "构建机架构不支持: $(uname -m)";; esac; }
arch_apk()  { case "$1" in arm64) echo aarch64 ;; amd64) echo x86_64 ;; esac; }
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
    # --retry-all-errors 不能省：镜像常在传输中途掐连接，curl 默认不重试
    curl -fsSL --http1.1 --retry 5 --retry-all-errors --retry-delay 2 \
         --connect-timeout 20 -A 'android-proot-rootfs/1.0' -o "$out" "$url" && return 0
    warn "curl 失败，改用 python3 重试"
  fi
  command -v python3 >/dev/null 2>&1 || die "下载失败：$url"
  python3 - "$url" "$out" <<'PY'
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

# ---------------------------------------------------------------- 收尾
# 纯文件操作，不需要执行目标架构的二进制，交叉构建也安全
postprocess() { # $1=root $2=family
  local root="$1" fam="$2"
  log "清理缓存与体积"

  rm -rf "$root"/var/cache/apt/archives/*.deb 2>/dev/null || true
  rm -rf "$root"/var/cache/apt/*.bin 2>/dev/null || true
  rm -rf "$root"/var/lib/apt/lists/* 2>/dev/null || true
  rm -rf "$root"/var/cache/apk/* 2>/dev/null || true
  rm -rf "$root"/var/log/* 2>/dev/null || true
  rm -rf "$root"/tmp/* "$root"/var/tmp/* 2>/dev/null || true
  rm -rf "$root"/usr/share/man/* "$root"/usr/share/info/* 2>/dev/null || true
  [ "$fam" = alpine ] && rm -rf "$root"/usr/share/doc/* "$root"/usr/share/locale/* 2>/dev/null || true

  # /proc /sys /dev 由 proot 从宿主机绑进来，不能带内容；
  # 但如果是真挂载就先别删（会删到宿主机上）
  local d
  for d in proc sys dev; do
    if mountpoint -q "$root/$d" 2>/dev/null; then warn "$root/$d 仍是挂载状态，跳过"; continue; fi
    rm -rf "$root/$d"/* 2>/dev/null || true
  done

  : > "$root/etc/machine-id"

  # DNS 必须是普通文件：发行版自带的 /etc/resolv.conf 常是软链到 127.0.0.53，
  # 在 proot 里解析不了，会导致 apt/git/pip 全部连不上网
  rm -f "$root/etc/resolv.conf"
  printf '# generated by android-proot-rootfs\nnameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 223.5.5.5\noptions edns0 trust-ad\n' \
    > "$root/etc/resolv.conf"
  chmod 644 "$root/etc/resolv.conf"

  echo "localhost" > "$root/etc/hostname"
  printf '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n' > "$root/etc/hosts"

  mkdir -p "$root/tmp" "$root/var/tmp" "$root/root" "$root/workspace"
  chmod 1777 "$root/tmp" "$root/var/tmp"
  chmod 700 "$root/root"
  chmod 755 "$root" "$root/workspace"

  if [ "$fam" = deb ]; then
    mkdir -p "$root/etc/default"
    echo "LANG=C.UTF-8" > "$root/etc/default/locale"

    # root 的登录 shell 换成 bash（有的话）
    if [ -x "$root/bin/bash" ] && [ -f "$root/etc/passwd" ]; then
      sed -i 's|^root:\([^:]*\):0:0:\([^:]*\):\([^:]*\):[^:]*$|root:\1:0:0:\2:\3:/bin/bash|' "$root/etc/passwd"
    fi

    # 装包时不要尝试拉起服务（proot 里没有 init）
    printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
    chmod 755 "$root/usr/sbin/policy-rc.d"

    mkdir -p "$root/etc/apt/apt.conf.d"
    cat > "$root/etc/apt/apt.conf.d/99-android-proot" <<'APTEOF'
Acquire::Retries "5";
Acquire::Languages "none";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APTEOF
  fi

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
pack() { # $1=root $2=输出 $3=epoch
  local root="$1" out="$2" epoch="$3"
  local gz
  if command -v pigz >/dev/null 2>&1; then gz=(pigz -9 -n -p "$(nproc)" -c); else gz=(gzip -9 -n -c); fi
  mkdir -p "$(dirname "$out")"
  log "打包 $(basename "$out")（未压缩 $(du -sh "$root" | cut -f1)）"
  # proot 的 --link2symlink 会把硬链接改写成「一份存储文件 + 一堆指向它的绝对软链」：
  #   usr/bin/.l2s.coreutils.dpkg-new0001   <- 存储，真内容（10 MB，114 个名字共用）
  #   usr/bin/coreutils        -> /abs/path/.../.l2s.coreutils.dpkg-new0001
  #   usr/lib/cargo/bin/coreutils/yes -> 同一个存储文件
  # 这些绝对链打进包里全是坏的；直接删存储文件又会丢内容（114 个名字共用它）。
  # 所以：把存储文件改名为 .<原名>.real，软链改写成树内相对路径，剩下的孤儿 .l2s.* 再删。
  if find "$root" -name '.l2s.*' -print -quit 2>/dev/null | grep -q .; then
    log "修正 proot 的 link2symlink 残留（绝对软链 → 相对软链）"
    python3 - "$root" <<'PYFIX' || warn "link2symlink 修正失败，产物可能含坏链"
import os, sys
root = os.path.abspath(sys.argv[1])
renamed = {}
def newname(t):
    d, b = os.path.split(t)
    if b.startswith(".l2s."):
        b = b[len(".l2s."):]
    return os.path.join(d, "." + b + ".real")
def store(p, t):
    # 把存储文件改名成正常名字，返回新路径；同一目标只改一次
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
        try:
            os.lstat(abs_t)             # 存储文件还在吗
        except OSError:
            continue                    # 内容已经丢了，交给下面的清理
        n = store(abs_t, abs_t)
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
  fi
  # proot 下偶有文件被 link2symlink 弄成悬空链，tar 遇到会非 0 退出；用 --ignore-failed-read
  # 保证包能出，但把丢掉的条目数报出来 —— 大于 0 就说明这个环境的 proot 不可信。
  local terr; terr="$(mktemp)"
  tar --numeric-owner --owner=0 --group=0 --sort=name --mtime="@$epoch" --format=gnu \
      --ignore-failed-read -C "$root" -cf - . 2>"$terr" | "${gz[@]}" > "$out"
  local lost; lost="$(grep -c "Cannot stat\|Cannot open" "$terr" 2>/dev/null || true)"
  [ "${lost:-0}" -eq 0 ] || warn "打包时跳过 $lost 个读不到的条目（proot 的 link2symlink 丢的），见下："
  [ "${lost:-0}" -eq 0 ] || head -5 "$terr" >&2
  rm -f "$terr"
}

verify() { # $1=产物
  local f="$1"
  gzip -t "$f" 2>/dev/null || die "gzip 校验失败，包被截断：$f"

  local list; list="$(tar -tzf "$f")"
  local tf; tf="$(mktemp)"
  printf '%s\n' "$list" > "$tf"

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

  local modes; modes="$(tar -tvzf "$f" | awk '$NF=="etc/resolv.conf"||$NF=="./etc/resolv.conf"{print $1}')"
  case "$modes" in l*) rm -f "$tf"; die "/etc/resolv.conf 是软链，proot 里会 DNS 全挂" ;; esac

  local n; n="$(wc -l < "$tf")"
  rm -f "$tf"
  ok "自检通过：$n 个条目，$(du -h "$f" | cut -f1)"
}

# ---------------------------------------------------------------- Alpine
build_alpine() { # $1=root
  local root="$1" apk_arch rel ver mini
  apk_arch="$(arch_apk "$ARCH")"
  rel="$RELEASE"
  ver="$(fetch "$MIRROR/$rel/releases/$apk_arch/" /dev/stdout \
        | grep -oE "alpine-minirootfs-${rel#v}\.[0-9]+-${apk_arch}\.tar\.gz" \
        | sed -E "s/alpine-minirootfs-(.*)-${apk_arch}\.tar\.gz/\1/" | sort -V | tail -1)"
  [ -n "$ver" ] || die "取不到 Alpine $rel 的 minirootfs 版本"

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

  mkdir -p "$root"
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

  local qdst=""
  if [ "$ARCH" != "$(host_arch)" ]; then
    local qsrc; qsrc="$(qemu_interpreter "$ARCH")" || die "找不到 qemu 解释器（apt install qemu-user-binfmt-hwe）"
    # 必须放到 binfmt 注册的那个路径上：chroot 之后内核是按这个路径去找解释器的
    local ipath; ipath="$(binfmt_interpreter "$ARCH")"
    [ -n "$ipath" ] || ipath="/usr/bin/$(basename "$qsrc")"
    mkdir -p "$root$(dirname "$ipath")"
    cp "$qsrc" "$root$ipath"
    qdst="$root$ipath"
  fi

  MOUNTED=()
  cleanup() { local i; for ((i=${#MOUNTED[@]}-1;i>=0;i--)); do umount "${MOUNTED[i]}" 2>/dev/null||true; done; MOUNTED=(); }
  trap cleanup EXIT

  mkdir -p "$root/proc" "$root/dev" "$root/sys"
  mount -t proc none "$root/proc" 2>/dev/null && MOUNTED+=("$root/proc") || true
  mount --bind /dev "$root/dev"   2>/dev/null && MOUNTED+=("$root/dev")  || true
  mount --bind /sys "$root/sys"   2>/dev/null && MOUNTED+=("$root/sys")  || true

  # 某些受限环境 mount 会"假成功"但把 chroot 弄坏，探一下
  if ! chroot "$root" /bin/true 2>/dev/null; then
    warn "挂载后 chroot 不可用，卸掉重试"
    cleanup
    chroot "$root" /bin/true 2>/dev/null || die "chroot 不可用（换真机 / sudo -i 重试）"
  fi

  local pkgs; pkgs="$(pkgs_for alpine "$TIER")"
  log "apk add --no-cache $pkgs"
  # 网络抖动时 apk 不重试，这里重试 3 次
  local i
  for i in 1 2 3; do
    chroot "$root" /sbin/apk add --no-cache $pkgs && break
    [ "$i" = 3 ] && die "apk add 失败"
    warn "apk add 第 $i 次失败，5 秒后重试"; sleep 5
  done
  ok "apk add 完成"

  cleanup
  [ -n "$qdst" ] && rm -f "$qdst"
  echo "alpine-minirootfs-$ver-$apk_arch" > "$root/etc/android-proot-base"
}

# ---------------------------------------------------------------- Debian/Ubuntu
build_deb() { # $1=root
  local root="$1"
  command -v mmdebstrap >/dev/null 2>&1 || die "缺 mmdebstrap：sudo apt install mmdebstrap"
  [ -f "$KEYRING" ] || die "缺 keyring $KEYRING：sudo apt install debian-archive-keyring ubuntu-keyring"

  local pkgs; pkgs="$(pkgs_for deb "$TIER")"
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
  VER="${D_VERSION[$DISTRO]}"; RELEASE="${D_RELEASE[$DISTRO]}"
  FAMILY="${D_FAMILY[$DISTRO]}"; COMPONENTS="${D_COMPONENTS[$DISTRO]:-}"
  KEYRING="${D_KEYRING[$DISTRO]:-}"
  if [ -n "$MIRROR_ARG" ]; then MIRROR="$MIRROR_ARG"; else MIRROR="${D_MIRROR[$DISTRO]}"; fi
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

  WORK="$PWD/.work/$DISTRO-$ARCH-$TIER"
  local root="$WORK/root"
  rm -rf "$WORK"; mkdir -p "$root"

  log "构建 ${D_NAME[$DISTRO]} $VER（$RELEASE）/ $ARCH / $TIER"

  case "$FAMILY" in
    deb)    build_deb "$root" ;;
    alpine) build_alpine "$root" ;;
    *) die "未知 family: $FAMILY" ;;
  esac

  postprocess "$root" "$FAMILY"

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
  [ "${KEEP:-0}" -eq 1 ] || rm -rf "$WORK" 2>/dev/null || true
  echo; ok "产物 out/$name（$(du -h "$out" | cut -f1)）"
}

# ---------------------------------------------------------------- 入口
MIRROR_ARG=""; KEEP=0; TARGETS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mirror) MIRROR_ARG="$2"; shift 2 ;;
    --keep)   KEEP=1; shift ;;
    all)      TARGETS=("${DISTROS[@]}"); shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

if [ ${#TARGETS[@]} -eq 0 ]; then
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1
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
