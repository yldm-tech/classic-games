package provenance

import (
	"testing"
	"time"
)

func TestSigner_MintVerify(t *testing.T) {
	s := NewSigner("secret-key")
	now := time.Unix(1_700_000_000, 0)
	tok := s.Mint(now, time.Hour)
	if tok == "" {
		t.Fatal("已配置密钥应签出令牌")
	}
	if !s.Verify(tok, now) {
		t.Error("刚签的令牌应通过校验")
	}
	if s.Verify(tok, now.Add(2*time.Hour)) {
		t.Error("过期令牌应失败")
	}
	if s.Verify("garbage", now) || s.Verify(tok+"x", now) {
		t.Error("被篡改/非法令牌应失败")
	}
	// 另一把钥匙不认这把钥匙的签名
	if NewSigner("other-key").Verify(tok, now) {
		t.Error("不同密钥不应通过校验")
	}
}

func TestSigner_Disabled(t *testing.T) {
	s := NewSigner("")
	if s.Enabled() {
		t.Error("空密钥应为未启用")
	}
	if s.Mint(time.Now(), time.Hour) != "" {
		t.Error("未启用应返回空令牌")
	}
	if s.Verify("anything", time.Now()) {
		t.Error("未启用 Verify 应恒 false")
	}
}
