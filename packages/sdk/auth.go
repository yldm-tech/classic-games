package sdk

import (
	"context"
	"fmt"
	"net/http"
)

// User is the account behind a token. The backend never returns the phone number.
type User struct {
	ID       string `json:"id"`
	Nickname string `json:"nickname"`
}

// Session is the result of a successful login. Tokens are opaque bearer strings valid for 30 days; RefreshToken trades one for a fresh one.
type Session struct {
	Token string `json:"token"`
	User  User   `json:"user"`
}

func (c *Client) login(ctx context.Context, path string, body any) (*Session, error) {
	var out Session
	if err := c.do(ctx, http.MethodPost, path, nil, body, &out); err != nil {
		return nil, err
	}
	if out.Token == "" {
		return nil, fmt.Errorf("sdk: POST %s: response carries no token", path)
	}
	return &out, nil
}

// LoginGuest calls POST /api/v1/auth/guest and creates a new guest account with its own token. It needs no credentials and always works, which makes it the default for tools. A guest can create mods, fork, publish and comment; guests are metered for AI quota by client IP, not per account, and a guest account cannot be recovered once its token is lost.
//
// The client's token is not changed: call SetToken(session.Token) to use the session.
func (c *Client) LoginGuest(ctx context.Context) (*Session, error) {
	return c.login(ctx, api("auth", "guest"), nil)
}

// SendSMSCode calls POST /api/v1/auth/sms/send and asks the backend to text a 6-digit login code to phone. The code is valid for 5 minutes and tolerates 5 wrong attempts. A second request for the same phone within 60 seconds fails with 429 RATE_LIMITED. Check Meta().SMS first: without a configured gateway the call succeeds but no message is delivered.
func (c *Client) SendSMSCode(ctx context.Context, phone string) error {
	return c.do(ctx, http.MethodPost, api("auth", "sms", "send"), nil, map[string]string{"phone": phone}, nil)
}

// LoginSMS calls POST /api/v1/auth/sms/verify with the code received after SendSMSCode. An unknown phone number is registered automatically. A wrong or expired code fails with 401 AUTH_INVALID.
//
// The client's token is not changed: call SetToken(session.Token) to use the session.
func (c *Client) LoginSMS(ctx context.Context, phone, code string) (*Session, error) {
	return c.login(ctx, api("auth", "sms", "verify"), map[string]string{"phone": phone, "code": code})
}

// LoginPassword calls POST /api/v1/auth/password/login. It works for accounts that set a password with SetPassword. Wrong credentials fail with 401 AUTH_INVALID; after 5 attempts per account or client IP within 15 minutes the backend answers 429 AUTH_INVALID.
//
// The client's token is not changed: call SetToken(session.Token) to use the session.
func (c *Client) LoginPassword(ctx context.Context, phone, password string) (*Session, error) {
	return c.login(ctx, api("auth", "password", "login"), map[string]string{"phone": phone, "password": password})
}

// RefreshToken calls POST /api/v1/auth/refresh. The backend revokes the client's current token and returns a new one valid for another 30 days. The client keeps sending the revoked token until SetToken is called with the returned one. An unknown or expired token fails with 401 AUTH_REQUIRED.
func (c *Client) RefreshToken(ctx context.Context) (string, error) {
	var out struct {
		Token string `json:"token"`
	}
	path := api("auth", "refresh")
	if err := c.do(ctx, http.MethodPost, path, nil, nil, &out); err != nil {
		return "", err
	}
	if out.Token == "" {
		return "", fmt.Errorf("sdk: POST %s: response carries no token", path)
	}
	return out.Token, nil
}

// Logout calls POST /api/v1/auth/logout and revokes the client's current token. It is idempotent: an unknown or missing token also succeeds. The client keeps the revoked token until SetToken("") is called.
func (c *Client) Logout(ctx context.Context) error {
	return c.do(ctx, http.MethodPost, api("auth", "logout"), nil, nil, nil)
}

// CurrentUser calls GET /api/v1/users/me. Requires a token.
func (c *Client) CurrentUser(ctx context.Context) (*User, error) {
	var out User
	if err := c.do(ctx, http.MethodGet, api("users", "me"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// SetPassword calls POST /api/v1/users/me/password and sets or replaces the account password (at least 8 characters, otherwise 400 PASSWORD_INVALID), which enables LoginPassword for later sessions. Requires a token.
func (c *Client) SetPassword(ctx context.Context, password string) error {
	return c.do(ctx, http.MethodPost, api("users", "me", "password"), nil, map[string]string{"password": password}, nil)
}
