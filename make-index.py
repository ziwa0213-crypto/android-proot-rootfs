#!/usr/bin/env python3
"""扫描 out/ 里的 *.tar.gz，生成 index.json 和 docs/包清单.md。

    ./make-index.py
    ./make-index.py --tag 2026.11.01
"""
import argparse, hashlib, json, re, sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "ziwa0213-crypto/android-proot-rootfs"
NAME = re.compile(r"^(?P<distro>[a-z]+)-(?P<version>[0-9][0-9.]*)-(?P<arch>arm64|amd64)-(?P<tier>min|base|dev)\.tar\.gz$")
TITLES = {"debian": "Debian", "ubuntu": "Ubuntu", "alpine": "Alpine"}


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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="out")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()

    root = Path(a.dir)
    rows = []
    for f in sorted(root.glob("*.tar.gz")):
        m = NAME.match(f.name)
        if not m:
            print(f"跳过（名字不合规）: {f.name}", file=sys.stderr)
            continue
        st = f.stat()
        rows.append(dict(
            name=f.name, distro=m["distro"], version=m["version"], arch=m["arch"],
            tier=m["tier"], size=st.st_size, sha256=sha(f),
            url=f"https://github.com/{REPO}/releases/download/{m['distro']}-{m['version']}/{f.name}",
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

    idx = {(r["distro"], r["version"], r["arch"], r["tier"]): r for r in rows}
    order = [("debian", ["12", "13"]), ("ubuntu", ["24.04", "26.04"]), ("alpine", ["3.22"])]

    L = ["# 包清单", "",
         "> 由 `make-index.py` 自动生成，不要手改。",
         f"> 生成时间：{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}", "",
         "## 体积", "", "| 发行版 | 架构 | min | base | dev |", "|---|---|---|---|---|"]
    for d, vs in order:
        for v in vs:
            for arch in ("arm64", "amd64"):
                cells = [human(idx[(d, v, arch, t)]["size"]) if (d, v, arch, t) in idx else "—"
                         for t in ("min", "base", "dev")]
                if any(c != "—" for c in cells):
                    L.append(f"| {TITLES[d]} {v} | {arch} | " + " | ".join(cells) + " |")

    L += ["", "## 稳定下载地址", "", "`latest` 永远指向最新一次正式发布：", ""]
    for r in rows:
        L.append(f"- {TITLES[r['distro']]} {r['version']} / {r['arch']} / {r['tier']}（{human(r['size'])}）")
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
