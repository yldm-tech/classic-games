package sdk

import (
	"context"
	"fmt"
	"iter"
	"net/url"
	"strconv"
)

// Page limits enforced by the backend: a limit of 0 or less means DefaultPageLimit, and anything above MaxPageLimit is clamped to it.
const (
	DefaultPageLimit = 20
	MaxPageLimit     = 100
)

// PageParams selects one page of a cursor-paginated listing. The zero value asks for the first page with the server default size.
type PageParams struct {
	// Cursor is the NextCursor of the previous page; "" starts from the beginning. Cursors are opaque: do not build or parse them.
	Cursor string
	// Limit is the page size. 0 lets the server use DefaultPageLimit.
	Limit int
}

func (p PageParams) apply(query url.Values) {
	if p.Cursor != "" {
		query.Set("cursor", p.Cursor)
	}
	if p.Limit > 0 {
		query.Set("limit", strconv.Itoa(p.Limit))
	}
}

// Page is one page of a cursor-paginated listing, the backend's {"items": [...], "next_cursor": "..."} shape.
type Page[T any] struct {
	Items []T `json:"items"`
	// NextCursor is the cursor of the following page, or "" on the last page. A page can hold fewer items than the limit and still have a next page, because some filters run after paging; only NextCursor says whether more exist.
	NextCursor string `json:"next_cursor"`
}

// HasMore reports whether another page follows this one.
func (p *Page[T]) HasMore() bool { return p != nil && p.NextCursor != "" }

// Paginate returns an iterator over every item of a cursor-paginated listing. fetch is called with "" for the first page and then with each NextCursor until the last page. Iteration stops at the first error, which is yielded with the zero item.
//
//	for game, err := range sdk.Paginate(ctx, func(ctx context.Context, cursor string) (*sdk.Page[sdk.Game], error) {
//		return client.ListGames(ctx, sdk.ListGamesParams{Runtime: "shooter", PageParams: sdk.PageParams{Cursor: cursor, Limit: sdk.MaxPageLimit}})
//	}) {
//		if err != nil {
//			return err
//		}
//		fmt.Println(game.Title)
//	}
func Paginate[T any](ctx context.Context, fetch func(ctx context.Context, cursor string) (*Page[T], error)) iter.Seq2[T, error] {
	return func(yield func(T, error) bool) {
		var zero T
		cursor := ""
		for {
			page, err := fetch(ctx, cursor)
			if err != nil {
				yield(zero, err)
				return
			}
			if page == nil {
				yield(zero, fmt.Errorf("sdk: paginate: fetch returned a nil page"))
				return
			}
			for _, item := range page.Items {
				if !yield(item, nil) {
					return
				}
			}
			if page.NextCursor == "" {
				return
			}
			if page.NextCursor == cursor {
				yield(zero, fmt.Errorf("sdk: paginate: server returned the same cursor %q twice", cursor))
				return
			}
			cursor = page.NextCursor
		}
	}
}
