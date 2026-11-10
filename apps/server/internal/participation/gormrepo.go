package participation

import (
	"strings"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type GormRepo struct{ db *gorm.DB }

func MigrationModels() []any { return []any{&Withdrawal{}, &EventJoin{}} }

func AfterMigration(db *gorm.DB) error {
	return db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_withdrawals_one_pending ON withdrawals(user_id) WHERE status = 'pending'`).Error
}

func NewGormRepo(db *gorm.DB) (*GormRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormRepo{db}, nil
}
func (r *GormRepo) PendingWithdrawal(user string) (bool, error) {
	var n int64
	e := r.db.Model(&Withdrawal{}).Where("user_id = ? AND status = ?", user, "pending").Count(&n).Error
	return n > 0, e
}
func (r *GormRepo) ListWithdrawals(user string) ([]Withdrawal, error) {
	var rows []Withdrawal
	// id DESC is a stable tiebreaker for rows sharing a timestamp, matching the ordering used by the other domains.
	e := r.db.Where("user_id = ?", user).Order("created_at DESC, id DESC").Find(&rows).Error
	if e != nil {
		return nil, e
	}
	if rows == nil {
		rows = []Withdrawal{}
	}
	return rows, nil
}

func (r *GormRepo) SumReserved(user string) (int, error) {
	var sum int
	e := r.db.Model(&Withdrawal{}).
		Where("user_id = ? AND status IN ?", user, []string{"pending", "paid"}).
		Select("COALESCE(SUM(amount),0)").
		Scan(&sum).Error
	return sum, e
}

func (r *GormRepo) CreateWithdrawal(v Withdrawal) (Withdrawal, error) {
	err := r.db.Create(&v).Error
	if isUniqueViolation(err) {
		// 部分唯一索引拦下的并发重复 → 归一为业务级 ErrDuplicate(与 PendingWithdrawal 预检口径一致)。
		return Withdrawal{}, ErrDuplicate
	}
	return v, err
}

// isUniqueViolation 跨方言识别唯一约束冲突(TranslateError 未开启,按错误文本匹配)。
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "unique constraint failed") || // SQLite
		strings.Contains(msg, "duplicate key value") || // PostgreSQL
		strings.Contains(msg, "23505") // PostgreSQL SQLSTATE
}
func (r *GormRepo) Join(v EventJoin) (EventJoin, error) {
	e := r.db.Clauses(clause.OnConflict{DoNothing: true}).Create(&v).Error
	return v, e
}
func (r *GormRepo) Joined(user string) ([]string, error) {
	var rows []EventJoin
	e := r.db.Where("user_id = ?", user).Find(&rows).Error
	out := make([]string, len(rows))
	for i, v := range rows {
		out[i] = v.EventID
	}
	return out, e
}
