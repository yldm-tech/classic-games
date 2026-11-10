package community

import (
	"forgeplay/server/internal/storage"
	"github.com/gin-gonic/gin"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCommunityHTTP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	r := gin.New()
	auth := func(c *gin.Context) { c.Set("user_id", "u1"); c.Next() }
	RegisterRoutes(r, NewService(repo), auth, auth)
	request := func(method, path, body string) *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		q := httptest.NewRequest(method, path, strings.NewReader(body))
		q.Header.Set("Content-Type", "application/json")
		r.ServeHTTP(w, q)
		return w
	}
	w := request(http.MethodPost, "/api/v1/games/g1/community/rating", `{"value":4}`)
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"my_rating":4`) {
		t.Fatalf("rating %d %s", w.Code, w.Body.String())
	}
	w = request(http.MethodPost, "/api/v1/games/g1/community/posts", `{"content":"hello"}`)
	if w.Code != 201 {
		t.Fatalf("post %d %s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/games/g1/community", "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"hello"`) {
		t.Fatalf("get %d %s", w.Code, w.Body.String())
	}
}
