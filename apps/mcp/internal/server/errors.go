package server

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"

	"forgeplay/mcp/internal/config"
	"forgeplay/sdk"
)

const (
	// maxBackendMessage caps the message of a backend error envelope in a tool error. Real messages are one sentence.
	maxBackendMessage = 1000
	// maxForeignExcerpt is how much of an answer that is not a ForgePlay error is quoted: enough to recognise a proxy page or another service, not enough to flood the model's context.
	maxForeignExcerpt = 200
)

// errAuthRequired is returned by tools that need a signed-in user when no token is configured. It is raised before any request is sent.
var errAuthRequired = errors.New("authentication required: set " + config.EnvToken + " (obtain with: forgeplay auth login, then forgeplay auth token)")

// requireToken fails with errAuthRequired when the backend client is anonymous.
func (s *service) requireToken() error {
	if s.backend.Token() == "" {
		return errAuthRequired
	}
	return nil
}

// backendError turns an error from forgeplay/sdk into a tool error that says what failed, what the backend answered and what to do next. action names the attempted step, such as "fork game g_1". The text goes to the model, so it never carries the raw backend URL (it may hold credentials) and never more than a short excerpt of an answer that is not a ForgePlay error.
func (s *service) backendError(action string, err error) error {
	var apiErr *sdk.APIError
	if errors.As(err, &apiErr) {
		return s.answerError(action, apiErr)
	}
	// A transport failure is a *url.Error whose text repeats the request URL; only its cause is shown.
	cause := err
	var urlErr *url.Error
	transport := errors.As(err, &urlErr)
	if transport {
		cause = urlErr.Err
	}
	switch {
	case errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded):
		return fmt.Errorf("%s: the request to the ForgePlay backend at %s was cancelled or timed out: %v", action, s.backendURL, cause)
	case transport:
		return fmt.Errorf("%s: cannot reach the ForgePlay backend at %s: %v. Check that the backend is running and that %s points at it", action, s.backendURL, cause, config.EnvServerURL)
	case errors.Is(err, sdk.ErrInvalidArgument):
		return fmt.Errorf("%s: no request was sent, because the id is not usable: %v. Pass an id exactly as a tool returned it", action, err)
	case errors.Is(err, sdk.ErrBadResponse):
		return fmt.Errorf("%s: %s answered, but not like a ForgePlay backend: %v. Check that %s is the root URL of the backend, without /api/v1", action, s.backendURL, err, config.EnvServerURL)
	default:
		return fmt.Errorf("%s: the request to the ForgePlay backend at %s failed: %v", action, s.backendURL, err)
	}
}

// answerError describes a non-2xx answer.
func (s *service) answerError(action string, apiErr *sdk.APIError) error {
	if apiErr.Code == "" {
		// Not an error envelope: a proxy error page, a login page, or another service altogether. Its body is not relayed beyond a short excerpt.
		answer := fmt.Sprintf("%d %s", apiErr.StatusCode, http.StatusText(apiErr.StatusCode))
		if apiErr.Message != "" && apiErr.Message != http.StatusText(apiErr.StatusCode) {
			answer += fmt.Sprintf(", and the body starts with %q", excerpt(apiErr.Message, maxForeignExcerpt))
		}
		return fmt.Errorf("%s: %s answered %s. That is not a ForgePlay API error: %s probably points at another service, or a proxy in front of the backend failed", action, s.backendURL, answer, config.EnvServerURL)
	}
	answer := fmt.Sprintf("%d %s", apiErr.StatusCode, apiErr.Code)
	if apiErr.Message != "" && apiErr.Message != apiErr.Code {
		answer += ": " + excerpt(apiErr.Message, maxBackendMessage)
	}
	return fmt.Errorf("%s: the backend answered %s. %s", action, answer, s.hint(apiErr))
}

// hint is the next step suggested for a backend error.
func (s *service) hint(apiErr *sdk.APIError) string {
	switch {
	case apiErr.StatusCode == http.StatusUnauthorized && s.backend.Token() == "":
		return "This server is anonymous; " + errAuthRequired.Error() + "."
	case apiErr.StatusCode == http.StatusUnauthorized:
		return "The token in " + config.EnvToken + " was rejected (expired, revoked or for another backend). Obtain a new one with: forgeplay auth login --force, then forgeplay auth token."
	case apiErr.Code == sdk.CodeQuotaExceeded:
		return "The daily AI generation quota is used up. Write the patch yourself: check it with apply_dsl_patch and save it with update_mod."
	case apiErr.StatusCode == http.StatusTooManyRequests:
		return "The backend is rate limiting this client. Wait before retrying."
	case apiErr.StatusCode == http.StatusForbidden && s.backend.Token() == "":
		return "Drafts are private to their author and this server is anonymous; " + errAuthRequired.Error() + "."
	case apiErr.StatusCode == http.StatusForbidden:
		return "The resource belongs to another user: a draft can be read, updated and published by its author only. Use a mod_id returned to you by fork_game, create_mod, update_mod or list_my_drafts."
	case apiErr.StatusCode == http.StatusNotFound:
		return "Check the id: list_games returns game ids; fork_game, create_mod, update_mod and list_my_drafts return mod ids. A game that is not published is visible to its author only."
	case apiErr.Code == sdk.CodeInvalidState:
		return "The mod is not a draft any more, most likely because it was already published. Fork the game again to keep editing."
	case apiErr.Code == sdk.CodePublishInvalid:
		return "A publish request needs a non-empty title, at most 3 tags, a draft owned by the token's user and an effective DSL that passes validate_dsl."
	case apiErr.Code == sdk.CodeDSLInvalid:
		return "The backend could not build a valid DSL from the request. Check the document with validate_dsl and the patch with apply_dsl_patch; for generate_mod, rephrase the instruction or write the patch yourself."
	case apiErr.Code == sdk.CodeContentRejected:
		return "The text was rejected by content moderation. Rephrase the title, summary, tags or instruction."
	case apiErr.Code == sdk.CodeProviderError:
		return "The backend's AI provider failed. Retry later, or write the patch yourself and save it with update_mod."
	case apiErr.StatusCode >= 500:
		return "This is a backend failure, not a problem with the arguments. Retry later."
	default:
		return "Correct the arguments and call the tool again."
	}
}
