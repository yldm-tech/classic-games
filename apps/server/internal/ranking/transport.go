package ranking

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"forgeplay/server/pkg/i18n"
)

// RegisterRoutes 挂载榜单端点(docs/09-api-design.md)。
func RegisterRoutes(r gin.IRouter, svc *Service, optionalMW ...gin.HandlerFunc) {
	g := r.Group("/api/v1")
	if len(optionalMW) > 0 && optionalMW[0] != nil {
		g.Use(optionalMW[0])
	}
	g.GET("/ranking", list(svc))
}

// list godoc
// @Summary  榜单(热门/新作/飙升)
// @Tags     ranking
// @Produce  json
// @Param    type   query     string  false  "hot|new|rising"
// @Param    limit  query     int     false  "条数"
// @Success  200    {object}  map[string]interface{}
// @Router   /ranking [get]
func list(svc *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		kind := c.DefaultQuery("type", "hot")
		limit, _ := strconv.Atoi(c.Query("limit"))
		items, err := svc.RankedFilteredFor(c.GetString("user_id"), kind, limit, c.Query("runtime"), c.Query("category"))
		if err != nil {
			if errors.Is(err, ErrUnknownType) {
				i18n.WriteErrorDetail(c, http.StatusBadRequest, "BAD_REQUEST", err.Error())
				return
			}
			i18n.WriteErrorDetail(c, http.StatusInternalServerError, "INTERNAL", err.Error())
			return
		}
		lang := c.DefaultQuery("lang", "zh")
		for i := range items {
			items[i].Game = items[i].Game.Localized(lang)
		}
		c.JSON(http.StatusOK, gin.H{"type": kind, "items": items})
	}
}
