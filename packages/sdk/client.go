// Package sdk is a typed Go client for the Classic Games backend HTTP API (apps/server). It is the transport layer shared by the classic-games CLI and the classic-games-mcp server, and it only depends on the standard library.
//
// Create a client with New, authenticate with one of the Login methods plus SetToken, then call the endpoint methods. Every call takes a context and returns typed values; a non-2xx response is returned as *APIError.
package sdk

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Version is the SDK version reported in the default User-Agent header.
const Version = "0.1.0"

// DefaultBaseURL is the address a locally started backend listens on (PORT defaults to 8080).
const DefaultBaseURL = "http://localhost:8080"

// DefaultTimeout bounds one request when the caller does not inject an *http.Client. It is generous because POST /ai/mod may call the model up to three times before answering.
const DefaultTimeout = 2 * time.Minute

const (
	apiPrefix        = "/api/v1"
	defaultUserAgent = "classic-games-sdk-go/" + Version
	maxErrorBody     = 1 << 20
	// maxResponseBody bounds a 2xx body. It is far above any real answer (the largest are replays with 18,000 frames and full listing pages, a few MiB), so reaching it means the URL does not point at a Classic Games backend.
	maxResponseBody = 32 << 20
)

// Client talks to one Classic Games backend. It is safe for concurrent use.
type Client struct {
	baseURL    string
	httpClient *http.Client
	userAgent  string
	language   string

	mu    sync.RWMutex
	token string
}

// Option customises a Client at construction time.
type Option func(*Client)

// WithHTTPClient replaces the HTTP client used for every request. Use it to set timeouts, proxies, a custom transport or a test transport. A nil client is ignored.
func WithHTTPClient(httpClient *http.Client) Option {
	return func(c *Client) {
		if httpClient != nil {
			c.httpClient = httpClient
		}
	}
}

// WithToken sets the bearer token sent as "Authorization: Bearer <token>". Tokens come from the Login methods or RefreshToken.
func WithToken(token string) Option {
	return func(c *Client) { c.token = token }
}

// WithUserAgent replaces the User-Agent header. An empty value keeps the default.
func WithUserAgent(userAgent string) Option {
	return func(c *Client) {
		if userAgent != "" {
			c.userAgent = userAgent
		}
	}
}

// WithLanguage selects the language of localized error messages, game titles and summaries. The backend supports "zh" (its default), "en" and "ja". The value is sent as Accept-Language, and as the lang query parameter on the two listings that only read the query string (ranking and a user's games).
func WithLanguage(language string) Option {
	return func(c *Client) { c.language = language }
}

// New returns a client for the backend at baseURL, which is the server root such as "http://localhost:8080" (not the /api/v1 prefix; the client adds it). A path prefix is kept, so a backend published under "https://example.com/classic-games" works.
func New(baseURL string, options ...Option) (*Client, error) {
	trimmed := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	parsed, err := url.Parse(trimmed)
	if err != nil {
		return nil, fmt.Errorf("sdk: invalid base URL %q: %w", baseURL, err)
	}
	if (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return nil, fmt.Errorf("sdk: invalid base URL %q: want http(s)://host[:port][/prefix]", baseURL)
	}
	if parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, fmt.Errorf("sdk: invalid base URL %q: query and fragment are not allowed", baseURL)
	}
	client := &Client{
		baseURL:    trimmed,
		httpClient: &http.Client{Timeout: DefaultTimeout},
		userAgent:  defaultUserAgent,
	}
	for _, option := range options {
		if option != nil {
			option(client)
		}
	}
	return client, nil
}

// BaseURL returns the server root this client was created with, without a trailing slash.
func (c *Client) BaseURL() string { return c.baseURL }

// Token returns the bearer token currently sent with requests, or "" when the client is anonymous.
func (c *Client) Token() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.token
}

// SetToken replaces the bearer token; "" makes the client anonymous. It is the only method that changes the client's credentials: the Login methods and RefreshToken return a token and leave the client untouched.
func (c *Client) SetToken(token string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.token = token
}

// segment escapes one dynamic path segment, which keeps "?" and "#" in an id out of the query string and the fragment. Escaping does not make "/" safe: the backend routes on the decoded path, so an id such as "g1/comments" would reach another endpoint. do therefore rejects every path that carries an escaped slash or a dot segment.
func segment(value string) string { return url.PathEscape(value) }

// api builds an /api/v1 path from already escaped parts.
func api(parts ...string) string { return apiPrefix + "/" + strings.Join(parts, "/") }

// do sends one request and decodes a 2xx JSON response into out. body is JSON-encoded when non-nil; out may be nil to discard the response body.
func (c *Client) do(ctx context.Context, method, path string, query url.Values, body, out any) error {
	// An empty id would turn a resource path into another route: GET /games/ is the catalog listing, which decodes into a zero-value Game without any error. Every path here is built by api from non-empty parts, so an empty segment can only come from an empty argument.
	if strings.HasSuffix(path, "/") || strings.Contains(path, "//") {
		return &localError{class: ErrInvalidArgument, message: fmt.Sprintf("sdk: %s %s: empty path parameter (an id or name argument is empty)", method, path)}
	}
	// The static parts of a path never contain "%2F", "." or "..", so these can only come from an id or name argument. The backend decodes the path before routing, which would turn them into extra or missing segments.
	if strings.Contains(strings.ToUpper(path), "%2F") {
		return &localError{class: ErrInvalidArgument, message: fmt.Sprintf("sdk: %s %s: invalid path parameter (an id or name argument contains \"/\")", method, path)}
	}
	for _, part := range strings.Split(path, "/") {
		if part == "." || part == ".." {
			return &localError{class: ErrInvalidArgument, message: fmt.Sprintf("sdk: %s %s: invalid path parameter (an id or name argument is %q)", method, path, part)}
		}
	}
	target := c.baseURL + path
	if len(query) > 0 {
		target += "?" + query.Encode()
	}
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("sdk: %s %s: encode request: %w", method, path, err)
		}
		reader = bytes.NewReader(encoded)
	}
	request, err := http.NewRequestWithContext(ctx, method, target, reader)
	if err != nil {
		return fmt.Errorf("sdk: %s %s: build request: %w", method, path, err)
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("User-Agent", c.userAgent)
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	if c.language != "" {
		request.Header.Set("Accept-Language", c.language)
	}
	if token := c.Token(); token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}

	response, err := c.httpClient.Do(request)
	if err != nil {
		return fmt.Errorf("sdk: %s %s: %w", method, path, err)
	}
	defer response.Body.Close()

	if response.StatusCode < 200 || response.StatusCode > 299 {
		return newAPIError(method, path, response)
	}
	if out == nil || response.StatusCode == http.StatusNoContent {
		_, _ = io.Copy(io.Discard, response.Body)
		return nil
	}
	// One byte more than the cap is let through so that reaching it is told apart from a body of exactly the cap.
	limited := &io.LimitedReader{R: response.Body, N: maxResponseBody + 1}
	decodeErr := json.NewDecoder(limited).Decode(out)
	if limited.N <= 0 {
		return &localError{class: ErrBadResponse, message: fmt.Sprintf("sdk: %s %s: response larger than %d bytes", method, path, maxResponseBody)}
	}
	if decodeErr != nil {
		return &localError{class: ErrBadResponse, cause: decodeErr, message: fmt.Sprintf("sdk: %s %s: decode response: %v", method, path, decodeErr)}
	}
	return nil
}

// langQuery adds the client language as the lang query parameter, for listings that ignore Accept-Language.
func (c *Client) langQuery(query url.Values) url.Values {
	if c.language != "" {
		if query == nil {
			query = url.Values{}
		}
		query.Set("lang", c.language)
	}
	return query
}

// itemsEnvelope is the {"items": [...]} wrapper most unpaginated listings use.
type itemsEnvelope[T any] struct {
	Items []T `json:"items"`
}

// listItems fetches an unpaginated {"items": [...]} listing.
func listItems[T any](ctx context.Context, c *Client, path string, query url.Values) ([]T, error) {
	var envelope itemsEnvelope[T]
	if err := c.do(ctx, http.MethodGet, path, query, nil, &envelope); err != nil {
		return nil, err
	}
	return envelope.Items, nil
}
