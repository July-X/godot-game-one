extends Node
## 通用对象池 — 预实例化并复用节点，避免 instantiate/queue_free GC 停顿
##
## 用法:
##   Pool.acquire("bullet", bullet_scene)  → 取用
##   Pool.release(some_node)               → 归还
##   Pool.setup("bullet", bullet_scene, 30) → 预分配

const DEFAULT_POOL_SIZE: int = 20
const MAX_POOL_SIZE: int = 100

## { type_name : [pooled_nodes] }
var _pools: Dictionary = {}
## { node_instance : type_name }
var _active: Dictionary = {}

## 配置某个类型的对象池初始大小
func setup(type_name: String, scene: PackedScene, size: int = DEFAULT_POOL_SIZE) -> void:
	if _pools.has(type_name):
		return  # 已初始化
	var arr: Array[Node] = []
	for i in size:
		var obj := scene.instantiate()
		obj.set_process(false)
		obj.set_physics_process(false)
		obj.visible = false
		obj.set_name("%s_pooled_%d" % [type_name, i])
		arr.append(obj)
	_pools[type_name] = arr

## 从池中取用节点
func acquire(type_name: String, scene: PackedScene) -> Node:
	var pool: Array = _pools.get(type_name)
	if pool == null:
		# 首次使用，延迟初始化
		setup(type_name, scene)
		pool = _pools[type_name]

	var node: Node
	if pool.is_empty():
		node = scene.instantiate()
	else:
		node = pool.pop_back()

	# 如果节点仍在场景树中（release 的 call_deferred 尚未执行），移出
	if node.is_inside_tree():
		var p = node.get_parent()
		if p != null:
			p.remove_child(node)

	node.set_process(true)
	node.set_physics_process(true)
	node.visible = true
	_active[node] = type_name
	return node

## 将节点归还池中
func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var type_name: String = _active.get(node, "")
	if type_name.is_empty():
		# 不在池中管理的节点，直接释放
		if node.is_inside_tree():
			node.queue_free()
		return

	# 重置状态
	node.set_process(false)
	node.set_physics_process(false)
	node.visible = false
	if node.has_method("reset"):
		node.reset()

	# 延迟移出场景树（避免 physics callback 中直接移除 CollisionObject）
	if node.is_inside_tree():
		var p = node.get_parent()
		if p != null:
			p.call_deferred("remove_child", node)

	var pool: Array = _pools.get(type_name)
	if pool != null and pool.size() < MAX_POOL_SIZE:
		pool.append(node)
	else:
		node.queue_free()
