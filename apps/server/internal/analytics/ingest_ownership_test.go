package analytics

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"forgeplay/server/internal/storage"
)

// Ingestion is unauthenticated, so the row's identity and clock have to be server-owned. Binding the persisted Event
// directly let a caller pick the primary key — colliding with or overwriting an existing row — and backdate created_at,
// which is what /analytics/summary computes its funnel from.
func TestIngestIgnoresClientSuppliedIDAndTimestamp(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, err := storage.Open("")
	if err != nil {
		t.Fatal(err)
	}
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, err := NewGormRepo(db)
	if err != nil {
		t.Fatal(err)
	}
	r := gin.New()
	RegisterRoutes(r, NewService(repo), func(c *gin.Context) {}, func(c *gin.Context) {})

	forged := time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)
	body, err := json.Marshal(map[string]any{
		"id": "evt_attacker_chosen", "name": GameViewed, "session_id": "s1", "target_id": "g1", "created_at": forged,
	})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/analytics/events", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("record status=%d body=%s", w.Code, w.Body.String())
	}

	stored, err := repo.List()
	if err != nil {
		t.Fatal(err)
	}
	if len(stored) != 1 {
		t.Fatalf("stored %d events, want 1", len(stored))
	}
	if stored[0].ID == "evt_attacker_chosen" {
		t.Fatal("the client chose the primary key — an anonymous caller could overwrite any existing event row")
	}
	if stored[0].CreatedAt.Year() == forged.Year() {
		t.Fatalf("the client backdated created_at to %s", stored[0].CreatedAt)
	}
	if stored[0].Name != GameViewed || stored[0].SessionID != "s1" || stored[0].TargetID != "g1" {
		t.Fatalf("client-owned fields were not preserved: %+v", stored[0])
	}
}
