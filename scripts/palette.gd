extends Node
## 全局配色系统（单一真理源）
##
## 弹幕射击的第一支柱是**可读性**，配色不是审美问题而是玩法问题。
## 核心规则只有一条：**背景必须让位，威胁必须跳出来**。
##
## 具体拆成三条可执行的规则：
##   1. 背景低饱和、低明度 —— 星空是"底"，不能和弹幕抢注意力
##   2. 敌方弹幕全部走高饱和暖色 —— 玩家看到暖色就本能地想躲，
##      这是不��要训练就能建立的直觉
##   3. 玩家弹幕走冷色高亮 —— 冷暖分离让玩家一眼分清"我的"和"敌人的"
##
## 另有一条**可学习**的映射：弹速与色相绑定。
## 看到红色就知道"快、必须闪"，看到粉色就知道"慢、能绕"。
## 玩家不需要记住数字，看颜色就能做出反应。
##
## 低端机约束：全部是纯常量 + modulate，**不引入任何着色器、
## 后处理或额外贴图**，draw call 与改动前完全一致。

## ── 背景（低饱和暗色，绝不与弹幕同色）────────────────────
const BG_BASE: Color = Color(0.045, 0.048, 0.085)
## 星云：明度和饱和度都压到很低，只留一点点冷色倾向做纵深
const NEBULA_COOL: Color = Color(0.10, 0.12, 0.26)
const NEBULA_WARM: Color = Color(0.18, 0.10, 0.14)
## 行星：比星云再暗一档，避免大块亮色挡住弹幕
const PLANET_SHADE: Color = Color(0.12, 0.14, 0.28)
## 星星：远景最暗，近景最亮，但整体不刺眼
const STAR_FAR: Color = Color(0.34, 0.36, 0.44)
const STAR_MID: Color = Color(0.52, 0.54, 0.62)
const STAR_NEAR: Color = Color(0.78, 0.78, 0.86)


## ── 敌方弹幕（高饱和暖色 = 危险）─────────────────────────
## 与弹速绑定：快=红（必须闪）、中=琥珀（可绕的墙）、慢=品红（能读的环）
const ENEMY_BULLET_FAST: Color = Color(1.0, 0.30, 0.18)
const ENEMY_BULLET_MID: Color = Color(1.0, 0.72, 0.16)
const ENEMY_BULLET_SLOW: Color = Color(1.0, 0.34, 0.80)


## ── 玩家（冷色高亮 = 我的）───────────────────────────────
## 冷色与敌方暖色形成硬分离，即使弹幕重叠也能一眼分清归属
const PLAYER_BULLET: Color = Color(0.62, 0.95, 1.0)
const PLAYER_HULL: Color = Color(0.86, 0.92, 1.0)
## 引擎尾焰是画面里唯一的暖色，属于"玩家自己"，与敌方弹幕同色系但更橙
const PLAYER_ENGINE: Color = Color(1.0, 0.58, 0.18)
## 擦弹反馈用青白，和玩家弹同族，强化"这是我的收益"的联想
const GRAZE_TINT: Color = Color(0.70, 1.0, 1.0)


## ── 敌人预警 ────────────────────────────────────────────
## 预警用红橙且随蓄力加深，和弹体同族：预告的就是"这些弹要来了"
const WARN_TINT: Color = Color(1.0, 0.42, 0.32)
const WARN_LINE: Color = Color(1.0, 0.30, 0.24)
## 恢复段用冷灰：明确"这个敌人暂时不会开火"，与危险色拉开距离
const RECOVER_TINT: Color = Color(0.42, 0.48, 0.62)


## ── 精英 / Boss ─────────────────────────────────────────
const ELITE_TINT: Color = Color(1.0, 0.72, 0.40)
const BOSS_TINT: Color = Color(1.0, 0.52, 0.44)


## ── UI 强调色 ───────────────────────────────────────────
## 升级卡：风格卡（改变玩法）用青，数值卡用白——一眼能挑出构筑主体
const CARD_STYLE: Color = Color(0.55, 0.90, 1.0)
const CARD_STAT: Color = Color(0.86, 0.86, 0.92)
## 闪避就绪用亮青，冷却中用暗灰
const DASH_READY: Color = Color(0.60, 0.95, 1.0)
const DASH_COOLDOWN: Color = Color(0.45, 0.50, 0.60)
## 进化提示用金，和卡面区分开
const EVOLUTION: Color = Color(1.0, 0.84, 0.42)
## 倒地告警：安全时琥珀，临死变红
const DOWNED_SAFE: Color = Color(1.0, 0.80, 0.50)
const DOWNED_CRITICAL: Color = Color(1.0, 0.42, 0.38)


## 按弹速取弹幕色（弹速分层与配色一一对应）
static func enemy_bullet_color(speed: float) -> Color:
	if speed >= 700.0:
		return ENEMY_BULLET_FAST
	if speed >= 500.0:
		return ENEMY_BULLET_MID
	return ENEMY_BULLET_SLOW
