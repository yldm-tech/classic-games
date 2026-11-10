package app

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// POST /auth/guest is public and unmetered, so a guest identity costs nothing to mint. If the AI quota were keyed on the
// resulting user id, anyone could reset their daily allowance on the paid LLM endpoints by asking for another guest
// token. Guests therefore share the allowance of the address they arrive from.
func TestGuestTokensShareOneQuotaBucket(t *testing.T) {
	cfg := applicationTestConfig(t)
	instance, err := New(context.Background(), cfg, Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if closeErr := instance.Close(); closeErr != nil {
			t.Errorf("Close: %v", closeErr)
		}
	})
	engine := instance.engine

	newGuest := func() string {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/guest", nil)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("guest login = %d %s", w.Code, w.Body.String())
		}
		var body struct {
			Token string `json:"token"`
		}
		if unmarshalErr := json.Unmarshal(w.Body.Bytes(), &body); unmarshalErr != nil || body.Token == "" {
			t.Fatalf("guest token: %v body=%s", unmarshalErr, w.Body.String())
		}
		return body.Token
	}
	usedBy := func(token string) int {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/ai/quota", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		engine.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("quota = %d %s", w.Code, w.Body.String())
		}
		var snapshot struct {
			Used int `json:"used"`
		}
		if unmarshalErr := json.Unmarshal(w.Body.Bytes(), &snapshot); unmarshalErr != nil {
			t.Fatal(unmarshalErr)
		}
		return snapshot.Used
	}

	baselineBytes, err := os.ReadFile(filepath.Join(repositoryRoot(t), "apps", "client", "runtime", "shooter", "baseline.dsl.json"))
	if err != nil {
		t.Fatal(err)
	}
	var baseline any
	if unmarshalErr := json.Unmarshal(baselineBytes, &baseline); unmarshalErr != nil {
		t.Fatal(unmarshalErr)
	}

	first := newGuest()
	payload, err := json.Marshal(map[string]any{"runtime": "shooter@1.0.0", "current_dsl": baseline, "prompt": "把飞机换成猫"})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/ai/mod", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+first)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("ai/mod = %d %s", w.Code, w.Body.String())
	}
	if used := usedBy(first); used != 1 {
		t.Fatalf("first guest used = %d, want 1", used)
	}

	second := newGuest()
	if used := usedBy(second); used != 1 {
		t.Fatalf("a second guest token from the same address reports used = %d, want 1 — minting a guest must not reset the AI allowance", used)
	}
}
