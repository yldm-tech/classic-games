package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHTTPSenderSendsAuthenticatedJSON(t *testing.T) {
	var got map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer secret" {
			t.Error("缺 Authorization")
		}
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		w.WriteHeader(http.StatusAccepted)
	}))
	defer srv.Close()
	s := NewHTTPSender(srv.URL, "secret", time.Second)
	if err := s.Send("13800000000", "123456"); err != nil {
		t.Fatal(err)
	}
	if got["phone"] != "13800000000" || got["code"] != "123456" {
		t.Fatalf("payload=%v", got)
	}
}

func TestHTTPSenderRejectsGatewayFailure(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { http.Error(w, "quota", 429) }))
	defer srv.Close()
	if err := NewHTTPSender(srv.URL, "", time.Second).Send("1", "2"); err == nil {
		t.Fatal("非 2xx 应报错")
	}
}

type failingSender struct{}

func (failingSender) Send(string, string) error { return ErrSendFailed }

func TestSendCodeFailureDoesNotConsumeCooldown(t *testing.T) {
	svc := NewService(failingSender{}, NewMemUserRepo())
	if err := svc.SendCode("13800000000"); err != ErrSendFailed {
		t.Fatalf("got %v", err)
	}
	if err := svc.SendCode("13800000000"); err != ErrSendFailed {
		t.Fatalf("发送失败后不应被 cooldown 覆盖: %v", err)
	}
}
