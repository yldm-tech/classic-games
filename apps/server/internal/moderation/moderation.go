// Package moderation 实现举报与屏蔽(docs/14-security-compliance.md、09-api-design.md)。
// 内容审核队列的裁决在 games 域(Decide);此处管用户侧的举报与屏蔽。
package moderation

import (
	"errors"
	"strings"
	"time"
)

// TargetType 举报对象类型。
type TargetType string

const (
	TargetGame    TargetType = "game"
	TargetComment TargetType = "comment"
	TargetUser    TargetType = "user"
)

var (
	ErrBadTarget = errors.New("moderation: 非法举报对象类型")
	ErrNoReason  = errors.New("moderation: 举报理由为空")
	ErrNoTarget  = errors.New("moderation: 举报对象为空")
	ErrSelf      = errors.New("moderation: 不能对自己执行此操作")
)

type Report struct {
	ID         string     `json:"id" gorm:"primaryKey"`
	ReporterID string     `json:"reporter_id"`
	TargetType TargetType `json:"target_type"`
	TargetID   string     `json:"target_id"`
	Reason     string     `json:"reason"`
}

type BlockEntry struct {
	UserID    string    `json:"-"`
	BlockedID string    `json:"user_id"`
	BlockedAt time.Time `json:"blocked_at"`
}

type Repository interface {
	AddReport(r Report) (Report, error)
	SetBlock(userID, blockedID string, blocked bool) error
	IsBlocked(userID, blockedID string) (bool, error)
	ListBlocked(userID string) ([]string, error)
	ListBlockEntries(userID string) ([]BlockEntry, error)
	SetHiddenGame(userID, gameID string, hidden bool) error
	IsGameHidden(userID, gameID string) (bool, error)
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func validTarget(t TargetType) bool {
	return t == TargetGame || t == TargetComment || t == TargetUser
}

// Report 提交举报(内容平台必备)。
func (s *Service) Report(reporterID string, t TargetType, targetID, reason string) (Report, error) {
	if !validTarget(t) {
		return Report{}, ErrBadTarget
	}
	if strings.TrimSpace(targetID) == "" {
		return Report{}, ErrNoTarget
	}
	if strings.TrimSpace(reason) == "" {
		return Report{}, ErrNoReason
	}
	if t == TargetUser && targetID == reporterID {
		return Report{}, ErrSelf // 不能举报自己
	}
	return s.repo.AddReport(Report{
		ReporterID: reporterID, TargetType: t, TargetID: targetID, Reason: reason,
	})
}

// Block / Unblock 屏蔽用户;幂等。
func (s *Service) Block(userID, blockedID string) error {
	if userID == blockedID {
		return ErrSelf // 不能屏蔽自己
	}
	return s.repo.SetBlock(userID, blockedID, true)
}
func (s *Service) Unblock(userID, blockedID string) error {
	return s.repo.SetBlock(userID, blockedID, false)
}

func (s *Service) IsBlocked(userID, blockedID string) (bool, error) {
	return s.repo.IsBlocked(userID, blockedID)
}
func (s *Service) ListBlocked(userID string) ([]string, error) {
	return s.repo.ListBlocked(userID)
}
func (s *Service) ListBlockEntries(userID string) ([]BlockEntry, error) {
	return s.repo.ListBlockEntries(userID)
}

func (s *Service) HideGame(userID, gameID string) error {
	if strings.TrimSpace(userID) == "" || strings.TrimSpace(gameID) == "" {
		return ErrNoTarget
	}
	return s.repo.SetHiddenGame(userID, gameID, true)
}
func (s *Service) IsGameHidden(userID, gameID string) (bool, error) {
	if userID == "" {
		return false, nil
	}
	return s.repo.IsGameHidden(userID, gameID)
}
