package httpx

import (
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestWriteError(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	WriteError(c, 422, "DSL_INVALID", "bad")

	if w.Code != 422 {
		t.Fatalf("状态码 %d, 期望 422", w.Code)
	}
	var env Envelope
	if err := json.Unmarshal(w.Body.Bytes(), &env); err != nil {
		t.Fatal(err)
	}
	if env.Error.Code != "DSL_INVALID" || env.Error.Message != "bad" {
		t.Errorf("信封内容不符: %+v", env.Error)
	}
}
