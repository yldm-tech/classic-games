package auth

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestOAuthVerifierAndLogin(t *testing.T) {
	var gotCode, gotAuth string
	provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var b map[string]string
		_ = json.NewDecoder(r.Body).Decode(&b)
		gotCode = b["code"]
		gotAuth = r.Header.Get("Authorization")
		_ = json.NewEncoder(w).Encode(OAuthIdentity{Subject: "stable_subject", Nickname: "OAuth User"})
	}))
	defer provider.Close()
	v := NewHTTPOAuthVerifier(map[string]OAuthProviderConfig{"apple": {URL: provider.URL, BearerToken: "secret"}}, time.Second)
	s := NewService(NewLogSender(), NewMemUserRepo())
	s.SetOAuthVerifier(v)
	token, u, err := s.OAuthLogin("APPLE", "authorization_code")
	if err != nil || token == "" || u.Nickname != "OAuth User" {
		t.Fatalf("login token=%q user=%+v err=%v", token, u, err)
	}
	if gotCode != "authorization_code" || gotAuth != "Bearer secret" {
		t.Fatalf("provider request code=%q auth=%q", gotCode, gotAuth)
	}
	_, again, err := s.OAuthLogin("apple", "second_code")
	if err != nil || again.ID != u.ID {
		t.Fatalf("identity not stable: %+v %v", again, err)
	}
	if _, _, err = s.OAuthLogin("unknown", "x"); err != ErrOAuthUnavailable {
		t.Fatalf("unknown provider=%v", err)
	}
}

func TestBindMultipleOAuthIdentitiesAndRejectTakeover(t *testing.T) {
	v := &fakeOAuthVerifier{identities: map[string]OAuthIdentity{"google:g": {Subject: "g"}, "apple:a": {Subject: "a"}}}
	repo := NewMemUserRepo()
	u1, _ := repo.Create(User{Phone: "13000000001"})
	u2, _ := repo.Create(User{Phone: "13000000002"})
	s := NewService(NewLogSender(), repo)
	s.SetOAuthVerifier(v)
	if err := s.BindOAuth(u1.ID, "google", "g"); err != nil {
		t.Fatal(err)
	}
	if err := s.BindOAuth(u1.ID, "apple", "a"); err != nil {
		t.Fatal(err)
	}
	if got := s.SecurityInfo(u1.ID); len(got.Providers) != 2 {
		t.Fatalf("providers=%v", got.Providers)
	}
	if err := s.BindOAuth(u2.ID, "google", "g"); !errors.Is(err, ErrIdentityBound) {
		t.Fatalf("takeover err=%v", err)
	}
}

type fakeOAuthVerifier struct{ identities map[string]OAuthIdentity }

func (v *fakeOAuthVerifier) Verify(provider, code string) (OAuthIdentity, error) {
	id, ok := v.identities[provider+":"+code]
	if !ok {
		return OAuthIdentity{}, ErrOAuthInvalid
	}
	return id, nil
}
