// Package dsl is the single Go implementation of the ForgePlay Mod DSL rules, shared by the backend, the CLI and the MCP server: applying RFC 6902 JSON Patch documents (Apply), upgrading historical DSL majors (Migrate) and validating an effective DSL against the JSON Schemas in packages/schemas (SchemaValidator).
//
// Apply must stay byte-for-byte equivalent to the client implementation in apps/client/runtime/json_patch.gd: the same fork patch chain has to produce the same effective DSL on both sides, otherwise the client preview and what the server stores and validates diverge. See docs/05-dsl-design.md and ADR-013. The golden test in patch_test.go enforces this against the baseline and golden files shared with the client.
//
// In the DSL, enemies and drops are id-keyed maps rather than arrays, so paths look like /enemies/<id>/count and stay stable across a fork chain when entries are added or removed.
//
// Patch and migration code uses only the standard library; schema validation uses github.com/santhosh-tekuri/jsonschema/v6 (ADR-014).
package dsl

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// Sentinel errors that classify why a patch operation or a validation could not run. They are matched with errors.Is; the message of the returned error is unchanged, because the backend shows it to users and the client implementation (json_patch.gd) produces the same text.
var (
	// ErrTargetMissing: replace, remove or test addressed a key that does not exist.
	ErrTargetMissing = errors.New("dsl: patch target does not exist")
	// ErrParentMissing: the container an operation addresses does not exist or cannot hold the key.
	ErrParentMissing = errors.New("dsl: patch parent does not exist")
	// ErrIndexOutOfRange: an array index is not a number or lies outside the array.
	ErrIndexOutOfRange = errors.New("dsl: array index out of range")
	// ErrTestFailed: a test operation found a different value.
	ErrTestFailed = errors.New("dsl: test operation failed")
	// ErrRootPath: an operation addressed the document root, which cannot be patched.
	ErrRootPath = errors.New("dsl: root path cannot be patched")
	// ErrUnsupportedOp: the op is not add, replace, remove or test.
	ErrUnsupportedOp = errors.New("dsl: unsupported patch op")
	// ErrInvalidRuntimeRef: a runtime ref is not of the form <name>@<version> with safe characters.
	ErrInvalidRuntimeRef = errors.New("dsl: invalid runtime ref")
	// ErrUnknownRuntime: no schema exists for the runtime ref.
	ErrUnknownRuntime = errors.New("dsl: no schema for runtime")
)

// classified is an error with a fixed message that also matches one of the sentinel errors above.
type classified struct {
	message string
	class   error
}

func (e *classified) Error() string { return e.message }
func (e *classified) Unwrap() error { return e.class }

// classify formats a message and tags it with a sentinel error.
func classify(class error, format string, args ...any) error {
	return &classified{message: fmt.Sprintf(format, args...), class: class}
}

// OpError is the error Apply returns when an operation fails. Index is the zero-based position of the failing operation in the patch; Error returns the message of Err unchanged.
type OpError struct {
	Index int
	Err   error
}

func (e *OpError) Error() string { return e.Err.Error() }
func (e *OpError) Unwrap() error { return e.Err }

// Op 是一条 RFC 6902 操作。
type Op struct {
	Op    string          `json:"op"`
	Path  string          `json:"path"`
	Value json.RawMessage `json:"value,omitempty"`
}

// Apply 把一组 6902 op 应用到 doc(map[string]any / []any 形态,来自 encoding/json),
// 返回新文档(深拷贝,不修改入参)。支持 add / replace / remove / test。
// A failing operation is returned as *OpError, which carries the index of that operation and keeps the message of the cause.
func Apply(doc map[string]any, ops []Op) (map[string]any, error) {
	working, err := deepCopy(doc)
	if err != nil {
		return nil, err
	}
	var root any = working
	for i, op := range ops {
		root, err = applyOp(root, op)
		if err != nil {
			return nil, &OpError{Index: i, Err: err}
		}
	}
	return root.(map[string]any), nil
}

// applyOp applies one operation to root and returns the new root.
func applyOp(root any, op Op) (any, error) {
	tokens := parsePointer(op.Path)
	// 根路径操作一律拒绝(与客户端 json_patch.gd 对称)。
	// 既防 tokens[:len-1] 越界 panic(不可信补丁的真实攻击面),也保证两端语义一致。
	if len(tokens) == 0 {
		return root, classify(ErrRootPath, "不支持根路径操作: %s", op.Op)
	}
	switch op.Op {
	case "add", "replace":
		var v any
		if err := json.Unmarshal(op.Value, &v); err != nil {
			return root, fmt.Errorf("%s value 解析失败 %s: %w", op.Op, op.Path, err)
		}
		return setAt(root, tokens, v, op.Op)
	case "remove":
		return removeAt(root, tokens)
	case "test":
		got, ok := getAt(root, tokens)
		if !ok {
			return root, classify(ErrTargetMissing, "test 路径不存在: %s", op.Path)
		}
		var want any
		if err := json.Unmarshal(op.Value, &want); err != nil {
			return root, fmt.Errorf("test value 解析失败 %s: %w", op.Path, err)
		}
		if !jsonEqual(got, want) {
			return root, classify(ErrTestFailed, "test 不通过: %s", op.Path)
		}
		return root, nil
	default:
		return root, classify(ErrUnsupportedOp, "不支持的 op: %s", op.Op)
	}
}

// RFC 6901 指针解析:"/a/b~1c" -> ["a", "b/c"]。
func parsePointer(path string) []string {
	if path == "" {
		return nil
	}
	parts := strings.Split(path, "/")[1:]
	for i, p := range parts {
		p = strings.ReplaceAll(p, "~1", "/")
		parts[i] = strings.ReplaceAll(p, "~0", "~")
	}
	return parts
}

func deepCopy(doc map[string]any) (map[string]any, error) {
	b, err := json.Marshal(doc)
	if err != nil {
		return nil, err
	}
	var out map[string]any
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, err
	}
	return out, nil
}

func navigateParent(root any, tokens []string) (any, bool) {
	cur := root
	for _, t := range tokens[:len(tokens)-1] {
		switch c := cur.(type) {
		case map[string]any:
			v, ok := c[t]
			if !ok {
				return nil, false
			}
			cur = v
		case []any:
			idx, err := strconv.Atoi(t)
			if err != nil || idx < 0 || idx >= len(c) {
				return nil, false
			}
			cur = c[idx]
		default:
			return nil, false
		}
	}
	return cur, true
}

func getAt(root any, tokens []string) (any, bool) {
	cur := root
	for _, t := range tokens {
		switch c := cur.(type) {
		case map[string]any:
			v, ok := c[t]
			if !ok {
				return nil, false
			}
			cur = v
		case []any:
			idx, err := strconv.Atoi(t)
			if err != nil || idx < 0 || idx >= len(c) {
				return nil, false
			}
			cur = c[idx]
		default:
			return nil, false
		}
	}
	return cur, true
}

func setAt(root any, tokens []string, value any, kind string) (any, error) {
	key := tokens[0]
	if len(tokens) > 1 {
		switch p := root.(type) {
		case map[string]any:
			child, ok := p[key]
			if !ok {
				return root, classify(ErrParentMissing, "%s 路径父级不存在: /%s", kind, strings.Join(tokens, "/"))
			}
			updated, err := setAt(child, tokens[1:], value, kind)
			if err != nil {
				return root, err
			}
			p[key] = updated
			return root, nil
		case []any:
			idx, err := strconv.Atoi(key)
			if err != nil || idx < 0 || idx >= len(p) {
				return root, classify(ErrParentMissing, "%s 路径父级不存在: /%s", kind, strings.Join(tokens, "/"))
			}
			updated, err := setAt(p[idx], tokens[1:], value, kind)
			if err != nil {
				return root, err
			}
			p[idx] = updated
			return p, nil
		default:
			return root, classify(ErrParentMissing, "%s 路径父级不存在: /%s", kind, strings.Join(tokens, "/"))
		}
	}
	switch p := root.(type) {
	case map[string]any:
		if kind == "replace" {
			if _, exists := p[key]; !exists {
				return root, classify(ErrTargetMissing, "replace 目标不存在: /%s", strings.Join(tokens, "/"))
			}
		}
		p[key] = value
		return root, nil
	case []any:
		if kind == "add" && key == "-" {
			return append(p, value), nil
		}
		idx, err := strconv.Atoi(key)
		if err != nil || idx < 0 || (kind == "add" && idx > len(p)) || (kind == "replace" && idx >= len(p)) {
			return root, classify(ErrIndexOutOfRange, "%s 数组下标非法或越界: %s", kind, key)
		}
		if kind == "add" {
			p = append(p, nil)
			copy(p[idx+1:], p[idx:])
			p[idx] = value
		} else {
			p[idx] = value
		}
		return p, nil
	default:
		return root, classify(ErrParentMissing, "父级不可写: /%s", strings.Join(tokens, "/"))
	}
}

func removeAt(root any, tokens []string) (any, error) {
	key := tokens[0]
	if len(tokens) > 1 {
		switch p := root.(type) {
		case map[string]any:
			child, ok := p[key]
			if !ok {
				return root, classify(ErrParentMissing, "remove 路径父级不存在: /%s", strings.Join(tokens, "/"))
			}
			updated, err := removeAt(child, tokens[1:])
			if err != nil {
				return root, err
			}
			p[key] = updated
			return root, nil
		case []any:
			idx, err := strconv.Atoi(key)
			if err != nil || idx < 0 || idx >= len(p) {
				return root, classify(ErrParentMissing, "remove 路径父级不存在: /%s", strings.Join(tokens, "/"))
			}
			updated, err := removeAt(p[idx], tokens[1:])
			if err != nil {
				return root, err
			}
			p[idx] = updated
			return p, nil
		default:
			return root, classify(ErrParentMissing, "remove 路径父级不存在: /%s", strings.Join(tokens, "/"))
		}
	}
	switch p := root.(type) {
	case map[string]any:
		if _, exists := p[key]; !exists {
			return root, classify(ErrTargetMissing, "remove 目标不存在: /%s", strings.Join(tokens, "/"))
		}
		delete(p, key)
		return root, nil
	case []any:
		idx, err := strconv.Atoi(key)
		if err != nil || idx < 0 || idx >= len(p) {
			return root, classify(ErrIndexOutOfRange, "remove 数组下标非法或越界: %s", key)
		}
		return append(p[:idx], p[idx+1:]...), nil
	default:
		return root, classify(ErrParentMissing, "父级不可删: /%s", strings.Join(tokens, "/"))
	}
}

func jsonEqual(a, b any) bool {
	ab, _ := json.Marshal(a)
	bb, _ := json.Marshal(b)
	return string(ab) == string(bb)
}
