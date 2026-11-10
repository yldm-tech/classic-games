package analytics

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"forgeplay/server/internal/storage"
	"github.com/gin-gonic/gin"
)

func TestTransportRecordAndSummary(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	r := gin.New()
	RegisterRoutes(r, NewService(repo), func(c *gin.Context) { c.Set("user_id", "u1") }, func(c *gin.Context) {})
	body, _ := json.Marshal(Event{Name: GameViewed, SessionID: "s1", TargetID: "g1"})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/analytics/events", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("record status=%d body=%s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/analytics/summary", nil))
	if w.Code != 200 {
		t.Fatalf("summary status=%d", w.Code)
	}
	var got Summary
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	if got.GameViewers != 1 {
		t.Fatalf("summary=%+v", got)
	}
}
