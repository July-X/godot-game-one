extends Node
## 升级三选一（升级卡池）
##
## 设计原则（见 docs/Design_Decisions.md「升级卡池」）：
## 1. **每张卡要么改数值，要么改操作方式**——只改数值的卡最多占一半。
##    三个原始属性（扩散/速射/威力）都是线性 DPS 乘法项，"扩散流/速射流/
##    威力流"体感上是同一种 build，玩家感受不到差异，也就没有 build 认同感。
## 2. **不给游戏加操作负担**。本作的契约是"全自动射击 + 只用鼠标走位"，
##    所以卡牌只能改变**走位方式**和**弹幕形态**，不能新增按钮。
##    典型：穿透流逼你贴脸、溅射流逼你精准卡位、追踪流让你站桩——
##    同一套输入，三种截然不同的站位偏好。
## 3. 联机时两端各自抽 3 张、各选各的，不做共享卡池协商（v2 再考虑）。
##    独立抽取保证两端不会因为抢同一张卡而卡住选择。

signal card_chosen(peer_id: int, card_id: String, choice_index: int)
signal draft_opened(peer_id: int, cards: Array)

## 卡池定义。字段：
##   id/name/desc  文本
##   kind          "stat"（数值）或 "style"（改变操作方式）
##   max_stacks    可叠加层数上限
const CARDS: Array[Dictionary] = [
	# ── 改变操作方式（构筑的核心）────────────────────────────
	{
		"id": "pierce", "name": "贯穿弹芯", "kind": "style",
		"desc": "子弹额外贯穿 1 个敌人。\n需要贴近敌群输出。",
		"max_stacks": 3,
	},
	{
		"id": "splash", "name": "溅射弹头", "kind": "style",
		"desc": "子弹命中时小范围爆炸。\n需要卡准密集敌群的位置。",
		"max_stacks": 2,
	},
	{
		"id": "homing", "name": "追踪回路", "kind": "style",
		"desc": "子弹轻微追踪最近的敌人。\n站桩也能覆盖全场，但会打偏。",
		"max_stacks": 2,
	},
	{
		"id": "ricochet", "name": "回弹弹皮", "kind": "style",
		"desc": "子弹撞墙后不再反弹，改为沿敌群方向散射。",
		"max_stacks": 1,
	},
	{
		"id": "graze_focus", "name": "擦弹专注", "kind": "style",
		"desc": "擦弹判定半径 +8px，擦弹窗口 2s → 3s。\n奖励更早触发。",
		"max_stacks": 3,
	},
	# ── 数值（最多一半，与上面混合）──────────────────────────
	{
		"id": "power", "name": "高爆弹头", "kind": "stat",
		"desc": "威力 +3。",
		"max_stacks": 99,
	},
	{
		"id": "firerate", "name": "过载扳机", "kind": "stat",
		"desc": "速射 +2。",
		"max_stacks": 8,
	},
	{
		"id": "spread", "name": "散射枪管", "kind": "stat",
		"desc": "扩散 +2。",
		"max_stacks": 5,
	},
	{
		"id": "vitality", "name": "强化装甲", "kind": "stat",
		"desc": "生命上限 +20，并立即回复 20。",
		"max_stacks": 8,
	},
	{
		"id": "shield", "name": "护盾电容", "kind": "stat",
		"desc": "护盾充能间隔 8s → 6s。",
		"max_stacks": 2,
	},
]

## 抽卡次数与超时
const DRAFT_POOL_SIZE: int = 3
const DRAFT_TIMEOUT_SECONDS: float = 10.0

var _rng := RandomNumberGenerator.new()

## { peer_id : {cards = [...], left = 秒, chosen = bool} }
var _drafts: Dictionary = {}


func _ready() -> void:
	_rng.randomize()


## 为某个 peer 抽 3 张卡。已经满层的卡不再进池，避免"抽到没用的卡"。
func open_draft(peer_id: int) -> Array:
	var owned: Dictionary = GameState.get_card_stacks(peer_id)
	var pool: Array = []
	for card: Dictionary in CARDS:
		var cid: String = str(card.id)
		if int(owned.get(cid, 0)) >= int(card.max_stacks):
			continue
		pool.append(cid)
	if pool.is_empty():
		return []
	## Fisher-Yates 部分洗牌：从下标 0 向后洗，只洗前 N 个位置。
	##
	## 这里踩过一个很隐蔽的坑：最初写成 `for i in range(DRAFT_POOL_SIZE, pool.size())`，
	## 也就是从前 3 个位置开始洗——但**前 3 个元素永远不会参与任何交换**，
	## 于是每次抽卡返回的都是 pool[0..2] 原样输出，玩家连续 12 级看到的
	## 三张卡完全一样，构筑系统等于不存在。用 Python 复现时一眼就能看出
	## 6 次 trial 结果全部相同。
	##
	## 正确写法是 `for i in range(pool.size() - 1)` 从后往前洗（Knuth 版）：
	## 把 pool[i] 与 pool[randi_range(0, i)] 交换。这样位置 i 上一定
	## 放着一个"从未被选中过"的元素，前 N 个位置的分布才是均匀的。
	for i in range(pool.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picks: Array = pool.slice(0, mini(DRAFT_POOL_SIZE, pool.size()))
	_drafts[peer_id] = {"cards": picks, "left": DRAFT_TIMEOUT_SECONDS, "chosen": false}
	draft_opened.emit(peer_id, picks)
	return picks


func _process(delta: float) -> void:
	if _drafts.is_empty():
		return
	for peer_id: Variant in _drafts.keys():
		var d: Dictionary = _drafts[peer_id]
		if bool(d.chosen):
			continue
		d.left = float(d.left) - delta
		if float(d.left) <= 0.0:
			## 超时自动选第一张。必须要有兜底：否则玩家没看到/没空选卡
			## 时会被永久卡住，拿不到升级收益。
			choose_card(int(peer_id), 0)


## 玩家按键选卡。index 越界或已选过都忽略。
func choose_card(peer_id: int, index: int) -> bool:
	if not _drafts.has(peer_id):
		return false
	var d: Dictionary = _drafts[peer_id]
	if bool(d.chosen):
		return false
	var cards: Array = d.cards
	if index < 0 or index >= cards.size():
		return false
	d.chosen = true
	_drafts[peer_id] = d
	var card_id: String = str(cards[index])
	GameState.apply_card(peer_id, card_id)
	card_chosen.emit(peer_id, card_id, index)
	return true


func has_draft(peer_id: int) -> bool:
	return _drafts.has(peer_id) and not bool(_drafts[peer_id].chosen)


func get_draft(peer_id: int) -> Dictionary:
	return _drafts.get(peer_id, {})


func clear_drafts() -> void:
	_drafts.clear()


static func card_by_id(card_id: String) -> Dictionary:
	for card: Dictionary in CARDS:
		if str(card.id) == card_id:
			return card
	return {}


## 供 UI 读取
static func card_texts() -> Array:
	var out: Array = []
	for card: Dictionary in CARDS:
		out.append({
			"id": card.id, "name": card.name, "desc": card.desc, "kind": card.kind,
		})
	return out
