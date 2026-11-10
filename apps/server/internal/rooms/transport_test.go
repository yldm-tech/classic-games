package rooms

import (
	"encoding/json"
	"forgeplay/server/internal/storage"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAuthoritativeMatchHTTP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo)
	room, _ := s.Create("host")
	_, _ = s.Join(room.Code, "guest")
	_, _ = s.Ready(room.ID, "host", true)
	_, _ = s.Ready(room.ID, "guest", true)
	_, _ = s.Start(room.ID, "host")

	router := gin.New()
	auth := func(c *gin.Context) {
		c.Set("user_id", c.GetHeader("X-Test-User"))
		c.Next()
	}
	RegisterRoutes(router, s, auth)
	call := func(user, method, path, body string) *httptest.ResponseRecorder {
		t.Helper()
		request := httptest.NewRequest(method, path, strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Test-User", user)
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		return response
	}

	inputPath := "/api/v1/rooms/" + room.ID + "/input"
	snapshotPath := "/api/v1/rooms/" + room.ID + "/snapshot"
	response := call("host", http.MethodPost, inputPath, `{"seq":1,"move_x":1,"move_y":-1,"fire":true}`)
	if response.Code != http.StatusOK {
		t.Fatalf("input: %d %s", response.Code, response.Body.String())
	}
	var submitted MatchSnapshot
	if err := json.Unmarshal(response.Body.Bytes(), &submitted); err != nil || submitted.Tick != 1 {
		t.Fatalf("input snapshot: %+v, %v", submitted, err)
	}

	response = call("guest", http.MethodGet, snapshotPath, "")
	if response.Code != http.StatusOK {
		t.Fatalf("snapshot: %d %s", response.Code, response.Body.String())
	}
	var observed MatchSnapshot
	if err := json.Unmarshal(response.Body.Bytes(), &observed); err != nil || observed.Player("guest") == nil || observed.Player("guest").Health != 90 {
		t.Fatalf("observed snapshot: %+v, %v", observed, err)
	}

	if response = call("host", http.MethodPost, inputPath, `{"seq":1}`); response.Code != http.StatusConflict {
		t.Fatalf("stale input: %d %s", response.Code, response.Body.String())
	}
	if response = call("host", http.MethodPost, inputPath, `{"seq":2,"move_x":2}`); response.Code != http.StatusBadRequest {
		t.Fatalf("invalid input: %d %s", response.Code, response.Body.String())
	}
	if response = call("outsider", http.MethodGet, snapshotPath, ""); response.Code != http.StatusForbidden {
		t.Fatalf("outsider snapshot: %d %s", response.Code, response.Body.String())
	}
}
