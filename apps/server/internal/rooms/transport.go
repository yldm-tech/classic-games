package rooms

import (
	"github.com/gin-gonic/gin"
	"github.com/yldm-tech/classic-games/apps/server/pkg/httpx"
	"net/http"
)

func RegisterRoutes(r gin.IRouter, s *Service, auth gin.HandlerFunc) {
	g := r.Group("/api/v1/rooms")
	if auth != nil {
		g.Use(auth)
	}
	g.POST("", createRoom(s))
	g.POST("/join", joinRoom(s))
	g.GET("/:id", getRoom(s))
	g.POST("/:id/ready", setRoomReady(s))
	g.POST("/:id/start", startRoom(s))
	g.GET("/:id/snapshot", roomSnapshot(s))
	g.POST("/:id/input", submitRoomInput(s))
}

// writeRoom 是各 room handler 共用的响应写出:失败按 roomErrorStatus 映射状态码,成功写指定状态码 + Room。
func writeRoom(c *gin.Context, v Room, e error, status int) {
	if e != nil {
		code := roomErrorStatus(e)
		httpx.WriteError(c, code, "ROOM_INVALID", e.Error())
		return
	}
	c.JSON(status, v)
}

// writeMatchSnapshot 是对局类 handler(snapshot/input)共用的响应写出。
func writeMatchSnapshot(c *gin.Context, v MatchSnapshot, e error) {
	if e != nil {
		httpx.WriteError(c, roomErrorStatus(e), "MATCH_INVALID", e.Error())
		return
	}
	c.JSON(http.StatusOK, v)
}

// createRoom godoc
// @Summary  创建房间(创建者自动加入并成为房主)
// @Tags     rooms
// @Produce  json
// @Success  201 {object}  Room
// @Failure  400 {object}  httpx.Envelope  "ROOM_INVALID"
// @Router   /rooms [post]
func createRoom(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) { v, e := s.Create(c.GetString("user_id")); writeRoom(c, v, e, http.StatusCreated) }
}

// joinRoom godoc
// @Summary  按房间码加入房间
// @Tags     rooms
// @Accept   json
// @Produce  json
// @Param    body  body      object{code=string}  true  "房间码"
// @Success  200   {object}  Room
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / ROOM_INVALID(已满/已开始/不存在)"
// @Router   /rooms/join [post]
func joinRoom(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Code string `json:"code"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.Join(b.Code, c.GetString("user_id"))
		writeRoom(c, v, e, 200)
	}
}

// getRoom godoc
// @Summary  查询房间详情
// @Tags     rooms
// @Produce  json
// @Param    id  path      string  true  "room id"
// @Success  200 {object}  Room
// @Failure  403 {object}  httpx.Envelope  "ROOM_INVALID(非房间成员)"
// @Failure  404 {object}  httpx.Envelope  "ROOM_INVALID(房间不存在)"
// @Router   /rooms/{id} [get]
func getRoom(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) { v, e := s.Get(c.Param("id"), c.GetString("user_id")); writeRoom(c, v, e, 200) }
}

// setRoomReady godoc
// @Summary  设置本人在房间内的准备状态
// @Tags     rooms
// @Accept   json
// @Produce  json
// @Param    id    path      string  true  "room id"
// @Param    body  body      object{ready=bool}  true  "准备状态"
// @Success  200   {object}  Room
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / ROOM_INVALID"
// @Router   /rooms/{id}/ready [post]
func setRoomReady(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var b struct {
			Ready bool `json:"ready"`
		}
		if c.ShouldBindJSON(&b) != nil {
			httpx.WriteError(c, 400, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.Ready(c.Param("id"), c.GetString("user_id"), b.Ready)
		writeRoom(c, v, e, 200)
	}
}

// startRoom godoc
// @Summary  开始对局(仅房主,需全员准备且 >=2 人)
// @Tags     rooms
// @Produce  json
// @Param    id  path      string  true  "room id"
// @Success  200 {object}  Room
// @Failure  400 {object}  httpx.Envelope  "ROOM_INVALID(未全员准备)"
// @Failure  403 {object}  httpx.Envelope  "ROOM_INVALID(非房主)"
// @Router   /rooms/{id}/start [post]
func startRoom(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) { v, e := s.Start(c.Param("id"), c.GetString("user_id")); writeRoom(c, v, e, 200) }
}

// roomSnapshot godoc
// @Summary  取当前对局快照(用于轮询)
// @Tags     rooms
// @Produce  json
// @Param    id  path      string  true  "room id"
// @Success  200 {object}  MatchSnapshot
// @Failure  400 {object}  httpx.Envelope  "MATCH_INVALID"
// @Router   /rooms/{id}/snapshot [get]
func roomSnapshot(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		v, e := s.Snapshot(c.Param("id"), c.GetString("user_id"))
		writeMatchSnapshot(c, v, e)
	}
}

// submitRoomInput godoc
// @Summary  提交一帧权威对局输入(移动/开火)
// @Tags     rooms
// @Accept   json
// @Produce  json
// @Param    id    path      string       true  "room id"
// @Param    body  body      PlayerInput  true  "本帧输入,seq 需单调递增"
// @Success  200   {object}  MatchSnapshot
// @Failure  400   {object}  httpx.Envelope  "BAD_REQUEST / MATCH_INVALID(非法输入/过期序号/对局未开始或已结束)"
// @Router   /rooms/{id}/input [post]
func submitRoomInput(s *Service) gin.HandlerFunc {
	return func(c *gin.Context) {
		var input PlayerInput
		if c.ShouldBindJSON(&input) != nil {
			httpx.WriteError(c, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
			return
		}
		v, e := s.SubmitInput(c.Param("id"), c.GetString("user_id"), input)
		writeMatchSnapshot(c, v, e)
	}
}

func roomErrorStatus(err error) int {
	switch err {
	case ErrNotFound:
		return http.StatusNotFound
	case ErrForbidden, ErrPlayBlocked:
		return http.StatusForbidden
	case ErrStaleInput, ErrMatchFinished, ErrNotStarted, ErrStarted:
		return http.StatusConflict
	default:
		return http.StatusBadRequest
	}
}
