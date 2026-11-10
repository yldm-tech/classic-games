// Package users 是用户公开资料层:个人主页身份/统计/等级,以及"我的作品/二创/喜欢"列表。
// 统计值与作品分段从这里出(客户端只保留标签文案的 i18n);作品列表复用 games 域解析。
package users

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"forgeplay/server/internal/games"
)

// Profile 是用户公开资料 + 统计(数值由服务端出,标签客户端本地化)。
type Profile struct {
	ID      string `json:"id"` // @handle
	Name    string `json:"name"`
	Bio     string `json:"bio"` // 用户自述;空时客户端回退本地化占位
	Gender  int    `json:"gender"`
	Tone    string `json:"tone"`
	Region  string `json:"region"`
	Joined  int    `json:"joined"`
	Works   int    `json:"works"`
	Level   int    `json:"level"`
	Points  int    `json:"points"`
	Plays   int    `json:"plays"`
	Forks   int    `json:"forks"`
	Follows int    `json:"follows"`
	Likes   int    `json:"likes"`
}

type segments struct {
	works []string
	forks []string
	liked []string
}

// Service 持有种子资料 + 分段,并用 games 域把游戏 id 解析成完整(本地化)游戏对象。
type Service struct {
	mu              sync.RWMutex
	profiles        map[string]Profile
	owners          map[string]string // auth user id -> public handle
	segs            map[string]segments
	verifications   map[string]verificationRecord
	verificationKey []byte
	games           *games.Service
	likes           games.LikeCounter // 可空;非空时「我的作品/二创/喜欢」的点赞数也以 social 为准(与 /games 一致)
	favorites       func(string) ([]string, error)
	followCount     func(string) int // 可空;非空时 Profile.Follows 取真实关注关系(inbox 域),否则恒为 0
	store           StateStore
}

func NewService(g *games.Service) *Service {
	s := &Service{
		profiles:      map[string]Profile{},
		owners:        map[string]string{},
		segs:          map[string]segments{},
		verifications: map[string]verificationRecord{},
		games:         g,
	}
	s.verificationKey = make([]byte, 32)
	if _, err := rand.Read(s.verificationKey); err != nil {
		panic("users: cannot initialize verification key")
	}
	s.seed()
	return s
}

func NewServiceWithStore(g *games.Service, store StateStore, key []byte) (*Service, error) {
	s := NewService(g)
	s.store = store
	if len(key) > 0 {
		sum := sha256.Sum256(key)
		s.verificationKey = append([]byte(nil), sum[:]...)
	}
	rows, e := store.LoadAll()
	if e != nil {
		return nil, e
	}
	for _, row := range rows {
		if row.Handle != "" {
			s.owners[row.UserID] = row.Handle
			s.profiles[row.Handle] = row.Profile
		}
		if row.Verification.Status != "" {
			var d [32]byte
			copy(d[:], row.VerificationDigest)
			s.verifications[row.UserID] = verificationRecord{VerificationStatus: row.Verification, digest: d}
		}
	}
	return s, nil
}

func (s *Service) saveLocked(userID string) error {
	if s.store == nil {
		return nil
	}
	handle := s.owners[userID]
	v := s.verifications[userID]
	return s.store.Save(userStateRow{UserID: userID, Handle: handle, Profile: s.profiles[handle], Verification: v.VerificationStatus, VerificationDigest: append([]byte(nil), v.digest[:]...)})
}

// SetLikeCounter 注入点赞计数源(social),使 /users/:id/games 的点赞数与 /games、/ranking、/like 一致。
func (s *Service) SetLikeCounter(c games.LikeCounter) { s.mu.Lock(); defer s.mu.Unlock(); s.likes = c }
func (s *Service) SetFavoriteLister(f func(string) ([]string, error)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.favorites = f
}

// SetFollowCounter 注入关注计数源(inbox 域),使 Profile.Follows 反映真实关注关系。
func (s *Service) SetFollowCounter(f func(string) int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.followCount = f
}

func (s *Service) seed() {
	// 种子账号只留身份字段;统计字段(Works/Plays/Forks/Follows)不再硬编码——
	// Get() 对所有账号统一按当前真实作品/关注关系动态聚合,避免与 segs/games 域真实数据脱节。
	s.profiles["@koru"] = Profile{ID: "@koru", Name: "@koru", Gender: 2, Tone: "ember", Region: "Shanghai", Joined: 2025, Level: 1}
	s.segs["@koru"] = segments{works: []string{"ember", "cinder"}, forks: []string{"volt", "echo"}, liked: []string{"null", "ash", "magma"}}
	// 创作者公开页(详情页点作者进入)
	s.profiles["@mei"] = Profile{ID: "@mei", Joined: 2025, Level: 1}
	s.segs["@mei"] = segments{works: []string{"volt"}, forks: []string{"echo"}, liked: []string{"ember"}}
	s.profiles["@talia"] = Profile{ID: "@talia", Joined: 2024, Level: 1}
	s.segs["@talia"] = segments{works: []string{"ashfall"}, forks: []string{}, liked: []string{"foundry"}}
}

var defaultProfile = Profile{Joined: 2025, Level: 1}

// Get 取用户资料。身份字段(Name/Bio/Gender/Tone/Region/Joined)取自存量资料(未知用户回退空资料,
// 客户端仍可渲染骨架/占位);统计字段(Works/Plays/Forks/Likes/Follows)每次都基于当前真实作品/关注
// 关系重新聚合,而不是存量快照——否则用户编辑一次资料后,统计值会与后续发布/游玩/被 Fork 脱节。
func (s *Service) Get(id string) (Profile, bool) {
	s.mu.RLock()
	stored, hit := s.profiles[id]
	followCounter := s.followCount
	s.mu.RUnlock()
	p := stored
	if !hit {
		p = Profile{ID: id, Name: id, Level: 1}
	}
	p.Works, p.Plays, p.Forks, p.Likes = 0, 0, 0, 0
	works := s.GamesOf(id, "works", "zh")
	for _, game := range works {
		p.Works++
		p.Plays += game.Plays
		p.Forks += game.Forks
		p.Likes += game.Likes
		if p.Joined == 0 || game.CreatedAt.Year() < p.Joined {
			p.Joined = game.CreatedAt.Year()
		}
	}
	if followCounter != nil {
		p.Follows = followCounter(id)
	}
	return p, hit || len(works) > 0
}

// allowedTones 必须与客户端 GameCard.TONES 同一词表(ember/moss/ocean/plum/steel/rust)——
// 客户端资料/头像色板从该常量渲染并原样回传,种子作品的 tone 也取自这套。两端不一致会让
// 除 ember 外的每个色板选项被服务端 400(见 client 头像/编辑资料流)。
var allowedTones = map[string]bool{"ember": true, "moss": true, "ocean": true, "plum": true, "steel": true, "rust": true}

// ErrProfilePersist 表示资料写入存储失败(区别于校验失败),供 transport 映射为 5xx 而非 400。
var ErrProfilePersist = errors.New("users: failed to persist profile")

type ProfileUpdate struct {
	Name   string `json:"name"`
	Bio    string `json:"bio"`
	Gender int    `json:"gender"`
	Tone   string `json:"tone"`
	Region string `json:"region"`
}

type ProfilePatch struct {
	Name   *string `json:"name"`
	Bio    *string `json:"bio"`
	Gender *int    `json:"gender"`
	Tone   *string `json:"tone"`
	Region *string `json:"region"`
}

func (s *Service) PatchProfile(userID string, in ProfilePatch) (Profile, error) {
	if userID == "" {
		return Profile{}, errors.New("missing user")
	}
	// 读—合并—写全程持同一把写锁,避免读快照与写之间被并发写覆盖(lost update)。
	s.mu.Lock()
	defer s.mu.Unlock()
	handle := s.owners[userID]
	current, ok := s.profiles[handle]
	if !ok {
		current = defaultProfile
		current.ID = "@" + userID
		current.Name = current.ID
		current.Tone = "ember"
	}
	update := ProfileUpdate{Name: current.Name, Bio: current.Bio, Gender: current.Gender, Tone: current.Tone, Region: current.Region}
	if in.Name != nil {
		update.Name = *in.Name
	}
	if in.Bio != nil {
		update.Bio = *in.Bio
	}
	if in.Gender != nil {
		update.Gender = *in.Gender
	}
	if in.Tone != nil {
		update.Tone = *in.Tone
	}
	if in.Region != nil {
		update.Region = *in.Region
	}
	return s.commitProfileLocked(userID, update)
}

func (s *Service) UpdateProfile(userID string, in ProfileUpdate) (Profile, error) {
	if userID == "" {
		return Profile{}, errors.New("missing user")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.commitProfileLocked(userID, in)
}

// commitProfileLocked 校验、落库并发布到内存;持久化失败时回滚内存并返回 ErrProfilePersist
// (与 quota.Allow 一致:内存不领先于存储)。调用方必须已持写锁。
func (s *Service) commitProfileLocked(userID string, in ProfileUpdate) (Profile, error) {
	in.Name, in.Bio, in.Region, in.Tone = strings.TrimSpace(in.Name), strings.TrimSpace(in.Bio), strings.TrimSpace(in.Region), strings.TrimSpace(in.Tone)
	if n := utf8.RuneCountInString(in.Name); n < 1 || n > 30 {
		return Profile{}, errors.New("name must be 1-30 characters")
	}
	if utf8.RuneCountInString(in.Bio) > 160 {
		return Profile{}, errors.New("bio must be at most 160 characters")
	}
	if utf8.RuneCountInString(in.Region) > 50 {
		return Profile{}, errors.New("region must be at most 50 characters")
	}
	if in.Gender < 0 || in.Gender > 2 {
		return Profile{}, errors.New("invalid gender")
	}
	if !allowedTones[in.Tone] {
		return Profile{}, errors.New("invalid tone")
	}
	handle := s.owners[userID]
	ownerCreated := false
	if handle == "" {
		handle = "@" + userID
		s.owners[userID] = handle
		ownerCreated = true
	}
	prev, existed := s.profiles[handle]
	p := prev
	if !existed {
		p = defaultProfile
		p.ID = handle
	}
	p.Name, p.Bio, p.Gender, p.Tone, p.Region = in.Name, in.Bio, in.Gender, in.Tone, in.Region
	s.profiles[handle] = p
	if err := s.saveLocked(userID); err != nil {
		// 回滚,保证持久化失败后内存与存储一致(不留下"看似已保存"的脏值)。
		if existed {
			s.profiles[handle] = prev
		} else {
			delete(s.profiles, handle)
		}
		if ownerCreated {
			delete(s.owners, userID)
		}
		return Profile{}, ErrProfilePersist
	}
	return p, nil
}

type VerificationStatus struct {
	Status      string    `json:"status"`
	IDMasked    string    `json:"id_masked,omitempty"`
	SubmittedAt time.Time `json:"submitted_at,omitempty"`
}

type PendingVerification struct {
	UserID string `json:"user_id"`
	VerificationStatus
}

type verificationRecord struct {
	VerificationStatus
	digest [32]byte
}

var (
	ErrVerificationInvalid = errors.New("invalid id number")
	ErrVerificationState   = errors.New("verification not pending")
)

func validChineseID18(id string) bool {
	if len(id) != 18 {
		return true
	}
	for i := 0; i < 17; i++ {
		if id[i] < '0' || id[i] > '9' {
			return false
		}
	}
	weights := [...]int{7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2}
	table := "10X98765432"
	sum := 0
	for i := 0; i < 17; i++ {
		sum += int(id[i]-'0') * weights[i]
	}
	return table[sum%11] == id[17]
}

func (s *Service) SubmitVerification(userID, name, idNumber string) (VerificationStatus, error) {
	name, idNumber = strings.TrimSpace(name), strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(idNumber), " ", ""))
	if userID == "" {
		return VerificationStatus{}, errors.New("missing user")
	}
	if utf8.RuneCountInString(name) < 2 || utf8.RuneCountInString(name) > 80 {
		return VerificationStatus{}, errors.New("invalid legal name")
	}
	if len(idNumber) < 6 || len(idNumber) > 32 {
		return VerificationStatus{}, ErrVerificationInvalid
	}
	if !validChineseID18(idNumber) {
		return VerificationStatus{}, ErrVerificationInvalid
	}
	mac := hmac.New(sha256.New, s.verificationKey)
	_, _ = mac.Write([]byte(name + "\x00" + idNumber))
	var digest [32]byte
	copy(digest[:], mac.Sum(nil))
	masked := "****" + idNumber[len(idNumber)-4:]
	status := VerificationStatus{Status: "pending", IDMasked: masked, SubmittedAt: time.Now().UTC()}
	s.mu.Lock()
	s.verifications[userID] = verificationRecord{VerificationStatus: status, digest: digest}
	err := s.saveLocked(userID)
	s.mu.Unlock()
	return status, err
}

func (s *Service) VerificationStatus(userID string) VerificationStatus {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if v, ok := s.verifications[userID]; ok {
		return v.VerificationStatus
	}
	return VerificationStatus{Status: "not_submitted"}
}

func (s *Service) ListPendingVerifications() []PendingVerification {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]PendingVerification, 0)
	for uid, rec := range s.verifications {
		if rec.Status != "pending" {
			continue
		}
		out = append(out, PendingVerification{UserID: uid, VerificationStatus: rec.VerificationStatus})
	}
	return out
}

func (s *Service) DecideVerification(userID string, approve bool) (VerificationStatus, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.verifications[userID]
	if !ok || rec.Status != "pending" {
		return VerificationStatus{}, ErrVerificationState
	}
	if approve {
		rec.Status = "verified"
	} else {
		rec.Status = "rejected"
	}
	s.verifications[userID] = rec
	return rec.VerificationStatus, s.saveLocked(userID)
}

// GamesOf 返回用户某分段(works/forks/liked)的完整游戏(按 lang 本地化)。
func (s *Service) GamesOf(id, typ, lang string) []games.Game {
	s.mu.RLock()
	seg := s.segs[id]
	likeCounter := s.likes
	favoriteLister := s.favorites
	s.mu.RUnlock()
	var ids []string
	switch typ {
	case "forks":
		ids = seg.forks
	case "liked":
		ids = seg.liked
	default:
		ids = seg.works
	}
	if typ == "liked" && len(ids) == 0 && favoriteLister != nil {
		ids, _ = favoriteLister(strings.TrimPrefix(id, "@"))
	}
	out := make([]games.Game, 0, len(ids))
	if len(ids) == 0 && (typ == "works" || typ == "forks") {
		if mine, err := s.games.ListMine(strings.TrimPrefix(id, "@")); err == nil {
			for _, game := range mine {
				isFork := game.ForkedFrom != ""
				if game.Status == games.StatusPublished && ((typ == "forks" && isFork) || (typ == "works" && !isFork)) {
					out = append(out, game.Localized(lang))
				}
			}
		}
	}
	for _, gid := range ids {
		// Published-only, matching the works/forks branch above. Without it a profile listing served whatever the id set
		// happened to contain, so a game still under review, or one that was rejected or delisted, stayed publicly
		// readable through anyone's liked list.
		if g, err := s.games.Get(gid); err == nil && g.Status == games.StatusPublished {
			out = append(out, g.Localized(lang))
		}
	}
	// 点赞数以 social 为单一真相源覆盖,与 /games、/ranking、/like 一致(避免「我的页」显示陈旧静态值)。
	if likeCounter != nil && len(out) > 0 {
		gotIDs := make([]string, len(out))
		for i := range out {
			gotIDs[i] = out[i].ID
		}
		if counts, err := likeCounter.LikeCounts(gotIDs); err == nil {
			for i := range out {
				out[i].Likes = counts[out[i].ID]
			}
		}
	}
	return out
}
