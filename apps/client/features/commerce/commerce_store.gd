class_name CommerceStore
extends Node

signal changed

var status := "idle"
var operation := ""
var error_kind := ""
var error_code := ""
var message := ""
var balance := 0
var points: Dictionary = {}
var shop: Dictionary = {}
var membership: Dictionary = {}
var welfare: Dictionary = {}
var events: Array = []
var joined_event_ids: Array = []
var achievements: Array = []
var avatar_items: Array = []
var equipped_by_category: Dictionary = {}
var owned_item_ids: Array = []
var earnings: Dictionary = {}
var last_transaction: Dictionary = {}
var last_withdrawal: Dictionary = {}
var withdrawals: Array = []
var orders: Dictionary = {}
var order_items: Array = []
var last_order_id := ""
var payment_session: Dictionary = {}
var pending: Dictionary = {}
var revisions: Dictionary = {}

func begin(next_operation:String) -> void:
	operation=next_operation;status="loading";_clear_error();changed.emit()
func ready(next_status:String="ready") -> void:
	status=next_status;_clear_error();changed.emit()
func fail(result:Variant) -> void:
	status="offline" if result.kind=="offline" else "error"
	error_kind=result.kind;error_code=result.code;message=result.message;changed.emit()
func bump(resource:String) -> void:
	revisions[resource]=int(revisions.get(resource,0))+1
func touch() -> void: changed.emit()
func _clear_error() -> void:error_kind="";error_code="";message=""
