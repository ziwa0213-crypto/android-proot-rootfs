#!/usr/bin/env python3
"""扫描 out/ 里的 *.tar.gz，生成 index.json 和 docs/包清单.md。

    ./make-index.py
    ./make-index.py --tag 2026.11.01

产物名由 build.sh 决定：<发行版 ID>-<架构>-<档位>.tar.gz
发行版 ID 本身可能带版本（debian-12、ubuntu-26.04），也可能不带（archlinux、void、
kalinethunter），还可能是多段（opensuse-tumbleweed）。release tag 用的就是这个 ID。
"""
import argparse, hashlib, json, re, sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "ziwa0213-crypto/android-proot-rootfs"

FILE = re.compile(r"^(?P<id>.+?)-(?P<arch>arm64|amd64)-(?P<tier>min|base|dev)\.tar\.gz$")

# 顺序决定文档里的分组顺序；新增发行版记得也加进来
TITLES = {
    "debian": "Debian",
    "ubuntu": "Ubuntu",
    "alpine": "Alpine",
    "almalinux": "AlmaLinux",
    "opensuse": "openSUSE",
    "opencloudos": "OpenCloudOS",
    "archlinux": "Arch Linux",
    "kalinethunter": "Kali NetHunter",
    "void": "Void Linux",
}


def split_id(rid: str) -> tuple:
    """debian-12 → (debian, 12)；opensuse-tumbleweed → (opensuse, tumbleweed)；archlinux → (archlinux, '')"""
    for name in TITLES:
        if rid == name:
            return name, ""
        if rid.startswith(name + "-"):
            return name, rid[len(name) + 1:]
    head = rid.split("-")[0]
    return head, rid[len(head) + 1:]


def sha(path: Path) -> str:
    side = path.with_name(path.name + ".sha256")
    if side.is_file():
        return side.read_text().split()[0]
    h = hashlib.sha256()
    with path.open("rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def human(n: int) -> str:
    for u in ("B", "KB", "MB", "GB"):
        if n < 1024 or u == "GB":
            return f"{n:.0f} {u}" if u == "B" else f"{n:.1f} {u}"
        n /= 1024


def vkey(v: str) -> tuple:
    nums = tuple(int(x) for x in re.findall(r"\d+", v))
    return nums if nums else (0,)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="out")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()

    root = Path(a.dir)
    rows = []
    for f in sorted(root.glob("*.tar.gz")):
        m = FILE.match(f.name)
        if not m:
            print(f"跳过（名字不合规）: {f.name}", file=sys.stderr)
            continue
        rid = m["id"]
        distro, version = split_id(rid)
        st = f.stat()
        rows.append(dict(
            name=f.name, distro=distro, version=version, arch=m["arch"], tier=m["tier"],
            size=st.st_size, sha256=sha(f),
            url=f"https://github.com/{REPO}/releases/download/{rid}/{f.name}",
        ))
    if not rows:
        print("out/ 里没有产物", file=sys.stderr)
        return 1

    (root / "index.json").write_text(json.dumps({
        "schemaVersion": 1,
        "repo": REPO,
        "release": a.tag or None,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "packages": rows,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # (distro, version) → {(arch, tier): row}
    idx = {}
    for r in rows:
        idx.setdefault((r["distro"], r["version"]), {})[(r["arch"], r["tier"])] = r

    # 按 TITLES 的顺序排，未知发行版排最后
    def order(k):
        d, v = k
        return (list(TITLES).index(d) if d in TITLES else 999, vkey(v), v)

    L = ["# 包清单", "",
         "> 由 `make-index.py` 自动生成，不要手改。",
         f"> 生成时间：{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}", "",
         "## 体积", "",
         "| 发行版 | 架构 | min | base | dev |", "|---|---|---|---|---|"]
    for d, v in sorted(idx, key=order):
        label = f"{TITLES.get(d, d)} {v}".strip()
        for arch in ("arm64", "amd64"):
            cells = [human(idx[(d, v)][(arch, t)]["size"]) if (arch, t) in idx[(d, v)] else "—"
                     for t in ("min", "base", "dev")]
            if any(c != "—" for c in cells):
                L.append(f"| {label} | {arch} | " + " | ".join(cells) + " |")

    L += ["", "## 下载地址", "",
          "每个发行版一个 release，tag 就是文件名里的发行版 ID；重建时原地替换，链接永久有效。", ""]
    for r in rows:
        label = f"{TITLES.get(r['distro'], r['distro'])} {r['version']}".strip()
        L.append(f"- {label} / {r['arch']} / {r['tier']}（{human(r['size'])}）")
        L.append(f"  `{r['url']}`")

    L += ["", "## sha256", "", "| 文件 | sha256 |", "|---|---|"]
    for r in rows:
        L.append(f"| `{r['name']}` | `{r['sha256']}` |")

    Path("docs").mkdir(exist_ok=True)
    Path("docs/包清单.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"已生成 {root/'index.json'} 和 docs/包清单.md（{len(rows)} 个包）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
