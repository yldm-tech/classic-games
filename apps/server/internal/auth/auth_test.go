package auth

import (
	"errors"
	"fmt"
	"forgeplay/server/internal/storage"
	"golang.org/x/crypto/bcrypt"
	"testing"
	"time"
)

func TestAuthRuntimeSurvivesRestartAndDropsExpired(t *testing.T) {
	db, _ := storage.Open("")
	models := append(IdentityMigrationModels(), RuntimeMigrationModels()...)
	if migrateErr := db.AutoMigrate(models...); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	if migrateErr := AfterIdentityMigration(db); migrateErr != nil {
		t.Fatal(migrateErr)
	}
	users, _ := NewGormUserRepo(db)
	store, _ := NewGormRuntimeStore(db)
	sender := NewLogSender()
	s, e := NewServiceWithRuntimeStore(sender, users, store)
	if e != nil {
		t.Fatal(e)
	}
	if e = s.SendCode("13800000000"); e != nil {
		t.Fatal(e)
	}
	persisted, _ := store.Load()
	if persisted.Codes["13800000000"].CodeHash == sender.Last["13800000000"] || persisted.Codes["13800000000"].CodeHash == "" {
		t.Fatal("verification code persisted in plaintext")
	}
	again, e := NewServiceWithRuntimeStore(sender, users, store)
	if e != nil {
		t.Fatal(e)
	}
	if e = again.SendCode("13800000000"); !errors.Is(e, ErrRateLimited) {
		t.Fatalf("cooldown reset: %v", e)
	}
	token, u, e := again.Login("13800000000", sender.Last["13800000000"])
	if e != nil {
		t.Fatal(e)
	}
	persisted, _ = store.Load()
	if _, plain := persisted.Tokens[token]; plain {
		t.Fatal("bearer token persisted in plaintext")
	}
	if _, hashed := persisted.Tokens[tokenKey(token)]; !hashed {
		t.Fatal("token digest missing")
	}
	third, e := NewServiceWithRuntimeStore(sender, users, store)
	if e != nil {
		t.Fatal(e)
	}
	if id, ok := third.UserIDForToken(token); !ok || id != u.ID {
		t.Fatalf("session lost %q %v", id, ok)
	}
	third.mu.Lock()
	third.tokens[tokenKey(token)] = tokenEntry{userID: u.ID, expiresAt: time.Now().Add(-time.Second)}
	_ = third.saveRuntimeLocked()
	third.mu.Unlock()
	fourth, e := NewServiceWithRuntimeStore(sender, users, store)
	if e != nil {
		t.Fatal(e)
	}
	if _, ok := fourth.UserIDForToken(token); ok {
		t.Fatal("expired token revived")
	}
}

func TestPasswordStoredHashedAndCanLogin(t *testing.T) {
	s, sender := newSvc()
	_ = s.SendCode("13800000000")
	_, u, _ := s.Login("13800000000", sender.Last["13800000000"])
	if err := s.SetPassword(u.ID, "correct horse battery"); err != nil {
		t.Fatal(err)
	}
	stored, _ := s.users.FindByID(u.ID)
	if stored.PasswordHash == "correct horse battery" || bcrypt.CompareHashAndPassword([]byte(stored.PasswordHash), []byte("correct horse battery")) != nil {
		t.Fatal("password not bcrypt hashed")
	}
	if tok, got, e := s.PasswordLogin("13800000000", "correct horse battery"); e != nil || tok == "" || got.ID != u.ID {
		t.Fatalf("login=%q %+v %v", tok, got, e)
	}
	if _, _, e := s.PasswordLogin("13800000000", "wrong password"); !errors.Is(e, ErrPasswordInvalid) {
		t.Fatalf("wrong password=%v", e)
	}
}

func TestUnknownPasswordLoginUsesValidDummyBcryptHash(t *testing.T) {
	if err := bcrypt.CompareHashAndPassword(dummyPasswordHash, []byte(dummyPassword)); err != nil {
		t.Fatalf("dummy hash is not a real bcrypt hash: %v", err)
	}
	s, _ := newSvc()
	if _, _, err := s.PasswordLogin("13999999999", dummyPassword); err != ErrPasswordInvalid {
		t.Fatalf("dummy password authenticated unknown account: %v", err)
	}
}

func TestPasswordLoginLimitsAccountAndIPBeforeBcrypt(t *testing.T) {
	s, _ := newSvc()
	now := time.Now()
	s.now = func() time.Time { return now }
	for i := 0; i < 6; i++ {
		phone := fmt.Sprintf("138000001%02d", i)
		u, err := s.users.Create(User{Phone: phone})
		if err != nil {
			t.Fatal(err)
		}
		if err = s.SetPassword(u.ID, "correct horse battery"); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < maxPasswordAttempts; i++ {
		if _, _, err := s.PasswordLoginWithIP("13800000100", "wrong", fmt.Sprintf("10.0.0.%d", i)); err != ErrPasswordInvalid {
			t.Fatalf("account attempt %d: %v", i, err)
		}
	}
	if _, _, err := s.PasswordLoginWithIP("13800000100", "correct horse battery", "10.0.0.99"); err != ErrPasswordLimited {
		t.Fatalf("account lockout=%v", err)
	}

	for i := 1; i < maxPasswordAttempts; i++ {
		phone := fmt.Sprintf("138000001%02d", i)
		if _, _, err := s.PasswordLoginWithIP(phone, "wrong", "10.0.1.1"); err != ErrPasswordInvalid {
			t.Fatalf("ip attempt %d: %v", i, err)
		}
	}
	if token, _, err := s.PasswordLoginWithIP("13800000105", "correct horse battery", "10.0.1.1"); err != nil || token == "" {
		t.Fatalf("valid login before IP limit=%q %v", token, err)
	}
	if _, _, err := s.PasswordLoginWithIP("13800000105", "wrong", "10.0.1.1"); err != ErrPasswordInvalid {
		t.Fatalf("fifth IP failure=%v", err)
	}
	if _, _, err := s.PasswordLoginWithIP("13800000105", "correct horse battery", "10.0.1.1"); err != ErrPasswordLimited {
		t.Fatalf("ip lockout=%v", err)
	}
	now = now.Add(passwordAttemptWindow + time.Second)
	if token, _, err := s.PasswordLoginWithIP("13800000105", "correct horse battery", "10.0.1.1"); err != nil || token == "" {
		t.Fatalf("window reset=%q %v", token, err)
	}
}

func TestChangePhoneRequiresCodeAndMovesLoginIdentity(t *testing.T) {
	s, sender := newSvc()
	_ = s.SendCode("13800000000")
	_, u, _ := s.Login("13800000000", sender.Last["13800000000"])
	_ = s.SendCode("13900000000")
	if e := s.ChangePhone(u.ID, "13900000000", "bad"); !errors.Is(e, ErrCodeInvalid) {
		t.Fatalf("bad code=%v", e)
	}
	if e := s.ChangePhone(u.ID, "13900000000", sender.Last["13900000000"]); e != nil {
		t.Fatal(e)
	}
	if _, ok := s.users.FindByPhone("13800000000"); ok {
		t.Fatal("old phone remains")
	}
	if got, ok := s.users.FindByPhone("13900000000"); !ok || got.ID != u.ID {
		t.Fatal("new phone missing")
	}
}

func TestChangePhoneInvalidAttemptsExpireCode(t *testing.T) {
	s, sender := newSvc()
	u, _ := s.users.Create(User{Phone: "13800000000"})
	if err := s.SendCode("13900000000"); err != nil {
		t.Fatal(err)
	}
	correct := sender.Last["13900000000"]
	for i := 0; i < maxVerifyAttempts; i++ {
		if err := s.ChangePhone(u.ID, "13900000000", "wrong"); err != ErrCodeInvalid {
			t.Fatalf("attempt %d: %v", i, err)
		}
	}
	if err := s.ChangePhone(u.ID, "13900000000", correct); err != ErrCodeInvalid {
		t.Fatalf("expired code accepted: %v", err)
	}
}

func newSvc() (*Service, *LogSender) {
	s := NewLogSender()
	return NewService(s, NewMemUserRepo()), s
}

func TestLogin_AutoCreatesUser(t *testing.T) {
	svc, sender := newSvc()
	if err := svc.SendCode("13800001234"); err != nil {
		t.Fatal(err)
	}
	code := sender.Last["13800001234"]
	if len(code) != 6 {
		t.Fatalf("验证码应 6 位, got %q", code)
	}

	token, u, err := svc.Login("13800001234", code)
	if err != nil {
		t.Fatalf("登录失败: %v", err)
	}
	if token == "" || u.ID == "" {
		t.Error("应返回 token 和用户")
	}
	if u.Phone != "13800001234" {
		t.Errorf("phone=%s", u.Phone)
	}
	// token 可解析回用户
	if id, ok := svc.UserIDForToken(token); !ok || id != u.ID {
		t.Error("token 应解析回同一用户")
	}
}

func TestDeleteAccountRemovesUserAndRevokesAllTokens(t *testing.T) {
	svc, sender := newSvc()
	phone := "13800006666"
	_ = svc.SendCode(phone)
	token1, user, _ := svc.Login(phone, sender.Last[phone])
	_ = svc.SendCode(phone)
	token2, _, _ := svc.Login(phone, sender.Last[phone])
	if err := svc.DeleteAccount(user.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.User(user.ID); err != ErrUserNotFound {
		t.Fatalf("user remains: %v", err)
	}
	if _, ok := svc.UserIDForToken(token1); ok {
		t.Fatal("token1 remains")
	}
	if _, ok := svc.UserIDForToken(token2); ok {
		t.Fatal("token2 remains")
	}
}

// 同一手机号冷却期内重复发码被拒(防短信轰炸);越过冷却期可重发。
func TestSendCode_Cooldown(t *testing.T) {
	svc, _ := newSvc()
	now := time.Now()
	svc.now = func() time.Time { return now }

	if err := svc.SendCode("13800002222"); err != nil {
		t.Fatalf("首次发码应成功: %v", err)
	}
	if err := svc.SendCode("13800002222"); err != ErrRateLimited {
		t.Fatalf("冷却期内重复发码应 ErrRateLimited, got %v", err)
	}
	now = now.Add(sendCooldown + time.Second)
	if err := svc.SendCode("13800002222"); err != nil {
		t.Fatalf("越过冷却期应可重发, got %v", err)
	}
}

// 验证码被连续猜错 maxVerifyAttempts 次后作废,之后即便正确码也失效(需重新发码),防暴力猜码。
func TestLogin_BruteForceLockout(t *testing.T) {
	svc, sender := newSvc()
	if err := svc.SendCode("13800003333"); err != nil {
		t.Fatal(err)
	}
	code := sender.Last["13800003333"]
	for i := 0; i < maxVerifyAttempts; i++ {
		if _, _, err := svc.Login("13800003333", "000000-wrong"); err != ErrCodeInvalid {
			t.Fatalf("第 %d 次错码应 ErrCodeInvalid, got %v", i+1, err)
		}
	}
	if _, _, err := svc.Login("13800003333", code); err != ErrCodeInvalid {
		t.Errorf("超限后即便正确码也应失效, got %v", err)
	}
}

func TestLogin_ExistingUserReused(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800005678")
	_, u1, _ := svc.Login("13800005678", sender.Last["13800005678"])
	svc.SendCode("13800005678")
	_, u2, _ := svc.Login("13800005678", sender.Last["13800005678"])
	if u1.ID != u2.ID {
		t.Errorf("同手机号应复用用户, %s != %s", u1.ID, u2.ID)
	}
}

func TestLogin_WrongCode(t *testing.T) {
	svc, _ := newSvc()
	svc.SendCode("13800000000")
	if _, _, err := svc.Login("13800000000", "000000-wrong"); err != ErrCodeInvalid {
		t.Errorf("错误验证码应 ErrCodeInvalid, got %v", err)
	}
}

func TestLogin_CodeExpired(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800009999")
	code := sender.Last["13800009999"]
	// 把时钟拨到过期之后
	svc.now = func() time.Time { return time.Now().Add(codeTTL + time.Minute) }
	if _, _, err := svc.Login("13800009999", code); err != ErrCodeInvalid {
		t.Errorf("过期验证码应 ErrCodeInvalid, got %v", err)
	}
}

func TestLogin_CodeSingleUse(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800001111")
	code := sender.Last["13800001111"]
	svc.Login("13800001111", code)
	// 同验证码二次使用应失败
	if _, _, err := svc.Login("13800001111", code); err != ErrCodeInvalid {
		t.Errorf("验证码应一次性, got %v", err)
	}
}

// token 过期后失效,并被顺手清理。
func TestToken_Expiry(t *testing.T) {
	svc, sender := newSvc()
	now := time.Now()
	svc.now = func() time.Time { return now }
	svc.SendCode("13800007777")
	tok, _, err := svc.Login("13800007777", sender.Last["13800007777"])
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := svc.UserIDForToken(tok); !ok {
		t.Fatal("新 token 应有效")
	}
	now = now.Add(tokenTTL + time.Hour)
	if _, ok := svc.UserIDForToken(tok); ok {
		t.Error("过期 token 应失效")
	}
}

// refresh 作废旧 token、签发新 token;无效 token refresh 失败。
func TestToken_Refresh(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800008888")
	tok, _, _ := svc.Login("13800008888", sender.Last["13800008888"])
	newTok, ok := svc.Refresh(tok)
	if !ok || newTok == "" || newTok == tok {
		t.Fatalf("refresh 应签发新 token, ok=%v new=%q old=%q", ok, newTok, tok)
	}
	if _, ok := svc.UserIDForToken(tok); ok {
		t.Error("refresh 后旧 token 应作废")
	}
	if _, ok := svc.UserIDForToken(newTok); !ok {
		t.Error("新 token 应有效")
	}
	if _, ok := svc.Refresh("bogus"); ok {
		t.Error("无效 token refresh 应失败")
	}
}

// logout 作废 token,且对无效 token 幂等安全。
func TestToken_Logout(t *testing.T) {
	svc, sender := newSvc()
	svc.SendCode("13800009000")
	tok, _, _ := svc.Login("13800009000", sender.Last["13800009000"])
	svc.Logout(tok)
	if _, ok := svc.UserIDForToken(tok); ok {
		t.Error("logout 后 token 应失效")
	}
	svc.Logout("bogus")
}

// flakyRuntimeStore lets a test fail the Nth Save to simulate a transient persist error.
type flakyRuntimeStore struct {
	state  authRuntimeState
	saves  int
	failOn int // fail the failOn-th Save (1-based); 0 = never
}

func (f *flakyRuntimeStore) Load() (authRuntimeState, error) { return f.state, nil }
func (f *flakyRuntimeStore) Save(v authRuntimeState) error {
	f.saves++
	if f.failOn > 0 && f.saves == f.failOn {
		return errors.New("flaky: persist failed")
	}
	f.state = v
	return nil
}

// Refresh 在新 token 持久化失败时必须回报失败(而非返回空 token + true),
// 否则客户端会存下空 token 且旧会话已被作废,被静默登出。回归守卫 C0。
func TestToken_RefreshReportsFailureWhenNewTokenPersistFails(t *testing.T) {
	store := &flakyRuntimeStore{}
	svc, err := NewServiceWithRuntimeStore(NewLogSender(), NewMemUserRepo(), store)
	if err != nil {
		t.Fatal(err)
	}
	sender := svc.sender.(*LogSender)
	if err := svc.SendCode("13800001212"); err != nil {
		t.Fatal(err)
	}
	tok, _, err := svc.Login("13800001212", sender.Last["13800001212"])
	if err != nil {
		t.Fatal(err)
	}
	// 让接下来第二次 Save 失败:Refresh 先作废旧 token(save 成功),
	// issueToken 再写新 token(此 save 失败)。
	store.failOn = store.saves + 2
	newTok, ok := svc.Refresh(tok)
	if ok || newTok != "" {
		t.Fatalf("持久化失败时 Refresh 应返回 (\"\", false), got (%q, %v)", newTok, ok)
	}
	// 旧 token 的作废已持久化,应已失效(不能既登出又不给新 token 却报成功)。
	if _, valid := svc.UserIDForToken(tok); valid {
		t.Error("Refresh 已作废旧 token,旧 token 不应仍有效")
	}
}

// 无待验证码时验证仍走一次等价 bcrypt 比较并返回失败(不因短路而行为异常)。回归守卫 C2。
func TestLogin_NoPendingCodeStillRejects(t *testing.T) {
	svc, _ := newSvc()
	if _, _, err := svc.Login("13800001313", "000000"); err != ErrCodeInvalid {
		t.Fatalf("无待验证码登录应 ErrCodeInvalid, got %v", err)
	}
}

// 暴力锁定删除验证码后,发码冷却仍然生效(防 5 次错码绕过冷却轰炸短信)。
func TestSendCode_CooldownSurvivesBruteForce(t *testing.T) {
	svc, _ := newSvc()
	now := time.Now()
	svc.now = func() time.Time { return now }
	if err := svc.SendCode("13800004444"); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < maxVerifyAttempts; i++ {
		svc.Login("13800004444", "000000-wrong") // 触发暴力锁定 → 删 codes
	}
	if err := svc.SendCode("13800004444"); err != ErrRateLimited {
		t.Fatalf("暴力锁定后冷却期内仍应 ErrRateLimited, got %v", err)
	}
	now = now.Add(sendCooldown + time.Second)
	if err := svc.SendCode("13800004444"); err != nil {
		t.Fatalf("越过冷却期应可重发, got %v", err)
	}
}
