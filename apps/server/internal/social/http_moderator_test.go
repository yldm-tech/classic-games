package social

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHTTPModerator(t *testing.T) {
	var auth, text string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		var b map[string]string
		_ = json.NewDecoder(r.Body).Decode(&b)
		text = b["text"]
		_ = json.NewEncoder(w).Encode(map[string]bool{"allowed": text != "reject"})
	}))
	defer srv.Close()
	m := NewHTTPModerator(srv.URL, "token", time.Second)
	if e := m.Check("safe"); e != nil {
		t.Fatal(e)
	}
	if auth != "Bearer token" || text != "safe" {
		t.Fatalf("auth=%q text=%q", auth, text)
	}
	if e := m.Check("reject"); e != ErrContentRejected {
		t.Fatalf("reject=%v", e)
	}
	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(503) }))
	defer bad.Close()
	if e := NewHTTPModerator(bad.URL, "", time.Second).Check("safe"); e == nil {
		t.Fatal("provider failure must fail closed")
	}
}
func TestChainKeepsKeywordDefense(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte(`{"allowed":true}`)) }))
	defer srv.Close()
	chain := ChainModerator{NewKeywordModerator("blocked"), NewHTTPModerator(srv.URL, "", time.Second)}
	if e := chain.Check("b.l.o.c.k.e.d"); e != ErrContentRejected {
		t.Fatalf("keyword bypass=%v", e)
	}
}
