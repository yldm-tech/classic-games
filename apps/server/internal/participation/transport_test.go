package participation

import (
	"forgeplay/server/internal/storage"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestParticipationHTTP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo, func(id string) bool { return id == "e1" }, func(string) int { return 500 })
	r := gin.New()
	auth := func(c *gin.Context) { c.Set("user_id", "u"); c.Next() }
	RegisterRoutes(r, s, auth)
	call := func(method, path, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		q := httptest.NewRequest(method, path, strings.NewReader(body))
		q.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, q)
		return w
	}
	if w := call(http.MethodPost, "/api/v1/events/e1/join", ""); w.Code != 200 {
		t.Fatalf("join %d %s", w.Code, w.Body.String())
	}
	if w := call(http.MethodGet, "/api/v1/events/joined", ""); w.Code != 200 || !strings.Contains(w.Body.String(), "e1") {
		t.Fatalf("joined %d %s", w.Code, w.Body.String())
	}
	if w := call(http.MethodPost, "/api/v1/earnings/withdrawals", `{"amount":501}`); w.Code != 409 {
		t.Fatalf("overdraw %d %s", w.Code, w.Body.String())
	}
	if w := call(http.MethodPost, "/api/v1/earnings/withdrawals", `{"amount":500}`); w.Code != http.StatusAccepted {
		t.Fatalf("withdraw %d %s", w.Code, w.Body.String())
	}
	if w := call(http.MethodGet, "/api/v1/earnings/withdrawals", ""); w.Code != 200 || !strings.Contains(w.Body.String(), `"status":"pending"`) {
		t.Fatalf("list withdrawals %d %s", w.Code, w.Body.String())
	}
}
