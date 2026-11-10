package social

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"
)

type HTTPModerator struct {
	url, token string
	client     *http.Client
}

func NewHTTPModerator(url, token string, timeout time.Duration) *HTTPModerator {
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	return &HTTPModerator{url, token, &http.Client{Timeout: timeout}}
}
func (m *HTTPModerator) Check(text string) error {
	body, _ := json.Marshal(map[string]string{"text": text})
	req, e := http.NewRequest(http.MethodPost, m.url, bytes.NewReader(body))
	if e != nil {
		return e
	}
	req.Header.Set("Content-Type", "application/json")
	if m.token != "" {
		req.Header.Set("Authorization", "Bearer "+m.token)
	}
	resp, e := m.client.Do(req)
	if e != nil {
		return fmt.Errorf("moderation unavailable: %w", e)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("moderation unavailable: status %d", resp.StatusCode)
	}
	var out struct {
		Allowed bool `json:"allowed"`
	}
	if json.NewDecoder(resp.Body).Decode(&out) != nil {
		return errors.New("moderation unavailable: invalid response")
	}
	if !out.Allowed {
		return ErrContentRejected
	}
	return nil
}

type ChainModerator []TextModerator

func (c ChainModerator) Check(text string) error {
	for _, m := range c {
		if m != nil {
			if e := m.Check(text); e != nil {
				return e
			}
		}
	}
	return nil
}
