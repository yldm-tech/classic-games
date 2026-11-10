package auth

import (
	"crypto/rand"
	"encoding/hex"
	"errors"

	"gorm.io/gorm"
)

// GormUserRepo 是 UserRepo 的 GORM 实现(用户持久化)。
// 验证码与 token 是短时态，由 Service 的短时存储维护，不与用户记录混表。
type GormUserRepo struct{ db *gorm.DB }

func IdentityMigrationModels() []any { return []any{&User{}, &LoginIdentity{}} }

func AfterIdentityMigration(db *gorm.DB) error {
	return db.Exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_nonempty ON users(phone) WHERE phone <> ''").Error
}

func NewGormUserRepo(db *gorm.DB) (*GormUserRepo, error) {
	if db == nil {
		return nil, gorm.ErrInvalidDB
	}
	return &GormUserRepo{db: db}, nil
}

func (r *GormUserRepo) Update(u User) error { return r.db.Save(&u).Error }
func (r *GormUserRepo) FindIdentity(p, s string) (LoginIdentity, bool) {
	var v LoginIdentity
	e := r.db.First(&v, "provider = ? AND subject = ?", p, s).Error
	return v, e == nil
}
func (r *GormUserRepo) BindIdentity(v LoginIdentity) error {
	var old LoginIdentity
	e := r.db.First(&old, "provider = ? AND subject = ?", v.Provider, v.Subject).Error
	if e == nil && old.UserID != v.UserID {
		return ErrIdentityBound
	}
	if e != nil && !errors.Is(e, gorm.ErrRecordNotFound) {
		return e
	}
	return r.db.FirstOrCreate(&v).Error
}
func (r *GormUserRepo) ListIdentities(uid string) ([]LoginIdentity, error) {
	var out []LoginIdentity
	e := r.db.Where("user_id = ?", uid).Order("provider").Find(&out).Error
	return out, e
}

func (r *GormUserRepo) FindByPhone(phone string) (User, bool) {
	var u User
	err := r.db.First(&u, "phone = ?", phone).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return User{}, false
	}
	return u, err == nil
}

func (r *GormUserRepo) FindByID(id string) (User, bool) {
	var u User
	err := r.db.First(&u, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return User{}, false
	}
	return u, err == nil
}

func (r *GormUserRepo) Create(u User) (User, error) {
	if u.ID == "" {
		b := make([]byte, 8)
		_, _ = rand.Read(b)
		u.ID = "user_" + hex.EncodeToString(b)
	}
	if err := r.db.Create(&u).Error; err != nil {
		return User{}, err
	}
	return u, nil
}

func (r *GormUserRepo) Delete(id string) error {
	if err := r.db.Where("user_id = ?", id).Delete(&LoginIdentity{}).Error; err != nil {
		return err
	}
	res := r.db.Delete(&User{}, "id = ?", id)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrUserNotFound
	}
	return nil
}
