class_name OperationsStore
extends Node

signal changed
var status:="idle"
var operation:=""
var error_kind:=""
var error_code:=""
var message:=""
var security:Dictionary={}
var notifications:Dictionary={}
var privacy:Dictionary={}
var teen:Dictionary={}
var blocks:Array=[]
var profile:Dictionary={}
var verification:Dictionary={}
var verification_queue:Array=[]
var analytics:Dictionary={}
var meta:Dictionary={}

func begin(next:String)->void:operation=next;status="loading";error_kind="";error_code="";message="";changed.emit()
func ready(empty:=false)->void:status="empty" if empty else "ready";changed.emit()
func fail(result:Variant)->void:status="offline" if result.kind=="offline" else "error";error_kind=result.kind;error_code=result.code;message=result.message;changed.emit()
func reset()->void:
	status="idle";operation="";error_kind="";error_code="";message="";security={};notifications={};privacy={};teen={};blocks=[];profile={};verification={};verification_queue=[];analytics={};meta={};changed.emit()
