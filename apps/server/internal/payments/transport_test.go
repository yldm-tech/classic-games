package payments

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"forgeplay/server/internal/storage"
	"github.com/gin-gonic/gin"
)

func TestPaymentOrderHTTP(t *testing.T) {
	gin.SetMode(gin.TestMode)
	db, _ := storage.Open("")
	if migrateErr := db.AutoMigrate(MigrationModels()...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	repo, _ := NewGormRepo(db)
	s := NewService(repo, "secret", []Product{{ID: "p", Amount: 100, Currency: "CNY", Kind: "points", Value: 1}}, nil)
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
	created := call(http.MethodPost, "/api/v1/payments/orders", `{"product_id":"p"}`)
	if created.Code != http.StatusCreated {
		t.Fatalf("create %d %s", created.Code, created.Body.String())
	}
	var order Order
	if err := json.Unmarshal(created.Body.Bytes(), &order); err != nil || order.ID == "" {
		t.Fatalf("create body %s err=%v", created.Body.String(), err)
	}
	listed := call(http.MethodGet, "/api/v1/payments/orders", "")
	if listed.Code != 200 || !strings.Contains(listed.Body.String(), order.ID) {
		t.Fatalf("list %d %s", listed.Code, listed.Body.String())
	}
	got := call(http.MethodGet, "/api/v1/payments/orders/"+order.ID, "")
	if got.Code != 200 || !strings.Contains(got.Body.String(), `"status":"pending"`) {
		t.Fatalf("get %d %s", got.Code, got.Body.String())
	}
}
