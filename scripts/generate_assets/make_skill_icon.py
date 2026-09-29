#!/usr/bin/env python3
"""生成 HUD 技能图标，规格与 assets/sprites/ui/skill_{laser,skill}.png 完全一致。

## 现有图标的规格（实测得出，不是猜的）

  - 128x128 RGBA
  - 在 32x32 网格上作画后最近邻放大 4 倍（实测同色块长度恒为 4）
  - 只有 10~11 种 RGB 色 = 明确的像素画量化调色板
  - 深色描边 + 3~4 级明度阶梯

## 为什么闪避图标是程序化画的，而不是直接用 AI 出图

先用图像模型出了 3 轮共 12 张候选，结论是**不能用**：
模型输出是大面积近乎同色的平滑渐变，512 -> 32 的面积平均会把细描边冲掉、
把镂空填满，最后 32x32 上只剩两三个亮色档——形状糊成一坨圆饼。
像素画能用是因为形状由少量、刻意的大色块构成，平滑渲染缩小只会变饼。
（模型确实有用：它定下了造型方案——朝右的双人字箭头 + 左侧速度残影，
  「»」是快进/冲刺的通用符号。下面渲染的就是这个造型。）

所以：造型靠模型，工艺靠代码。直接在 32x32 网格上按块画，
明暗分层由到描边的距离决定，天然就是像素画。

用法：
  python3 make_skill_icon.py dash assets/sprites/ui/skill_dash.png   # 程序化画
  python3 make_skill_icon.py ai <src.jpg> <dst.png>                  # AI 出图后处理
"""
import sys
from PIL import Image

GRID = 32          # 与现有图标一致
SCALE = 4          # 32 -> 128
SIZE = GRID * SCALE

# 青绿系，与激光的蓝紫系拉开色相差。
# 最深一档承担描边职责（对应现有图标里的深蓝/深紫轮廓）。
PALETTE = [
    (10, 54, 74),    # 0 描边
    (24, 118, 146),  # 1 暗部
    (64, 190, 210),  # 2 中间调
    (150, 234, 246), # 3 亮部
    (232, 254, 255), # 4 高光
]


# ══════════════════════════════════════════════════════════════
# 通用工具
# ══════════════════════════════════════════════════════════════

def save_grid(grid: list, dst: str) -> None:
    """把 32x32 的颜色索引网格存成 128x128 PNG。"""
    im = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    px = im.load()
    for y in range(GRID):
        for x in range(GRID):
            v = grid[y][x]
            if v is None:
                continue
            r, g, b = PALETTE[v]
            px[x, y] = (r, g, b, 255)
    im = im.resize((SIZE, SIZE), Image.NEAREST)
    im.save(dst, "PNG", optimize=True)
    colors = {grid[y][x] for y in range(GRID) for x in range(GRID) if grid[y][x] is not None}
    filled = sum(1 for y in range(GRID) for x in range(GRID) if grid[y][x] is not None)
    print(f"{dst}: {im.size} 用了 {len(colors)}/{len(PALETTE)} 级明度 "
          f"非透明占比={100*filled/(GRID*GRID):.1f}%")


def new_grid():
    return [[None] * GRID for _ in range(GRID)]


def draw_capsule(grid, p0, p1, thickness):
    """把一条粗线段画进网格（Bresenham + 半径扩展），返回覆盖到的格子集合。

    半径用 (thickness-1)/2 而不是 thickness//2：后者会让奇数厚度凭空少一格
    （thickness=5 的 //2 得 2，实际只画 5 格里的 5 格但和 4 的半径相同，
    于是 4 和 5 画出来完全一样，白白浪费一个调节档位）。
    """
    cells = set()
    x0, y0 = p0
    x1, y1 = p1
    steps = max(abs(x1 - x0), abs(y1 - y0)) * 4 + 1
    r = (thickness - 1) / 2.0
    for i in range(steps + 1):
        t = i / steps
        cx = round(x0 + (x1 - x0) * t)
        cy = round(y0 + (y1 - y0) * t)
        for dy in range(-int(r), int(r) + 1):
            for dx in range(-int(r), int(r) + 1):
                # 圆形而非方形端面：方形端面在拐角处会鼓出一坨，
                # 斜线段上尤其明显
                if dx * dx + dy * dy > r * r + 0.25:
                    continue
                x, y = cx + dx, cy + dy
                if 0 <= x < GRID and 0 <= y < GRID:
                    cells.add((x, y))
    return cells


def shade_and_outline(grid, cells):
    """按到描边的距离分层，再压一圈最深色描边。

    像素画可读性的命门就是这圈深色剪影：深色 HUD 上没有硬边界，
    缩到 92px 就会糊成一团。AI 出图的描边在 512 上只有 1~2px，
    降采样必丢，所以描边必须**在目标网格上重新生成**，不能指望缩放保留。
    """
    cells = set(cells)
    # 描边 = 与外部相邻的格子
    outline = set()
    for x, y in cells:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < GRID and 0 <= ny < GRID) or (nx, ny) not in cells:
                outline.add((x, y))
                break
    interior = cells - outline

    # 内部分层：到描边的切比雪夫距离
    depth = {}
    frontier = set(outline)
    d = 0
    while frontier:
        d += 1
        nxt = set()
        for x, y in frontier:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if (nx, ny) in interior and (nx, ny) not in depth:
                        depth[(nx, ny)] = d
                        nxt.add((nx, ny))
        frontier = nxt

    for x, y in outline:
        grid[y][x] = 0
    for x, y in interior:
        dist = depth.get((x, y), 1)
        # 描边旁最深，中心最亮：三档即可，档位多了在 92px 上反而糊
        grid[y][x] = 1 if dist <= 1 else (2 if dist <= 2 else (3 if dist >= 4 else 2))
    # 最内圈再提一档做高光
    if interior:
        maxd = max(depth.values())
        if maxd >= 5:
            for x, y in interior:
                if depth.get((x, y), 0) >= maxd - 1:
                    grid[y][x] = 4


# ══════════════════════════════════════════════════════════════
# 闪避图标（程序化）
# ══════════════════════════════════════════════════════════════

def render_dash() -> list:
    """朝右的双人字箭头 + 左侧速度残影。

    造型来自图像模型出图（见文件头说明）：模型这一轮给对了形状语义，
    但渲染质量达不到像素画标准，所以这里按同一造型在网格上重画。
    语义上「»」+ 拖尾 = 快进/冲刺，玩家不需要学习就能读懂。
    """
    grid = new_grid()
    cells = set()

    # 两枚人字箭头，朝右。
    #
    # 厚度 6 格（放大后 24px，约占 92px 槽位的 1/4）是并排实测选出来的：
    #   4 格 → 描边吃掉大半宽度，左侧残影直接糊进箭头，» 的镂空读不出来
    #   5 格 → 能读开，但内部只够放 1 档明度，整条发平
    #   6 格 → 内部留得住明暗分层，箭头与残影分离得开
    # 纵向间距收紧到 apex_y 相差 8：差 10 时读起来是两个独立箭头，
    # 而不是"一个 » 符号"——后者才是玩家一眼能认的快进/冲刺符号。
    for apex_y in (12, 20):
        cells |= draw_capsule(grid, (10, apex_y - 6), (24, apex_y), 6)
        cells |= draw_capsule(grid, (24, apex_y), (10, apex_y + 6), 6)

    # 左侧速度残影：一道长 + 一道短，指向右，暗示"正在加速"。
    # 放在两枚箭头之间的空档（y=16），而不是叠在箭头所在行——
    # 叠上去会把 » 的镂空填掉，那正是前一版看起来散成一团的原因。
    cells |= draw_capsule(grid, (1, 16), (9, 16), 3)

    shade_and_outline(grid, cells)
    return grid


# ══════════════════════════════════════════════════════════════
# AI 出图后处理（留给将来其他图标）
# ══════════════════════════════════════════════════════════════

def strip_background(im):
    """把接近纯白的背景抠成透明。阈值取 232：模型输出带压缩噪点，卡死会留白边。"""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, _ = px[x, y]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum > 232 and (max(r, g, b) - min(r, g, b)) < 26:
                px[x, y] = (r, g, b, 0)
    return im


def trim_and_fit(im):
    bbox = im.getbbox()
    if bbox is None:
        raise SystemExit("抠完背景后没有内容")
    im = im.crop(bbox)
    inner = GRID - 2
    w, h = im.size
    scale = min(inner / w, inner / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    im = im.resize((nw, nh), Image.BOX)
    out = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    out.paste(im, ((GRID - nw) // 2, (GRID - nh) // 2))
    return out


def ai_postprocess(src, dst):
    im = trim_and_fit(strip_background(Image.open(src)))
    px = im.load()
    mask = {(x, y) for y in range(GRID) for x in range(GRID) if px[x, y][3] > 0}
    grid = new_grid()
    shade_and_outline(grid, mask)
    save_grid(grid, dst)


def main():
    mode = sys.argv[1]
    if mode == "dash":
        save_grid(render_dash(), sys.argv[2])
    elif mode == "ai":
        ai_postprocess(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
