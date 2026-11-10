class_name PagedList
extends RefCounted

signal next_requested(cursor:String)

var items:Array=[]
var cursor:=""
var pending:=false

func replace(next_items:Array,next_cursor:String)->void:
	items=next_items.duplicate(true);cursor=next_cursor;pending=false

func append(next_items:Array,next_cursor:String,id_key:String="id")->void:
	var requested_cursor:=cursor
	var known:Dictionary={}
	for item:Variant in items:
		if item is Dictionary and item.has(id_key):known[str(item[id_key])]=true
	for item:Variant in next_items:
		if item is Dictionary and item.has(id_key):
			var id:=str(item[id_key]);if known.has(id):continue
			known[id]=true
		items.append(item.duplicate(true) if item is Dictionary or item is Array else item)
	cursor="" if next_cursor==requested_cursor else next_cursor;pending=false

func request_next()->bool:
	if pending or cursor=="":return false
	pending=true;next_requested.emit(cursor);return true

func fail_next()->void:pending=false
