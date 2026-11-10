package replays

import (
	"forgeplay/server/internal/storage"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestReplayHTTPUsesAuthUser(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	r := gin.New()
	auth := func(c *gin.Context) { c.Set("user_id", "token_user"); c.Next() }
	RegisterRoutes(r, NewService(repo), auth)
	body := `{"duration_ms":1000,"frames":[{"at_ms":0,"hp":100},{"at_ms":1000,"hp":90,"score":10}]}`
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/games/g/replays", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusCreated || !strings.Contains(w.Body.String(), `"user_id":"token_user"`) {
		t.Fatalf("post %d %s", w.Code, w.Body.String())
	}
	w = httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/v1/games/g/replays/token_user", nil))
	if w.Code != 200 {
		t.Fatalf("get %d %s", w.Code, w.Body.String())
	}
}
