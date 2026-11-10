// Package inbox 提供通知、私信、关注与好友关系。初始内容来自三语种子，
// 用户消息、关注和好友关系由可替换 StateStore 保存，生产使用 GORM。
package inbox

import (
	_ "embed"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"sync"
)

// 三语种子(zh/en/ja)。运行期一次性解码,只读,无需并发保护。
var (
	//go:embed seed/activity.json
	activityJSON []byte
	//go:embed seed/chats.json
	chatsJSON []byte
	//go:embed seed/auto_replies.json
	autoRepliesJSON []byte
	//go:embed seed/follow.json
	followJSON []byte
	//go:embed seed/suggestions.json
	suggestionsJSON []byte
)

// L10n is a tri-lingual text map (zh/en/ja). zh is the canonical fallback.
// 对齐 client i18n 的 DEFAULT_LOCALE = "zh"。
type L10n map[string]string

const defaultLang = "zh"

// localePick resolves a locale, falling back to zh, then to any present value.
// 与 games 域的 localePick 同义:lang 缺失→回落 zh→再回落任意非空,保证不返回空串。
func localePick(m L10n, lang string) string {
	if v, ok := m[lang]; ok && v != "" {
		return v
	}
	if v, ok := m[defaultLang]; ok && v != "" {
		return v
	}
	for _, v := range m {
		if v != "" {
			return v
		}
	}
	return ""
}

// normLang 归一化语言代码;非支持语言一律回落 zh(默认)。
func normLang(lang string) string {
	switch lang {
	case "zh", "en", "ja":
		return lang
	default:
		return defaultLang
	}
}

// --- 种子内部模型(带 L10n,未本地化) ---

type seedActivity struct {
	Icon  string `json:"icon"` // 图标键,不本地化(fork/heart/trophy/sparkle)
	Title L10n   `json:"title"`
	Body  L10n   `json:"body"`
	Time  L10n   `json:"time"` // 相对时间文案,前端展示用,本地化
}

type seedChat struct {
	Handle      string `json:"handle"` // @昵称,不本地化
	Online      bool   `json:"online"`
	Unread      int    `json:"unread"`
	Time        L10n   `json:"time"`
	LastMessage L10n   `json:"last_message"`
}

type seedPerson struct {
	Handle string `json:"handle"`
	Mutual bool   `json:"mutual"` // 是否互相关注
	Note   L10n   `json:"note"`
}

type seedSuggestion struct {
	Handle string `json:"handle"`
	Reason L10n   `json:"reason"`
}

type seedFollow struct {
	Following []seedPerson `json:"following"`
	Followers []seedPerson `json:"followers"`
}

type seedSuggestions struct {
	InviteCode  string           `json:"invite_code"`
	Suggestions []seedSuggestion `json:"suggestions"`
}

// --- 对外 DTO(已本地化,counts/index/handle/icon 保持原样) ---

// Activity 是通知页的一条动态(消息 tab 的"通知"段)。
type Activity struct {
	Index int    `json:"index"`
	Icon  string `json:"icon"`
	Title string `json:"title"`
	Body  string `json:"body"`
	Time  string `json:"time"`
}

// Chat 是私信会话列表的一项(消息 tab 的"私信"段)。
type Chat struct {
	Index       int    `json:"index"`
	Handle      string `json:"handle"`
	Online      bool   `json:"online"`
	Unread      int    `json:"unread"`
	Time        string `json:"time"`
	LastMessage string `json:"last_message"`
}

// Message 是单条会话气泡。Mine=true 表示本人发出。
type Message struct {
	Text string `json:"text"`
	Mine bool   `json:"mine"`
}

// Person 是关注/粉丝列表的一行。
type Person struct {
	Handle string `json:"handle"`
	Mutual bool   `json:"mutual"`
	Note   string `json:"note"`
}

// Suggestion 是加好友页的"可能认识的人"。
type Suggestion struct {
	Handle string `json:"handle"`
	Reason string `json:"reason"`
}

// Service 是并发安全的消息中心服务：种子只读，用户消息与关系可写。
type Service struct {
	mu                sync.Mutex
	activity          []seedActivity
	chats             []seedChat
	autoReplies       []L10n
	follow            seedFollow
	suggestions       seedSuggestions
	userMessages      map[string]map[int][]Message
	userConversations map[string]map[string][]Message
	userFollowing     map[string]map[string]bool
	userFriends       map[string]map[string]bool
	store             StateStore
	onFriend          func(string) error
}

func (s *Service) SetFriendRecorder(f func(string) error) { s.onFriend = f }

var ErrInvalidMessage = errors.New("inbox: message empty or chat not found")
var ErrNotFriend = errors.New("inbox: conversation target is not a friend")

// NewService 从内嵌 JSON 种子构造服务。种子是构建期资产,解码失败属于编程错误,直接 panic。
func NewService() *Service {
	s := &Service{}
	mustUnmarshal(activityJSON, &s.activity)
	mustUnmarshal(chatsJSON, &s.chats)
	mustUnmarshal(autoRepliesJSON, &s.autoReplies)
	mustUnmarshal(followJSON, &s.follow)
	mustUnmarshal(suggestionsJSON, &s.suggestions)
	s.userMessages = map[string]map[int][]Message{}
	s.userConversations = map[string]map[string][]Message{}
	s.userFollowing = map[string]map[string]bool{}
	s.userFriends = map[string]map[string]bool{}
	return s
}

func NewServiceWithStore(store StateStore) (*Service, error) {
	s := NewService()
	s.store = store
	rows, e := store.LoadAll()
	if e != nil {
		return nil, e
	}
	for _, row := range rows {
		st := row.State
		if st.Messages == nil {
			st.Messages = map[int][]Message{}
		}
		if st.Following == nil {
			st.Following = map[string]bool{}
		}
		if st.Friends == nil {
			st.Friends = map[string]bool{}
		}
		if st.Conversations == nil {
			st.Conversations = map[string][]Message{}
		}
		s.userMessages[row.UserID] = st.Messages
		s.userConversations[row.UserID] = st.Conversations
		s.userFollowing[row.UserID] = st.Following
		s.userFriends[row.UserID] = st.Friends
	}
	return s, nil
}
func (s *Service) saveLocked(uid string) error {
	if s.store == nil {
		return nil
	}
	return s.store.Save(inboxStateRow{UserID: uid, State: userState{Messages: s.userMessages[uid], Conversations: s.userConversations[uid], Following: s.userFollowing[uid], Friends: s.userFriends[uid]}})
}

func mustUnmarshal(data []byte, v any) {
	if err := json.Unmarshal(data, v); err != nil {
		panic("inbox: 种子 JSON 解码失败: " + err.Error())
	}
}

// Activity 返回本地化后的通知动态列表。
func (s *Service) Activity(lang string) []Activity {
	lang = normLang(lang)
	out := make([]Activity, 0, len(s.activity))
	for i, a := range s.activity {
		out = append(out, Activity{
			Index: i,
			Icon:  a.Icon,
			Title: localePick(a.Title, lang),
			Body:  localePick(a.Body, lang),
			Time:  localePick(a.Time, lang),
		})
	}
	return out
}

// ActivityFor keeps the embedded catalog available for anonymous previews,
// while authenticated accounts only receive their own persisted activity.
// No per-user activity has been recorded yet, so a new account is truthfully empty.
func (s *Service) ActivityFor(userID, lang string) []Activity {
	if userID != "" {
		return []Activity{}
	}
	return s.Activity(lang)
}

// Chats 返回本地化后的私信会话列表。
func (s *Service) Chats(lang string) []Chat {
	lang = normLang(lang)
	out := make([]Chat, 0, len(s.chats))
	for i, c := range s.chats {
		out = append(out, Chat{
			Index:       i,
			Handle:      c.Handle,
			Online:      c.Online,
			Unread:      c.Unread,
			Time:        localePick(c.Time, lang),
			LastMessage: localePick(c.LastMessage, lang),
		})
	}
	return out
}

func (s *Service) ChatsFor(userID, _ string) []Chat {
	s.mu.Lock()
	defer s.mu.Unlock()
	handles := make([]string, 0, len(s.userFriends[userID]))
	for handle, friend := range s.userFriends[userID] {
		if friend {
			handles = append(handles, handle)
		}
	}
	sort.Strings(handles)
	out := make([]Chat, len(handles))
	for i, handle := range handles {
		messages := s.userConversations[userID][handle]
		last := ""
		if len(messages) > 0 {
			last = messages[len(messages)-1].Text
		}
		out[i] = Chat{Index: i, Handle: handle, LastMessage: last}
	}
	return out
}

func (s *Service) MessagesWith(userID, handle string) ([]Message, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if userID == "" || !s.userFriends[userID][handle] {
		return nil, ErrNotFriend
	}
	return append([]Message(nil), s.userConversations[userID][handle]...), nil
}

func (s *Service) SendMessageTo(userID, handle, text string) ([]Message, error) {
	text = strings.TrimSpace(text)
	s.mu.Lock()
	defer s.mu.Unlock()
	if text == "" {
		return nil, ErrInvalidMessage
	}
	if userID == "" || !s.userFriends[userID][handle] {
		return nil, ErrNotFriend
	}
	if s.userConversations[userID] == nil {
		s.userConversations[userID] = map[string][]Message{}
	}
	s.userConversations[userID][handle] = append(s.userConversations[userID][handle], Message{Text: text, Mine: true})
	if err := s.saveLocked(userID); err != nil {
		return nil, err
	}
	return append([]Message(nil), s.userConversations[userID][handle]...), nil
}

// ChatCount 返回会话数,供 transport 层做索引边界校验。
func (s *Service) ChatCount() int { return len(s.chats) }

// Messages 返回某会话的种子气泡:对方最近一条消息打底,
// 其后按 auto_replies 模板循环补几条自动回复,还原前端 chat_screen 的对话效果。
// idx 越界返回 (nil, false)。
func (s *Service) Messages(idx int, lang string) ([]Message, bool) {
	return s.MessagesFor("", idx, lang)
}

func (s *Service) MessagesFor(userID string, idx int, lang string) ([]Message, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if idx < 0 || idx >= len(s.chats) {
		return nil, false
	}
	if userID != "" {
		out := append([]Message(nil), s.userMessages[userID][idx]...)
		return out, true
	}
	lang = normLang(lang)
	out := []Message{
		{Text: localePick(s.chats[idx].LastMessage, lang), Mine: false},
	}
	// 自动回复模板循环,模拟好友陆续回话(对方发出,Mine=false)。
	for _, r := range s.autoReplies {
		out = append(out, Message{Text: localePick(r, lang), Mine: false})
	}
	if byChat := s.userMessages[userID]; byChat != nil {
		out = append(out, byChat[idx]...)
	}
	return out, true
}

func (s *Service) SendMessage(userID string, idx int, text string) ([]Message, error) {
	text = strings.TrimSpace(text)
	if text == "" || idx < 0 || idx >= len(s.chats) {
		return nil, ErrInvalidMessage
	}
	s.mu.Lock()
	if s.userMessages[userID] == nil {
		s.userMessages[userID] = map[int][]Message{}
	}
	s.userMessages[userID][idx] = append(s.userMessages[userID][idx], Message{Text: text, Mine: true})
	if e := s.saveLocked(userID); e != nil {
		s.mu.Unlock()
		return nil, e
	}
	s.mu.Unlock()
	out, _ := s.MessagesFor(userID, idx, defaultLang)
	return out, nil
}

func (s *Service) SetFollowing(userID, handle string, on bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.userFollowing[userID] == nil {
		s.userFollowing[userID] = map[string]bool{}
	}
	if on {
		s.userFollowing[userID][handle] = true
	} else {
		delete(s.userFollowing[userID], handle)
	}
	return s.saveLocked(userID)
}
func (s *Service) IsFollowing(userID, handle string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.userFollowing[userID][handle]
}

func (s *Service) FollowingOf(userID string) []Person {
	s.mu.Lock()
	defer s.mu.Unlock()
	return relationPeople(s.userFollowing[userID])
}

func (s *Service) FollowersOf(userID string) []Person {
	s.mu.Lock()
	defer s.mu.Unlock()
	set := map[string]bool{}
	for actor, targets := range s.userFollowing {
		if targets[userID] {
			set[actor] = true
		}
	}
	return relationPeople(set)
}

func relationPeople(set map[string]bool) []Person {
	ids := make([]string, 0, len(set))
	for id, on := range set {
		if on {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	out := make([]Person, len(ids))
	for i, id := range ids {
		out[i] = Person{Handle: id}
	}
	return out
}
func (s *Service) AddFriend(userID, handle string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.userFriends[userID] == nil {
		s.userFriends[userID] = map[string]bool{}
	}
	s.userFriends[userID][handle] = true
	err := s.saveLocked(userID)
	if err == nil && s.onFriend != nil {
		_ = s.onFriend(userID)
	}
	return err
}
func (s *Service) IsFriend(userID, handle string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.userFriends[userID][handle]
}

// Follow 返回本地化后的关注或粉丝列表。kind 取 "following" 或 "followers"。
// kind 非法返回 (nil, false)。
func (s *Service) Follow(kind, lang string) ([]Person, bool) {
	var src []seedPerson
	switch kind {
	case "following":
		src = s.follow.Following
	case "followers":
		src = s.follow.Followers
	default:
		return nil, false
	}
	lang = normLang(lang)
	out := make([]Person, 0, len(src))
	for _, p := range src {
		out = append(out, Person{
			Handle: p.Handle,
			Mutual: p.Mutual,
			Note:   localePick(p.Note, lang),
		})
	}
	return out, true
}

// Suggestions 返回本地化后的加好友推荐和邀请码(邀请码不本地化)。
func (s *Service) Suggestions(lang string) ([]Suggestion, string) {
	lang = normLang(lang)
	out := make([]Suggestion, 0, len(s.suggestions.Suggestions))
	for _, sg := range s.suggestions.Suggestions {
		out = append(out, Suggestion{
			Handle: sg.Handle,
			Reason: localePick(sg.Reason, lang),
		})
	}
	return out, s.suggestions.InviteCode
}
