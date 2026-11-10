package feedback

import (
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/yldm-tech/classic-games/apps/server/internal/social"
	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
	"net/http"
)

func RegisterRoutes(r gin.IRouter, s *Service, auth gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if auth != nil {
		g.Use(auth)
	}
	g.POST("/feedback", submitFeedback(s))
}

// submitFeedback godoc
// @Summary  提交用户反馈
// @Tags     feedback
// @Accept   json
// @Produce  json
// @Param    body  body      object{content=string}  true  "反馈内容,1-2000 字符"
// @Success  201   {object}  Item
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / FEEDBACK_INVALID"
// @Failure  422   {object}  httpx.Envelope  "CONTENT_REJECTED(内容审核不通过)"
// @Failure  503   {object}  httpx.Envelope  "MODERATION_UNAVAILABLE(审核服务不可用)"
// @Router   /feedback [post]
func submitFeedback(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Content string `json:"content"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		item, err := s.Submit(c.GetString("user_id"), b.Content)
		if err != nil {
			code := http.StatusServiceUnavailable
			errorCode := "MODERATION_UNAVAILABLE"
			if errors.Is(err, ErrInvalid) {
				code = http.StatusBadRequest
				errorCode = "FEEDBACK_INVALID"
			} else if errors.Is(err, social.ErrContentRejected) {
				code = http.StatusUnprocessableEntity
				errorCode = "CONTENT_REJECTED"
			}
			httpx.WriteError(c, code, errorCode, err.Error())
			return
		}
		c.JSON(http.StatusCreated, item)
	}
}
