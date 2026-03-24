# Code Review: Paginated Items API Handler

**Files reviewed:** `handler.go`, `handler_test.go`

## Architecture

The handler design is clean and well-structured. Two endpoints (`ListItems`, `GetItem`) follow standard Go HTTP handler patterns with proper separation of concerns -- the store interface handles data access while the handler manages HTTP concerns. The use of `slog` for structured logging is a good choice.

## Issues

### 1. Context value key for authentication is fragile (handler.go:16)

```go
userID, ok := r.Context().Value(userIDKey).(int64)
```

Using context values for authentication is a common Go pattern, but the `userIDKey` type is not visible in the diff. If it is a plain string (e.g., `const userIDKey = "userID"`), any package can collide with it. Verify that `userIDKey` is defined as an unexported custom type (e.g., `type contextKey struct{}`) to prevent collisions.

**Severity:** Medium -- potential security issue if the key type allows external overwrites.

### 2. Silent parse error on `page` and `per_page` (handler.go:21-27)

```go
page, _ := strconv.Atoi(r.URL.Query().Get("page"))
```

Non-numeric values like `?page=abc` silently fall back to 0, which then gets clamped to 1. This is fine as defensive behavior, but the API gives no signal to the caller that their input was ignored. Consider whether a 400 response for non-numeric values would be more appropriate -- it depends on the API contract. At minimum, document this behavior.

**Severity:** Low -- functional but potentially surprising to API consumers.

### 3. `per_page` validation conflates "too low" and "too high" (handler.go:24-27)

```go
if perPage < 1 || perPage > 100 {
    perPage = 20
}
```

A request with `?per_page=500` silently drops to 20 instead of clamping to 100. If a client asks for 500, they probably want as many as possible, so clamping to the max (100) would be less surprising than resetting to the default (20). Recommended fix:

```go
if perPage < 1 {
    perPage = 20
}
if perPage > 100 {
    perPage = 100
}
```

**Severity:** Low -- behavioral surprise for API consumers.

### 4. Missing `Content-Type` header before error responses (handler.go throughout)

`http.Error()` writes `text/plain` responses, while success paths write `application/json`. This inconsistency means clients cannot rely on `Content-Type` to detect errors. Consider returning JSON-formatted error bodies for consistency, especially if this API serves JavaScript clients that parse all responses as JSON.

**Severity:** Low -- standard Go behavior but worth noting for API consistency.

### 5. Response written before error check on `json.Encode` (handler.go:42-45)

```go
w.Header().Set("Content-Type", "application/json")
if err := json.NewEncoder(w).Encode(resp); err != nil {
    slog.Error("failed to encode response", "err", err)
}
```

By the time `Encode` fails partway through, partial bytes may have already been written to the response. The status code (implicit 200) has already been sent. There is no way to send an error status at this point. This is a known limitation with streaming JSON encoding in Go. For small payloads like paginated lists, consider marshaling to a byte slice first with `json.Marshal`, which lets you detect errors before writing anything:

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

**Severity:** Medium -- partial response corruption on marshal failure.

### 6. `PaginatedResponse.Items` may serialize as `null` (handler.go:36)

If `s.store.ListItems` returns a nil slice, `json.Encode` will produce `"Items": null` instead of `"Items": []`. This is a common source of client-side bugs. Ensure the store returns an empty slice, or add a nil guard:

```go
if items == nil {
    items = []store.Item{}
}
```

**Severity:** Medium -- `null` vs `[]` causes real bugs in frontend clients.

### 7. `GetItem` does not verify HTTP method (handler.go:49)

Neither handler checks `r.Method`. If these are mounted via a mux that does not enforce methods (e.g., `http.HandleFunc("/items", s.ListItems)`), both endpoints will accept POST, PUT, DELETE, etc. If the router handles method routing (Go 1.22+ `mux.HandleFunc("GET /items", ...)`) this is fine, but it is worth confirming.

**Severity:** Low -- depends on router configuration.

## Test Coverage

### What is covered well

- Default pagination values on `ListItems`
- 404 on missing item in `GetItem`
- 401 on missing auth context in `GetItem`
- Negative/zero page and per_page clamping

### Gaps

- **No test for `ListItems` unauthorized path.** `TestGetItem_Unauthorized` exists but there is no equivalent for `ListItems`. The code path is identical, but test coverage should confirm both handlers.
- **No test for `GetItem` success path.** There is no test that fetches an existing item and verifies the response body.
- **No test for invalid `id` path parameter.** `r.PathValue("id")` with a non-numeric value (e.g., `"abc"`) should return 400. This is untested.
- **No test for store error (non-NotFound).** The `GetItem` handler has a branch for generic store errors that returns 500. This path is untested.
- **No test for `ListItems` store failure.** The 500 error branch in `ListItems` is untested.
- **No test for `per_page` exceeding maximum.** The test sends `per_page=0` but not `per_page=200`. Given the per_page clamping issue noted above, this would be valuable.
- **No test for actual pagination.** No test verifies that page 2 returns different items than page 1, or that the `Total` field is correct across pages.
- **`newTestServer` is not in the diff.** The test helper and mock store are not visible. Verify that the mock store's `ListItems` correctly implements pagination logic (offset/limit) rather than always returning all items.

## Summary

The handler code is well-organized and follows Go conventions. The main areas to address are:

1. **Marshal before write** to avoid partial responses (medium).
2. **Nil slice guard** on `Items` to avoid `null` in JSON (medium).
3. **Separate per_page clamping** for low vs. high values (low).
4. **Add missing tests** for success paths, error branches, and actual pagination behavior.
