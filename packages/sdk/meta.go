package sdk

import (
	"context"
	"fmt"
	"net/http"
)

// Meta is the public, non-secret capability surface of a backend (GET /api/v1/meta). It tells a tool which optional integrations the operator has configured.
type Meta struct {
	// Environment is "development" or "production".
	Environment string `json:"environment"`
	AI          MetaAI `json:"ai"`
	// SMS is true when a real SMS gateway is configured. When false the backend generates login codes but delivers them nowhere, so SMS login cannot complete.
	SMS bool `json:"sms"`
	// OAuthProviders lists the third-party login providers that are configured, sorted by name.
	OAuthProviders  []string `json:"oauth_providers"`
	Payments        bool     `json:"payments"`
	AdminConfigured bool     `json:"admin_configured"`
	// Moderation is true when an external content moderation service is configured; the built-in keyword filter is always on.
	Moderation bool `json:"moderation"`
}

// MetaAI describes the AI provider behind the generation endpoints.
type MetaAI struct {
	// Mode is "live" when a real model is configured, or "stub" when the backend answers with a fixed, deterministic patch per runtime.
	Mode string `json:"mode"`
}

// AI provider modes reported in MetaAI.Mode.
const (
	AIModeLive = "live"
	AIModeStub = "stub"
)

// Health calls GET /healthz and returns nil when the backend reports it is up. No authentication.
func (c *Client) Health(ctx context.Context) error {
	var out struct {
		OK bool `json:"ok"`
	}
	if err := c.do(ctx, http.MethodGet, "/healthz", nil, nil, &out); err != nil {
		return err
	}
	if !out.OK {
		return fmt.Errorf("sdk: GET /healthz: backend reported ok=false")
	}
	return nil
}

// Meta calls GET /api/v1/meta. No authentication.
func (c *Client) Meta(ctx context.Context) (*Meta, error) {
	var out Meta
	if err := c.do(ctx, http.MethodGet, api("meta"), nil, nil, &out); err != nil {
		return nil, err
	}
	return &out, nil
}
