package auth

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var (
	ErrOAuthUnavailable = errors.New("auth: OAuth provider unavailable")
	ErrOAuthInvalid     = errors.New("auth: OAuth authorization invalid")
)

type OAuthIdentity struct {
	Subject  string `json:"subject"`
	Nickname string `json:"nickname"`
}
type OAuthVerifier interface {
	Verify(provider, code string) (OAuthIdentity, error)
}

type OAuthProviderConfig struct {
	URL         string
	BearerToken string
}
type HTTPOAuthVerifier struct {
	providers map[string]OAuthProviderConfig
	client    *http.Client
}

func NewHTTPOAuthVerifier(config map[string]OAuthProviderConfig, timeout time.Duration) *HTTPOAuthVerifier {
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	return &HTTPOAuthVerifier{config, &http.Client{Timeout: timeout}}
}
func (v *HTTPOAuthVerifier) Verify(provider, code string) (OAuthIdentity, error) {
	cfg, ok := v.providers[strings.ToLower(provider)]
	if !ok || cfg.URL == "" {
		return OAuthIdentity{}, ErrOAuthUnavailable
	}
	if strings.TrimSpace(code) == "" {
		return OAuthIdentity{}, ErrOAuthInvalid
	}
	body, _ := json.Marshal(map[string]string{"code": code})
	req, err := http.NewRequest(http.MethodPost, cfg.URL, bytes.NewReader(body))
	if err != nil {
		return OAuthIdentity{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	if cfg.BearerToken != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.BearerToken)
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return OAuthIdentity{}, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return OAuthIdentity{}, fmt.Errorf("%w: provider status %d", ErrOAuthInvalid, resp.StatusCode)
	}
	var id OAuthIdentity
	if json.Unmarshal(raw, &id) != nil || strings.TrimSpace(id.Subject) == "" {
		return OAuthIdentity{}, ErrOAuthInvalid
	}
	id.Subject = strings.TrimSpace(id.Subject)
	id.Nickname = strings.TrimSpace(id.Nickname)
	return id, nil
}

func (s *Service) SetOAuthVerifier(v OAuthVerifier) { s.mu.Lock(); s.oauth = v; s.mu.Unlock() }
func (s *Service) OAuthLogin(provider, code string) (string, User, error) {
	provider = strings.ToLower(strings.TrimSpace(provider))
	s.mu.Lock()
	v := s.oauth
	s.mu.Unlock()
	if v == nil {
		return "", User{}, ErrOAuthUnavailable
	}
	id, err := v.Verify(provider, code)
	if err != nil {
		return "", User{}, err
	}
	identity, ok := s.users.FindIdentity(provider, id.Subject)
	var u User
	if ok {
		u, ok = s.users.FindByID(identity.UserID)
	}
	if !ok {
		nickname := id.Nickname
		if nickname == "" {
			nickname = "玩家" + randSuffix()
		}
		u, err = s.users.Create(User{Nickname: nickname})
		if err != nil {
			return "", User{}, err
		}
		if err = s.users.BindIdentity(LoginIdentity{Provider: provider, Subject: id.Subject, UserID: u.ID}); err != nil {
			return "", User{}, err
		}
	}
	if token := s.issueToken(u); token != "" {
		return token, u, nil
	}
	return "", User{}, ErrSessionStore
}

func (s *Service) BindOAuth(userID, provider, code string) error {
	provider = strings.ToLower(strings.TrimSpace(provider))
	s.mu.Lock()
	v := s.oauth
	s.mu.Unlock()
	if v == nil {
		return ErrOAuthUnavailable
	}
	if _, ok := s.users.FindByID(userID); !ok {
		return ErrUserNotFound
	}
	id, e := v.Verify(provider, code)
	if e != nil {
		return e
	}
	return s.users.BindIdentity(LoginIdentity{Provider: provider, Subject: id.Subject, UserID: userID})
}

type SecurityView struct {
	PhoneMasked string   `json:"phone_masked"`
	PasswordSet bool     `json:"password_set"`
	Providers   []string `json:"providers"`
}

func (s *Service) SecurityInfo(userID string) SecurityView {
	u, ok := s.users.FindByID(userID)
	if !ok {
		return SecurityView{}
	}
	ids, _ := s.users.ListIdentities(userID)
	p := make([]string, len(ids))
	for i, v := range ids {
		p[i] = v.Provider
	}
	return SecurityView{PhoneMasked: maskPhone(u.Phone), PasswordSet: u.PasswordHash != "", Providers: p}
}
func maskPhone(v string) string {
	if len(v) < 7 {
		return v
	}
	return v[:3] + "****" + v[len(v)-4:]
}
