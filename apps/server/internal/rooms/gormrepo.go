package rooms

import (
	"errors"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"time"
)

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Room{}, &Member{}, &Match{}, &PlayerState{}} }

func AfterMigration(db *gorm.DB) error {
	var existing []Room
	if err := db.Find(&existing).Error; err != nil {
		return err
	}
	for _, room := range existing {
		var count int64
		if err := db.Model(&Member{}).Where("room_id = ?", room.ID).Count(&count).Error; err != nil {
			return err
		}
		if err := db.Model(&Room{}).Where("id = ?", room.ID).Update("member_count", count).Error; err != nil {
			return err
		}
	}
	return nil
}

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db}, nil
}
func (r *GormRepo) Create(v Room) (Room, error) { e := r.db.Create(&v).Error; return v, e }
func (r *GormRepo) ByID(id string) (Room, error) {
	var v Room
	e := r.db.Preload("Members", func(db *gorm.DB) *gorm.DB { return db.Order("joined_at") }).First(&v, "id = ?", id).Error
	if errors.Is(e, gorm.ErrRecordNotFound) {
		e = ErrNotFound
	}
	return v, e
}
func (r *GormRepo) ByCode(code string) (Room, error) {
	var v Room
	e := r.db.Preload("Members").First(&v, "code = ?", code).Error
	if errors.Is(e, gorm.ErrRecordNotFound) {
		e = ErrNotFound
	}
	return v, e
}
func (r *GormRepo) JoinMember(v Member, limit int) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		var existing Member
		if err := tx.First(&existing, "room_id = ? AND user_id = ?", v.RoomID, v.UserID).Error; err == nil {
			return nil
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		result := tx.Model(&Room{}).Where("id = ? AND status = ? AND member_count < ?", v.RoomID, "waiting", limit).UpdateColumn("member_count", gorm.Expr("member_count + 1"))
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected == 0 {
			var room Room
			if err := tx.First(&room, "id = ?", v.RoomID).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return ErrNotFound
				}
				return err
			}
			if room.Status != "waiting" {
				return ErrStarted
			}
			return ErrFull
		}
		return tx.Create(&v).Error
	})
}
func (r *GormRepo) SetReady(id, user string, on bool) error {
	return r.db.Model(&Member{}).Where("room_id = ? AND user_id = ?", id, user).Update("ready", on).Error
}

func (r *GormRepo) StartMatch(id string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		result := tx.Model(&Room{}).Where("id = ? AND status = ?", id, "waiting").Update("status", MatchStarted)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected == 0 {
			return ErrStarted
		}
		var members []Member
		if err := tx.Where("room_id = ?", id).Order("joined_at").Find(&members).Error; err != nil {
			return err
		}
		if len(members) < 2 {
			return ErrNotReady
		}
		for _, member := range members {
			if !member.Ready {
				return ErrNotReady
			}
		}
		match := newMatch(id, members, time.Now().UTC())
		return tx.Create(&match).Error
	})
}

func (r *GormRepo) MatchByRoom(id string) (Match, error) {
	var match Match
	err := r.db.Preload("Players").First(&match, "room_id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		err = ErrNotStarted
	}
	return match, err
}

func (r *GormRepo) MutateMatch(id string, mutate func(*Match) error) (Match, error) {
	var match Match
	err := r.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Preload("Players").First(&match, "room_id = ?", id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrNotStarted
			}
			return err
		}
		if err := mutate(&match); err != nil {
			return err
		}
		if err := tx.Omit("Players").Save(&match).Error; err != nil {
			return err
		}
		for i := range match.Players {
			if err := tx.Save(&match.Players[i]).Error; err != nil {
				return err
			}
		}
		if match.Status == MatchFinished {
			return tx.Model(&Room{}).Where("id = ?", id).Update("status", MatchFinished).Error
		}
		return nil
	})
	return match, err
}
