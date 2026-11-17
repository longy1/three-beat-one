# -*- coding: utf-8 -*-
"""CJK 字体子集化工具（Web 导出必备：浏览器无系统字体回退，须打包中文字体）。

来源：Noto Sans SC（OFL 协议）SubsetOTF；字集 = 项目 UI 源码全部字符
（core/*.gd、script/*.gd、scene/*、project.godot）+ ASCII + 常用全角标点缓冲。

用法（在仓库根目录）：
    python -I tool/subset_font.py [源字体] [输出字体]
默认：build/_font_src/NotoSansSC-Regular.otf → font/NotoSansSC-Regular.subset.otf

纪律：UI 文案有新增字符（尤其新中文/符号）后必须重跑本脚本并重新导出 Web 版，
否则该字符在浏览器中显示为豆腐块（详见 AGENTS.md「HTML 导出与验收工作流」）。
"""
import pathlib
import sys

from fontTools import subset

REPO = pathlib.Path(__file__).resolve().parents[1]

# 运行时可能出现的全角标点/符号缓冲（格式化拼接、未来文案微调）
BUFFER_CHARS = "，。：；！？、（）《》「」『』【】—…·×＋－－＝％￥℃①②③④⑤⑥⑦⑧⑨⑩✓✗♠♥♣♦👍"


def collect_chars() -> str:
    chars = set(BUFFER_CHARS)
    chars |= set(chr(c) for c in range(0x20, 0x7F))  # 可打印 ASCII（数字/字母/常用半角符号）
    patterns = ["core/*.gd", "script/*.gd", "net/*.gd", "scene/*.tscn", "scene/*.tres", "project.godot"]
    for pattern in patterns:
        for path in REPO.glob(pattern):
            chars |= set(path.read_text(encoding="utf-8"))
    return "".join(sorted(chars))


def main() -> int:
    src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "build/_font_src/NotoSansSC-Regular.otf"
    dst = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else REPO / "font/NotoSansSC-Regular.subset.otf"
    if not src.exists():
        print(f"源字体不存在：{src}（先放入 build/_font_src/，来源 notofonts/noto-cjk SubsetOTF/SC）")
        return 1
    chars = collect_chars()
    options = subset.Options()
    options.name_IDs = ["*"]          # 保留字体名等元数据
    options.name_legacy = True
    options.name_languages = ["*"]
    options.layout_features = ["*"]   # 保留 kerning 等排版特性
    options.notdef_outline = True
    font = subset.load_font(str(src), options)
    ss = subset.Subsetter(options)
    ss.populate(text=chars)
    ss.subset(font)
    dst.parent.mkdir(parents=True, exist_ok=True)
    subset.save_font(font, str(dst), options)
    print(f"子集完成：{len(chars)} 个字符 → {dst}（{dst.stat().st_size / 1024:.0f} KB）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
