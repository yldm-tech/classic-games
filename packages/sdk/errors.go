package sdk

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"unicode/utf8"
)

// Error codes the backend puts in the error envelope. The list covers the endpoints this SDK wraps; an unknown code is still reported verbatim in APIError.Code.
const (
	CodeBadRequest      = "BAD_REQUEST"      // 400: malformed body, cursor or parameter.
	CodeAuthRequired    = "AUTH_REQUIRED"    // 401: missing, unknown or expired token.
	CodeAuthInvalid     = "AUTH_INVALID"     // 401: wrong SMS code or password; 429 when password attempts are exhausted.
	CodeForbidden       = "FORBIDDEN"        // 403: not the owner, or someone else's draft.
	CodeNotFound        = "NOT_FOUND"        // 404.
	CodeGameHasNoMod    = "GAME_HAS_NO_MOD"  // 404: the game is listed but has no mod behind it (a showcase game), so its DSL, lineage and fork tree cannot be read and it cannot be forked.
	CodeInvalidState    = "INVALID_STATE"    // 409: the resource is not in a state that allows the operation.
	CodeDSLInvalid      = "DSL_INVALID"      // 422: patch does not apply or the DSL fails schema validation.
	CodeContentRejected = "CONTENT_REJECTED" // 422: text rejected by content moderation.
	CodeRateLimited     = "RATE_LIMITED"     // 429: SMS code requested again within the cooldown.
	CodeQuotaExceeded   = "QUOTA_EXCEEDED"   // 429: daily AI quota used up.
	CodeProviderError   = "PROVIDER_ERROR"   // 502: the model provider failed; the call still counts against the quota.
	CodePublishInvalid  = "PUBLISH_INVALID"  // 400: publish request rejected (title, tags, ownership or invalid mod).
	CodeCommentInvalid  = "COMMENT_INVALID"  // 400: empty or too long comment.
	CodeRatingInvalid   = "RATING_INVALID"   // 400: rating outside 1..5.
	CodePostInvalid     = "POST_INVALID"     // 400: empty or too long community post.
	CodeReplayInvalid   = "REPLAY_INVALID"   // 400: replay frames or duration rejected.
	CodeReplayNotFound  = "REPLAY_NOT_FOUND" // 404: the user has no replay for the game.
	CodePasswordInvalid = "PASSWORD_INVALID" // 400: password shorter than 8 characters.
	CodeTeenBlocked     = "TEEN_BLOCKED"     // 403: play blocked by teen-mode limits.
	CodeInternal        = "INTERNAL"         // 500.
)

// Sentinel errors for failures that are not backend answers. Match them with errors.Is; the error text is unchanged by the classification.
var (
	// ErrInvalidArgument marks an error raised before any request was sent, because an id or name argument cannot be part of a request path: it is empty, contains "/" or is "." or "..".
	ErrInvalidArgument = errors.New("sdk: invalid argument")
	// ErrBadResponse marks a 2xx answer that could not be used: the body is not the expected JSON, or it exceeds the size limit. It usually means the base URL does not point at a Classic Games backend.
	ErrBadResponse = errors.New("sdk: unusable response")
)

// localError is an error raised by the client itself. It matches its class with errors.Is and keeps the cause reachable, while its text is exactly message.
type localError struct {
	message string
	class   error
	cause   error
}

func (e *localError) Error() string { return e.message }

func (e *localError) Unwrap() []error {
	if e.cause == nil {
		return []error{e.class}
	}
	return []error{e.class, e.cause}
}

// maxErrorExcerpt is how much of a response body that is not an error envelope is kept in APIError.Message. Such a body is a proxy error page or the answer of another service, which can be megabytes of HTML.
const maxErrorExcerpt = 512

// APIError is returned for every non-2xx response. Use errors.As to reach it, or the IsCode / IsStatus helpers.
//
// The single-resource getters (GetGame, GetMod, GetModForkTree, GetUserProfile, GetLatestReplay) also return it, as 404 NOT_FOUND, when the backend answers 2xx with something that is not the requested resource. That happens when the id equals a fixed route of the backend, such as "mine" in /games/mine: no resource has that id, so the lookup is reported as not found.
type APIError struct {
	// StatusCode is the HTTP status of the response, or 404 for a 2xx answer that is not the requested resource.
	StatusCode int
	// Code is the machine-readable code from the error envelope, such as "NOT_FOUND". It is empty when the response was not an envelope (for example a proxy error page or an unknown route).
	Code string
	// Message is the human-readable message from the envelope, localized by the backend. For a non-envelope response it holds the start of the response body (at most 512 bytes, followed by a note of how many bytes were left out), or the HTTP status text.
	Message string
	// Details carries the optional envelope details object. The backend currently never fills it.
	Details map[string]any
	// Method and Path identify the request that failed.
	Method string
	Path   string
}

func (e *APIError) Error() string {
	code := e.Code
	if code == "" {
		code = http.StatusText(e.StatusCode)
	}
	if e.Message == "" || e.Message == code {
		return fmt.Sprintf("classic-games: %s %s: %d %s", e.Method, e.Path, e.StatusCode, code)
	}
	return fmt.Sprintf("classic-games: %s %s: %d %s: %s", e.Method, e.Path, e.StatusCode, code, e.Message)
}

// IsCode reports whether err is, or wraps, an *APIError with the given envelope code.
func IsCode(err error, code string) bool {
	var apiErr *APIError
	return errors.As(err, &apiErr) && apiErr.Code == code
}

// IsStatus reports whether err is, or wraps, an *APIError with the given HTTP status.
func IsStatus(err error, status int) bool {
	var apiErr *APIError
	return errors.As(err, &apiErr) && apiErr.StatusCode == status
}

// IsNotFound reports whether err is an *APIError with HTTP status 404.
func IsNotFound(err error) bool { return IsStatus(err, http.StatusNotFound) }

// IsUnauthorized reports whether err is an *APIError with HTTP status 401: the client has no token, or the token is unknown or expired.
func IsUnauthorized(err error) bool { return IsStatus(err, http.StatusUnauthorized) }

type errorEnvelope struct {
	Error *struct {
		Code    string         `json:"code"`
		Message string         `json:"message"`
		Details map[string]any `json:"details"`
	} `json:"error"`
}

func newAPIError(method, path string, response *http.Response) *APIError {
	apiErr := &APIError{StatusCode: response.StatusCode, Method: method, Path: path}
	raw, _ := io.ReadAll(io.LimitReader(response.Body, maxErrorBody))
	var envelope errorEnvelope
	if json.Unmarshal(raw, &envelope) == nil && envelope.Error != nil && (envelope.Error.Code != "" || envelope.Error.Message != "") {
		apiErr.Code = envelope.Error.Code
		apiErr.Message = envelope.Error.Message
		apiErr.Details = envelope.Error.Details
		return apiErr
	}
	apiErr.Message = excerpt(strings.TrimSpace(string(raw)))
	if apiErr.Message == "" {
		apiErr.Message = http.StatusText(response.StatusCode)
	}
	return apiErr
}

// excerpt cuts text to maxErrorExcerpt bytes on a rune boundary and says how much was left out.
func excerpt(text string) string {
	if len(text) <= maxErrorExcerpt {
		return text
	}
	end := maxErrorExcerpt
	for end > 0 && !utf8.RuneStart(text[end]) {
		end--
	}
	return fmt.Sprintf("%s ... (%d more bytes)", text[:end], len(text)-end)
}

// notTheResource is the error of a single-resource getter whose 2xx answer does not describe the resource that was asked for. The backend looks a resource up by its id, so a mismatch means another route answered: the id equals a fixed path word such as "mine" in /games/mine. No resource has such an id, which makes this a not-found result. kind names the resource in the message ("game", "mod", "user").
func notTheResource(path, kind, id string) *APIError {
	return &APIError{
		StatusCode: http.StatusNotFound,
		Code:       CodeNotFound,
		Message:    fmt.Sprintf("no %s has the id %q: the backend answered with a different resource", kind, id),
		Method:     http.MethodGet,
		Path:       path,
	}
}
