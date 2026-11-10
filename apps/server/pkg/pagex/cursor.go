// Package pagex 提供游标分页(docs/09-api-design.md:游标式 ?cursor=&limit=,返回 next_cursor)。
// 当前游标编码 offset(不透明 base64);将来可换成 keyset(last-id)而不动调用方。
package pagex

import (
	"encoding/base64"
	"fmt"
	"strconv"
)

const (
	DefaultLimit = 20
	MaxLimit     = 100
)

// Encode 把 offset 编成不透明游标。offset<=0 返回空(首页无游标)。
func Encode(offset int) string {
	if offset <= 0 {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString([]byte(strconv.Itoa(offset)))
}

// Decode 解析游标为 offset。空串视为 0(首页)。
func Decode(cursor string) (int, error) {
	if cursor == "" {
		return 0, nil
	}
	b, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return 0, fmt.Errorf("非法游标")
	}
	n, err := strconv.Atoi(string(b))
	if err != nil || n < 0 {
		return 0, fmt.Errorf("非法游标")
	}
	return n, nil
}

// ClampLimit 把 limit 归一到 [1, MaxLimit],<=0 用 DefaultLimit。
func ClampLimit(limit int) int {
	if limit <= 0 {
		return DefaultLimit
	}
	if limit > MaxLimit {
		return MaxLimit
	}
	return limit
}

// Page 对已排序切片做游标分页,返回 (该页, nextCursor)。nextCursor 为空表示到底。
func Page[T any](all []T, cursor string, limit int) ([]T, string, error) {
	offset, err := Decode(cursor)
	if err != nil {
		return nil, "", err
	}
	limit = ClampLimit(limit)
	if offset >= len(all) {
		return []T{}, "", nil
	}
	end := offset + limit
	if end >= len(all) {
		return all[offset:], "", nil
	}
	return all[offset:end], Encode(end), nil
}
