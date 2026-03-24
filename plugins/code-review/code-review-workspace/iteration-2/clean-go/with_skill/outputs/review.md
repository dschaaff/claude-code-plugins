# Code Review: main
2 files changed | 2026-03-24

**Pre-review checks**: No `go.mod` present in the repository, so the code cannot be compiled or tested. This is a scaffold/partial repo -- tests and linting could not be run.

## Strengths
- Clean separation between `ListItems` and `GetItem` with consistent patterns for auth checks, error handling, and JSON encoding.
- Pagination defaults and clamping are sensible (page defaults to 1, per_page capped at 100, defaults to 20).
- Structured logging with `slog` includes relevant context (user_id, item_id, error).
- `GetItem` correctly distinguishes `store.ErrNotFound` from unexpected errors, returning appropriate HTTP status codes.
- Tests cover the happy path, not-found, unauthorized, and invalid pagination parameters.

## Important Issues

### Missing test for cross-user item access in GetItem
- **Location**: `handler_test.go`
- **Problem**: There is no test verifying that user A cannot retrieve an item belonging to user B. The handler delegates ownership scoping to `s.store.GetItem(ctx, userID, itemID)`, but without a test, there is no guarantee the store mock or future refactors enforce this correctly.
- **Fix**: Add a test that creates an item for user 2 and attempts to fetch it as user 1, asserting a 404 response:
```go
func TestGetItem_WrongUser(t *testing.T) {
    s := newTestServer(t)
    s.store.AddItem(store.Item{ID: 1, UserID: 2, Title: "other-user"})

    req := httptest.NewRequest("GET", "/items/1", nil)
    req = req.WithContext(context.WithValue(req.Context(), userIDKey, int64(1)))
    req.SetPathValue("id", "1")
    w := httptest.NewRecorder()

    s.GetItem(w, req)

    if w.Code != http.StatusNotFound {
        t.Fatalf("expected 404 for wrong user, got %d", w.Code)
    }
}
```

### Missing test for store error path in ListItems
- **Location**: `handler_test.go`
- **Problem**: There is no test verifying that `ListItems` returns 500 when the store returns an error. The error branch at `handler.go:33-36` is untested.
- **Fix**: Add a test that configures the mock store to return an error, then assert a 500 response.

### No go.mod -- code cannot be built or tested
- **Location**: repository root
- **Problem**: The repository has no `go.mod`, no supporting types (`Server`, `PaginatedResponse`, `userIDKey`), and no test helper (`newTestServer`). The code cannot compile as-is.
- **Fix**: Ensure the full module structure is committed. At minimum: `go.mod`, the type definitions for `Server`, `PaginatedResponse`, `userIDKey`, and the `newTestServer` helper.

## Suggestions

### ListItems silently ignores non-numeric page/per_page values
- **Location**: `handler.go:21-28`
- **Problem**: `strconv.Atoi` errors are silently discarded. Passing `?page=abc` silently defaults to page 1. This is a reasonable UX choice but could mask client bugs. Consider whether returning 400 for non-numeric values would be more appropriate for your API contract.

### Response body already written before encode error
- **Location**: `handler.go:44-46`, `handler.go:76-78`
- **Problem**: If `json.NewEncoder(w).Encode(resp)` partially writes then fails, the client receives a truncated JSON body with a 200 status (headers are already flushed). This is an inherent limitation of streaming JSON encoding. For small payloads like these, marshaling to a byte slice first and writing the full response atomically avoids the issue:
```go
data, err := json.Marshal(resp)
if err != nil {
    slog.Error("failed to marshal response", "err", err)
    http.Error(w, "internal error", http.StatusInternalServerError)
    return
}
w.Header().Set("Content-Type", "application/json")
w.Write(data)
```

### Test for ListItems response body does not verify the returned items
- **Location**: `handler_test.go:13-42`
- **Problem**: `TestListItems_DefaultPagination` checks `Total`, `Page`, and `PerPage` but never inspects `resp.Items`. This means a bug that returns the wrong items (or no items) would pass the test.
- **Fix**: Assert `len(resp.Items) == 2` and verify the item contents.

## Next Steps
1. Add the missing module structure (`go.mod`, types, test helper) so the code compiles and tests run.
2. Add a cross-user access test for `GetItem`.
3. Add a store-error test for `ListItems`.
4. Verify `resp.Items` content in `TestListItems_DefaultPagination`.
5. Consider marshaling to `[]byte` before writing to avoid partial response risk.
