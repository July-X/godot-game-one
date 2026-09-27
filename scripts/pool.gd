extends Node
## 子弹 / 命中特效的取用与回收入口（Autoload `Pool`）
##
## 现状（2026-09-27 校准）：**不做节点复用**，acquire 即 instantiate，
## release 即 queue_free。
##
## 曾经实现过真正的池化（把节点挂在 Pool 下复用），但反复踩到同一类坑：
## "already has a parent"、deferred remove_child 与 add_child 的竞争
## （见 git 3c8527b → c5e503c → be12daf → 1bb5882 → 241f634 五次返工），
## 最终选择"不复用"这条更简单可预期的路径：
##   - 省掉池内节点的父节点归属问题
##   - 省掉归还时的状态重置（速度 / 位置 / 计时 / 特效）——那才是池化真正的成本
##   - reset_all 仍然是必需的：断线回退单机时要把在途子弹全部清掉
##
## 曾经还有一段"预实例化 40 发子弹 + 20 个命中特效"的死代码：节点既没有
## add_child 进场景树，也永远不会被归还，整局白占内存，已删除。
## 恢复真池化前，先看 docs/Development_Plan.md 的「对象池复用」条目。
##
## 用法:
##   Pool.acquire("bullet", bullet_scene)  → 取用（返回新节点）
##   Pool.release(some_node)               → 回收
##   Pool.reset_all()                      → 清空全部在途节点

## { node_instance : type_name }，只用于 reset_all 时批量回收
var _active: Dictionary = {}

## 取用节点。_scene 参数保留是为了兼容既有调用点（acquire 一律显式传场景），
## 同时避免 UNUSED_PARAMETER 警告。
func acquire(type_name: String, _scene: PackedScene) -> Node:
	var node: Node = _scene.instantiate()
	_active[node] = type_name
	return node

## 回收单个节点
func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_active.erase(node)
	node.queue_free()

## 清空所有在途节点（断线回退单机 / 结算时调用）
func reset_all() -> void:
	for node in _active.keys():
		if is_instance_valid(node):
			node.queue_free()
	_active.clear()
