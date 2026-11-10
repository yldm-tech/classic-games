// Package provenance 签发/校验「AI 生成」溯源令牌:HMAC 签名 + 过期时间。
// /ai/mod 成功后签发,客户端在 POST /mods 时回带,服务端校验通过即把 mod 标记为 AI 生成。
// 令牌只能由持有密钥的服务端签发,客户端无法伪造「这是 AI 生成」的标识(防漏标的篡改证据)。
package provenance

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"
	"time"
)

// Signer 用一个对称密钥签发/校验令牌。密钥为空表示「未配置」——Mint 返回空串、Verify 恒为 false。
type Signer struct{ key []byte }

func NewSigner(key string) *Signer { return &Signer{key: []byte(key)} }

// Enabled 是否已配置密钥。
func (s *Signer) Enabled() bool { return len(s.key) > 0 }

// Mint 签发一个在 now+ttl 前有效的令牌,形如 "<expUnix>.<hexHMAC(expUnix)>"。
func (s *Signer) Mint(now time.Time, ttl time.Duration) string {
	if !s.Enabled() {
		return ""
	}
	exp := strconv.FormatInt(now.Add(ttl).Unix(), 10)
	return exp + "." + s.sign(exp)
}

// Verify 校验签名且未过期。
func (s *Signer) Verify(token string, now time.Time) bool {
	if !s.Enabled() || token == "" {
		return false
	}
	exp, sig, ok := strings.Cut(token, ".")
	if !ok {
		return false
	}
	if !hmac.Equal([]byte(sig), []byte(s.sign(exp))) {
		return false
	}
	expUnix, err := strconv.ParseInt(exp, 10, 64)
	if err != nil {
		return false
	}
	return now.Unix() <= expUnix
}

func (s *Signer) sign(msg string) string {
	m := hmac.New(sha256.New, s.key)
	m.Write([]byte(msg))
	return hex.EncodeToString(m.Sum(nil))
}
