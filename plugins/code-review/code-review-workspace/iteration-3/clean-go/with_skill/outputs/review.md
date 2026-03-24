# Code Review: main
2 files changed | 2026-03-24

**Pre-review checks**: No go.mod, Makefile, or linter configuration found in the repository. Could not run `go test`, `go vet`, or `golangci-lint`. Recommend adding a `go.mod` and basic CI configuration.

## Strengths
- Clean separation between `ListItems` and `GetItem` handlers with consistent patterns across both
- Good input validation: page/per_page are clamped to sensible defaults rather than returning errors for bad values
- Proper auth check at the top of every handler using context values
- `GetItem` correctly distinguishes `store.ErrNotFound` from unexpected errors, returning 404 vs 500
- Structured logging with `slog` includes relevant context fields (`user_id`, `item_id`, `err`)
- Test coverage includes the happy path, not-found, unauthorized, and invalid pagination parameters
- Tests use `httptest` correctly and verify both status codes and response body contents

## Suggestions

### Consider validating non-numeric `per_page` values explicitly
- **Location**: `handler.go:26`
- **Problem**: When `per_page` is a non-integer string (e.g., `?per_page=abc`), `strconv.Atoi` returns `0, err`, and the code silently falls through to the default of 20. This is fine behavior, but a client sending garbage might appreciate a 400 response so they know their parameter was ignored.
  ```go
  perPage, _ := strconv.Atoi(r.URL.Query().Get("per_page"))
  ```
- **Fix**: This is a design choice -- the current "clamp to defaults" approach is perfectly valid for a paginated list endpoint. Just noting the tradeoff: silent fallback is friendlier for casual use, explicit errors are better for API contracts. No change required unless the API has a strict contract.

### Add a test for `GetItem` happy path
- **Location**: `handler_test.go`
- **Problem**: `GetItem` is tested for not-found and unauthorized cases, but there is no test that retrieves an existing item and verifies the response body. This is the most common code path and should be covered.
- **Fix**: Add a test that inserts an item, requests it, and asserts on the decoded response:
  ```go
  func TestGetItem_Success(t *testing.T) {
      s := newTestServer(t)
      s.store.AddItem(store.Item{ID: 1, UserID: 1, Title: "test-item"})

      req := httptest.NewRequest("GET", "/items/1", nil)
      req = req.WithContext(context.WithValue(req.Context(), userIDKey, int64(1)))
      req.SetPathValue("id", "1")
      w := httptest.NewRecorder()

      s.GetItem(w, req)

      if w.Code != http.StatusOK {
          t.Fatalf("expected 200, got %d", w.Code)
      }

      var item store.Item
      if err := json.NewDecoder(w.Body).Decode(&item); err != nil {
          t.Fatalf("decode: %v", err)
      }
      if item.Title != "test-item" {
          t.Errorf("expected title=%q, got %q", "test-item", item.Title)
      }
  }
  ```

### Add a test for `GetItem` with an invalid (non-numeric) ID
- **Location**: `handler_test.go`
- **Problem**: The handler returns 400 for non-numeric IDs (`handler.go:60-63`), but no test exercises this path.
- **Fix**:
  ```go
  func TestGetItem_InvalidID(t *testing.T) {
      s := newTestServer(t)

      req := httptest.NewRequest("GET", "/items/abc", nil)
      req = req.WithContext(context.WithValue(req.Context(), userIDKey, int64(1)))
      req.SetPathValue("id", "abc")
      w := httptest.NewRecorder()

      s.GetItem(w, req)

      if w.Code != http.StatusBadRequest {
          t.Fatalf("expected 400, got %d", w.Code)
      }
  }
  ```

### Add a test for `ListItems` unauthorized path
- **Location**: `handler_test.go`
- **Problem**: The unauthorized case is tested for `GetItem` but not for `ListItems`. Both handlers have the same auth check and both should be covered.

## Next Steps
1. Add the missing happy-path test for `GetItem` and the invalid-ID test
2. Add an unauthorized test for `ListItems` for symmetry
3. Add `go.mod` and basic project infrastructure (linter config, Makefile) so automated checks can run
