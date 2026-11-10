package auth

import (
	"golang.org/x/crypto/bcrypt"
	"strings"
)

const dummyPassword = "forgeplay-dummy-password-never-valid"

var dummyPasswordHash = func() []byte {
	hash, err := bcrypt.GenerateFromPassword([]byte(dummyPassword), bcrypt.DefaultCost)
	if err != nil {
		panic(err)
	}
	return hash
}()

func (s *Service) SetPassword(userID, password string) error {
	if len([]rune(password)) < 8 {
		return ErrPasswordWeak
	}
	u, ok := s.users.FindByID(userID)
	if !ok {
		return ErrUserNotFound
	}
	h, e := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if e != nil {
		return e
	}
	u.PasswordHash = string(h)
	return s.users.Update(u)
}
func (s *Service) PasswordLogin(phone, password string) (string, User, error) {
	return s.PasswordLoginWithIP(phone, password, "")
}

func (s *Service) PasswordLoginWithIP(phone, password, ip string) (string, User, error) {
	phone = strings.TrimSpace(phone)
	keys := []string{"account:" + phone}
	if ip = strings.TrimSpace(ip); ip != "" {
		keys = append(keys, "ip:"+ip)
	}
	if err := s.reservePasswordAttempt(keys); err != nil {
		return "", User{}, err
	}
	u, ok := s.users.FindByPhone(phone)
	hash := dummyPasswordHash
	if ok && u.PasswordHash != "" {
		hash = []byte(u.PasswordHash)
	}
	passwordOK := bcrypt.CompareHashAndPassword(hash, []byte(password)) == nil
	if !ok || u.PasswordHash == "" || !passwordOK {
		s.finishPasswordAttempt(keys, false)
		return "", User{}, ErrPasswordInvalid
	}
	s.finishPasswordAttempt(keys, true)
	if token := s.issueToken(u); token != "" {
		return token, u, nil
	}
	return "", User{}, ErrSessionStore
}

func (s *Service) reservePasswordAttempt(keys []string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	for _, key := range keys {
		attempt := s.passwordAttempts[key]
		if !attempt.ResetAt.IsZero() && !now.Before(attempt.ResetAt) {
			delete(s.passwordAttempts, key)
			attempt = passwordAttempt{}
		}
		if attempt.Count+s.passwordInFlight[key] >= maxPasswordAttempts {
			return ErrPasswordLimited
		}
	}
	for _, key := range keys {
		s.passwordInFlight[key]++
	}
	return nil
}

func (s *Service) finishPasswordAttempt(keys []string, success bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	for index, key := range keys {
		if s.passwordInFlight[key] > 1 {
			s.passwordInFlight[key]--
		} else {
			delete(s.passwordInFlight, key)
		}
		if success {
			// A valid password proves control of this account, but must never erase
			// the source-IP history shared by attempts against other accounts.
			if index == 0 {
				delete(s.passwordAttempts, key)
			}
			continue
		}
		attempt := s.passwordAttempts[key]
		if attempt.ResetAt.IsZero() || !now.Before(attempt.ResetAt) {
			attempt = passwordAttempt{ResetAt: now.Add(passwordAttemptWindow)}
		}
		attempt.Count++
		s.passwordAttempts[key] = attempt
	}
	_ = s.saveRuntimeLocked()
}
