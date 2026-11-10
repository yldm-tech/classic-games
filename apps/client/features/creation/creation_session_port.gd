class_name CreationSessionPort
extends RefCounted

## Performs the same validation as load_baseline/load_document without mutating
## the active editing session. A true result guarantees the subsequent loads.
func can_load(_runtime_ref: String, _baseline: Dictionary, _document: Dictionary) -> bool: return false
func load_baseline(_runtime_ref: String, _baseline: Dictionary) -> bool: return false
func load_document(_document: Dictionary) -> bool: return false
func current() -> Dictionary: return {}
func apply_patch(_ops: Array) -> bool: return false
func apply_document(_document: Dictionary) -> bool: return false
func is_dirty() -> bool: return false
## Monotonic token for any adopted or edited document state, including origin
## loads whose per-origin revision resets to zero.
func state_token() -> int: return 0
## A monotonic edit revision. Applying, undoing, redoing, or importing a document
## must advance it; loading a new origin resets it to zero.
func revision() -> int: return 0
## Returns RFC 6902 batches that transform the document at `revision` into the
## current document, including inverse changes created by undo/branch edits.
func patches_since_revision(_revision: int) -> Array: return []
func preview(_runtime_ref: String, _dsl: Dictionary) -> bool: return false
