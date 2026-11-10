extends SceneTree

const AsyncContentScript:=preload("res://ui/patterns/async_content.gd")
const EmptyStateScript:=preload("res://ui/patterns/empty_state.gd")
const PagedListScript:=preload("res://ui/patterns/paged_list.gd")
const ConfirmSheetScript:=preload("res://ui/patterns/confirm_sheet.gd")
const Widgets:=preload("res://shell/design_system/components/widgets.gd")

var passed:=0
var failed:=0

func _initialize()->void:
	_test_async_content();_test_empty_state();_test_paged_list();_test_confirm_sheet();_test_design_widgets()
	print("patterns_test: %d passed, %d failed"%[passed,failed]);quit.call_deferred(0 if failed==0 else 1)

func _test_async_content()->void:
	var view=AsyncContentScript.new();root.add_child(view);view.present("loading","Loading","dark","Retry")
	_check("async content renders loading state",view.current_state=="loading" and view.find_child("LoadingIndicator",true,false)!=null)
	var retried:={"value":false};view.retry_requested.connect(func():retried.value=true);view.present("offline","Offline","dark","Retry");(view.find_child("RetryButton",true,false) as Button).pressed.emit()
	_check("async content renders failure and emits retry intent",view.current_state=="offline" and retried.value);view.queue_free()

func _test_empty_state()->void:
	var view=EmptyStateScript.new();root.add_child(view);var retried:={"value":false};view.retry_requested.connect(func():retried.value=true);view.configure("Nothing here","dark","Try again","Look around");(view.find_child("RetryButton",true,false) as Button).pressed.emit()
	_check("empty state owns message alignment and retry intent",view.find_child("EmptyMessage",true,false).text=="Nothing here" and retried.value)
	_check("empty state can render a subtitle",view.find_child("EmptySubtitle",true,false).text=="Look around");view.queue_free()

func _test_design_widgets()->void:
	var avatar:=Widgets.avatar("@koru","dark",40);root.add_child(avatar)
	_check("avatar uses first letter and circular size",avatar.name=="Avatar" and avatar.custom_minimum_size==Vector2(40,40) and (avatar.get_child(0) as Label).text=="K")
	var kpi:=Widgets.kpi_card("1.2k","Plays","dark");root.add_child(kpi)
	_check("kpi card exposes value and label",(kpi.find_child("KpiValue",true,false) as Label).text=="1.2k" and (kpi.find_child("KpiLabel",true,false) as Label).text=="Plays")
	var ghost:=Widgets.ghost_button("See all","dark");root.add_child(ghost)
	_check("ghost button stays flat",ghost.flat and ghost.text=="See all")
	var sk:=Widgets.skeleton_block(48,"dark");root.add_child(sk)
	_check("skeleton block has themed height",sk.custom_minimum_size.y==48)
	for node:Node in [avatar,kpi,ghost,sk]:node.queue_free()

func _test_paged_list()->void:
	var list=PagedListScript.new();var requested:=[];list.next_requested.connect(func(cursor):requested.append(cursor));list.replace([{"id":"a"}],"next")
	_check("paged list replaces items and exposes cursor",list.items.size()==1 and list.cursor=="next")
	_check("paged list suppresses duplicate cursor requests",list.request_next() and not list.request_next() and requested==["next"])
	list.append([{"id":"a"},{"id":"b"}],"");_check("paged list appends unique items and completes request",list.items.map(func(item):return item.id)==["a","b"] and not list.pending and not list.request_next())
	list.replace([{"id":"a"}],"stuck");list.request_next();list.append([],"stuck")
	_check("paged list stops when the server repeats a cursor",list.cursor=="" and not list.pending and not list.request_next())

func _test_confirm_sheet()->void:
	var view=ConfirmSheetScript.new();root.add_child(view);var result:={"confirm":0,"cancel":0};view.confirmed.connect(func():result.confirm+=1);view.cancelled.connect(func():result.cancel+=1);view.configure("Delete?","Cannot undo","Delete","Cancel","dark")
	view.set_pending(true);_check("confirm sheet reflects consumer-owned pending state",(view.find_child("ConfirmButton",true,false) as Button).disabled and (view.find_child("CancelButton",true,false) as Button).disabled);view.set_pending(false)
	(view.find_child("ConfirmButton",true,false) as Button).pressed.emit();view.set_pending(false);(view.find_child("CancelButton",true,false) as Button).pressed.emit()
	_check("confirm sheet emits explicit confirm and cancel intents",result=={"confirm":1,"cancel":1});view.queue_free()

func _check(label:String,condition:bool)->void:
	if condition:passed+=1
	else:failed+=1;push_error("FAIL: "+label)
