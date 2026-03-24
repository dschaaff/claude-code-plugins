# Code Review: app.py -- User Management Flask API

## Summary

This file contains multiple **critical security vulnerabilities** that would allow complete compromise of the application and its data. There are also significant code quality issues. This code must not be deployed in its current state.

---

## Security

### CRITICAL: SQL Injection (app.py:23, app.py:36, app.py:56-61)

All three query-building sites use string concatenation to embed user input directly into SQL statements. This allows an attacker to execute arbitrary SQL, including reading, modifying, or deleting all data.

**app.py:23** -- `search_users`:
```python
"SELECT id, name, email FROM users WHERE name LIKE '%" + query + "%'"
```
A request to `/users/search?q=' OR 1=1 --` dumps the entire table. More destructive payloads (`DROP TABLE`, `UNION SELECT`) are equally trivial.

**app.py:36** -- `get_user`:
```python
f"SELECT id, name, email, password_hash FROM users WHERE id = {user_id}"
```
The `int` type hint on the route provides some protection here, but the f-string pattern is still dangerous as a practice and should use parameterized queries.

**app.py:56-61** -- `create_user`:
```python
"INSERT INTO users (name, email, password_hash) VALUES ('"
    + data["name"] + "', '" + data["email"] + "', '" + data["password"] + "')"
```
Any of the three input fields can be used to inject SQL.

**Fix:** Use parameterized queries everywhere.
```python
cursor = db.execute(
    "SELECT id, name, email FROM users WHERE name LIKE ?",
    (f"%{query}%",),
)
```

### CRITICAL: Hardcoded API Key / Secret in Source (app.py:8)

```python
API_KEY = "sk-proj-a8f3k2m1n4p5q6r7s8t9u0v1w2x3y4z5"
```

A secret key is committed to source code. This will end up in version control history and is trivially extractable. Load secrets from environment variables or a secrets manager.

```python
import os
API_KEY = os.environ["API_KEY"]
```

### CRITICAL: Plaintext Password Storage (app.py:56-61)

The `create_user` endpoint stores `data["password"]` directly as `password_hash`. No hashing is performed. If the database is compromised, all user passwords are exposed in cleartext.

Use `bcrypt`, `argon2-cffi`, or `werkzeug.security.generate_password_hash` to hash passwords before storage.

### HIGH: Password Hash Exposed in API Response (app.py:40-45)

The `get_user` endpoint returns `password_hash` in the JSON response. Even if properly hashed, password hashes must never be sent to clients. Remove it from the SELECT and the response body.

### HIGH: No Input Validation (app.py:53-62)

`create_user` accesses `data["name"]`, `data["email"]`, and `data["password"]` without checking:
- Whether `request.get_json()` returned `None` (invalid/missing JSON body causes `TypeError`).
- Whether the required keys exist (missing keys cause `KeyError` with a 500 and stack trace leak).
- Whether the values are strings of acceptable length and format.

### HIGH: Timing-Vulnerable API Key Comparison (app.py:69)

```python
if provided_key == API_KEY:
```

String equality (`==`) is vulnerable to timing attacks. Use `hmac.compare_digest()` for constant-time comparison of secrets.

### MEDIUM: Debug Mode Enabled on 0.0.0.0 (app.py:79)

```python
app.run(debug=True, host="0.0.0.0")
```

`debug=True` enables the Werkzeug interactive debugger, which allows arbitrary code execution if reachable. Binding to `0.0.0.0` exposes the server on all interfaces. Together, this gives unauthenticated remote code execution to anyone on the network.

### MEDIUM: No CORS, Rate Limiting, or CSRF Protection

The API has no rate limiting, making brute-force attacks trivial. There is no CORS configuration. Flask's CSRF protection is not enabled.

---

## Code Quality

### Database Connection Leak (app.py:13-15)

`get_db()` creates a new connection on every call and never closes it. Connections accumulate until the process runs out of file descriptors.

**Options:**
1. Use Flask's `g` object with a `teardown_appcontext` handler to close connections at the end of each request.
2. Use a connection pool.

### No Database Schema Initialization

There is no code to create the `users` table. The application will crash on the first request to a fresh database. Add a schema initialization step or migration tool.

### No Error Handling

No `try/except` blocks anywhere. Database errors, malformed JSON, and missing fields all surface as unhandled 500s, potentially leaking stack traces (especially with `debug=True`).

### Inconsistent HTTP Status Codes and Response Shapes

- `search_users` returns a bare list on success.
- `get_user` returns an object on success, `{"error": "not found"}` on 404.
- `create_user` returns `{"status": "created"}`.
- `export_data` returns a bare list on success, `{"error": "unauthorized"}` on 401.

Standardize on a consistent response envelope.

### Magic Strings

The database name `"users.db"` is hardcoded. Use configuration (environment variable or Flask config) so test and production environments can differ.

---

## Recommendations (Priority Order)

1. **Replace all string-concatenated SQL with parameterized queries.** This is the single highest-impact fix.
2. **Remove the hardcoded API key.** Load from environment. Rotate the exposed key immediately if this was ever committed to a remote repository.
3. **Hash passwords** with `bcrypt` or `argon2-cffi` before storage.
4. **Remove `password_hash` from the `get_user` response.**
5. **Disable debug mode** and do not bind to `0.0.0.0` in production.
6. **Add input validation** for all endpoints; handle `None` from `get_json()` and missing keys.
7. **Fix database connection management** using Flask's `g` and `teardown_appcontext`.
8. **Use `hmac.compare_digest`** for API key comparison.
9. **Add rate limiting** (e.g., `flask-limiter`) and configure CORS.
10. **Standardize error handling and response formats** across all endpoints.
