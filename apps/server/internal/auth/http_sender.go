package auth

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// HTTPSender 把验证码交给可配置短信网关。网关契约：
// POST JSON {phone,code}，可选 Bearer token，任意 2xx 表示接收成功。
type HTTPSender struct {
	endpoint string
	token    string
	client   *http.Client
}

func NewHTTPSender(endpoint, token string, timeout time.Duration) *HTTPSender {
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	return &HTTPSender{endpoint: endpoint, token: token, client: &http.Client{Timeout: timeout}}
}

func (s *HTTPSender) Send(phone, code string) error {
	body, err := json.Marshal(map[string]string{"phone": phone, "code": code})
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, s.endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if s.token != "" {
		req.Header.Set("Authorization", "Bearer "+s.token)
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrSendFailed, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("%w: gateway status %d: %s", ErrSendFailed, resp.StatusCode, bytes.TrimSpace(msg))
	}
	return nil
}
