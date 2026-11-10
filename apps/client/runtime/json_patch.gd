class_name JsonPatch
extends RefCounted

## 最小 RFC 6902 (JSON Patch) 实现,服务 Fork 补丁链(见 docs/05-dsl-design.md、ADR-013)。
## 只覆盖 spike 需要的 op:add / replace / remove / test。
## DSL 里 enemies/drops 是 id-keyed map,故路径形如 /enemies/<id>/count,稳定不错位。

## 对 doc 应用一组 patch ops,返回 { ok: bool, result: Variant, error: String }。
## doc 不被修改(内部深拷贝)。
static func apply(doc: Variant, ops: Array) -> Dictionary:
	var working: Variant = _deep_copy(doc)
	for op_any in ops:
		if typeof(op_any) != TYPE_DICTIONARY:
			return _err("op 不是对象: %s" % str(op_any))
		var op: Dictionary = op_any
		var kind: String = str(op.get("op", ""))
		var path: String = str(op.get("path", ""))
		var tokens: Array = _parse_pointer(path)
		# 根路径操作一律拒绝(含 replace),与服务端 patch.go 对称,避免 tokens[-1] 越界。
		if tokens.is_empty():
			return _err("不支持根路径操作: %s" % kind)
		match kind:
			"add", "replace":
				if not op.has("value"):
					return _err("%s 缺 value: %s" % [kind, path])
				var e1: String = _set_at(working, tokens, op["value"], kind)
				if e1 != "":
					return _err(e1)
			"remove":
				var e2: String = _remove_at(working, tokens)
				if e2 != "":
					return _err(e2)
			"test":
				# 缺 value 直接判错,与服务端(value 走 json.Unmarshal,缺失即报错)对称;
				# 否则缺 value 会被当 null 比较,两端语义分叉,破坏补丁链逐字节一致。
				if not op.has("value"):
					return _err("test 缺 value: %s" % path)
				var got: Dictionary = _get_at(working, tokens)
				if not got["ok"]:
					return _err("test 路径不存在: %s" % path)
				if got["value"] != op.get("value"):
					return _err("test 不通过: %s" % path)
			_:
				return _err("不支持的 op: %s" % kind)
	return {"ok": true, "result": working, "error": ""}

static func _err(msg: String) -> Dictionary:
	return {"ok": false, "result": null, "error": msg}

# RFC 6901 指针解析:"/a/b~1c" -> ["a", "b/c"]
static func _parse_pointer(path: String) -> Array:
	if path == "":
		return []
	var raw: PackedStringArray = path.split("/")
	var tokens: Array = []
	for i in range(1, raw.size()):
		tokens.append(raw[i].replace("~1", "/").replace("~0", "~"))
	return tokens

static func _deep_copy(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		return (v as Dictionary).duplicate(true)
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).duplicate(true)
	return v

static func _get_at(root: Variant, tokens: Array) -> Dictionary:
	var cur: Variant = root
	for t in tokens:
		if typeof(cur) == TYPE_DICTIONARY:
			if not (cur as Dictionary).has(t):
				return {"ok": false, "value": null}
			cur = (cur as Dictionary)[t]
		elif typeof(cur) == TYPE_ARRAY:
			# 非数字下标(如 "bird_1"/"")必须拒绝,不能像 int() 那样静默退化成 0,
			# 否则与服务端 strconv.Atoi 报错的语义分叉,破坏两端逐字节一致(见 patch.go)。
			if not str(t).is_valid_int():
				return {"ok": false, "value": null}
			var idx: int = str(t).to_int()
			if idx < 0 or idx >= (cur as Array).size():
				return {"ok": false, "value": null}
			cur = (cur as Array)[idx]
		else:
			return {"ok": false, "value": null}
	return {"ok": true, "value": cur}

static func _navigate_parent(root: Variant, tokens: Array) -> Dictionary:
	var cur: Variant = root
	for i in range(tokens.size() - 1):
		var t: Variant = tokens[i]
		if typeof(cur) == TYPE_DICTIONARY and (cur as Dictionary).has(t):
			cur = (cur as Dictionary)[t]
		elif typeof(cur) == TYPE_ARRAY:
			if not str(t).is_valid_int():
				return {"ok": false, "parent": null}
			var idx: int = str(t).to_int()
			if idx < 0 or idx >= (cur as Array).size():
				return {"ok": false, "parent": null}
			cur = (cur as Array)[idx]
		else:
			return {"ok": false, "parent": null}
	return {"ok": true, "parent": cur}

static func _set_at(root: Variant, tokens: Array, value: Variant, kind: String) -> String:
	var nav: Dictionary = _navigate_parent(root, tokens)
	if not nav["ok"]:
		return "%s 路径父级不存在: /%s" % [kind, "/".join(tokens)]
	var parent: Variant = nav["parent"]
	var key: Variant = tokens[tokens.size() - 1]
	if typeof(parent) == TYPE_DICTIONARY:
		if kind == "replace" and not (parent as Dictionary).has(key):
			return "replace 目标不存在: /%s" % "/".join(tokens)
		(parent as Dictionary)[key] = value
		return ""
	elif typeof(parent) == TYPE_ARRAY:
		var arr: Array = parent
		# 末尾追加 token "-" 仅对 add 生效,与服务端 patch.go 对称(replace 会走 strconv.Atoi("-") 报错)。
		# 否则 replace /arr/- 在客户端追加、服务端报错,破坏补丁链逐字节一致。
		if kind == "add" and str(key) == "-":
			arr.append(value)
			return ""
		if not str(key).is_valid_int():
			return "%s 数组下标非法: /%s" % [kind, "/".join(tokens)]
		var idx: int = str(key).to_int()
		if kind == "add":
			if idx < 0 or idx > arr.size():
				return "add 数组下标越界: /%s" % "/".join(tokens)
			arr.insert(idx, value)
		else:
			if idx < 0 or idx >= arr.size():
				return "replace 数组下标越界: /%s" % "/".join(tokens)
			arr[idx] = value
		return ""
	return "父级不可写: /%s" % "/".join(tokens)

static func _remove_at(root: Variant, tokens: Array) -> String:
	var nav: Dictionary = _navigate_parent(root, tokens)
	if not nav["ok"]:
		return "remove 路径父级不存在: /%s" % "/".join(tokens)
	var parent: Variant = nav["parent"]
	var key: Variant = tokens[tokens.size() - 1]
	if typeof(parent) == TYPE_DICTIONARY:
		if not (parent as Dictionary).has(key):
			return "remove 目标不存在: /%s" % "/".join(tokens)
		(parent as Dictionary).erase(key)
		return ""
	elif typeof(parent) == TYPE_ARRAY:
		if not str(key).is_valid_int():
			return "remove 数组下标非法: /%s" % "/".join(tokens)
		var idx: int = str(key).to_int()
		if idx < 0 or idx >= (parent as Array).size():
			return "remove 数组下标越界: /%s" % "/".join(tokens)
		(parent as Array).remove_at(idx)
		return ""
	return "父级不可删: /%s" % "/".join(tokens)
