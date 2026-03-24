# Code Review: main (staged changes)
1 file changed | 2026-03-24

**Pre-review checks**: No test infrastructure, linter config, or dependency manifest found in this repository.

## Strengths
- Clear, simple Flask route structure that is easy to follow
- Consistent use of `jsonify` for API responses with appropriate HTTP status codes

## Critical Issues

### 1. Hardcoded API Key
- **Location**: `app.py:8`
- **Problem**: A secret API key is committed directly in source code. This will be in git history permanently and is trivially extractable by anyone with repo access.
- **Fix**: Load the key from an environment variable. Add it to `.env` (gitignored) or a secrets manager.
```python
import os
API_KEY = os.environ["API_KEY"]
```

### 2. SQL Injection in search_users
- **Location**: `app.py:22-23`
- **Problem**: User-supplied query parameter `q` is concatenated directly into a SQL string. An attacker can inject arbitrary SQL to extract, modify, or delete any data in the database.
- **Fix**: Use parameterized queries.
```python
cursor = db.execute(
    "SELECT id, name, email FROM users WHERE name LIKE ?",
    (f"%{query}%",),
)
```

### 3. SQL Injection in get_user
- **Location**: `app.py:35-36`
- **Problem**: f-string interpolation into SQL. Although `user_id` is typed as `int` by Flask's route converter (which mitigates this specific route), the pattern is dangerous and sets a bad precedent. If the type annotation were ever removed or changed, this becomes exploitable.
- **Fix**: Use parameterized queries.
```python
cursor = db.execute(
    "SELECT id, name, email, password_hash FROM users WHERE id = ?",
    (user_id,),
)
```

### 4. SQL Injection in create_user
- **Location**: `app.py:55-61`
- **Problem**: All three user-supplied fields (`name`, `email`, `password`) are concatenated into the SQL INSERT statement. This is the most dangerous injection in this file because the input is entirely attacker-controlled with no type constraints.
- **Fix**: Use parameterized queries.
```python
db.execute(
    "INSERT INTO users (name, email, password_hash) VALUES (?, ?, ?)",
    (data["name"], data["email"], hashed_password),
)
```

### 5. Plaintext Password Storage
- **Location**: `app.py:55-61`
- **Problem**: `data["password"]` is stored directly as `password_hash` without any hashing. Passwords are stored in plaintext, meaning a database breach exposes every user's credentials.
- **Fix**: Hash passwords before storage using `bcrypt` or `argon2`.
```python
from werkzeug.security import generate_password_hash
hashed = generate_password_hash(data["password"])
```

### 6. Password Hash Exposed in API Response
- **Location**: `app.py:40-45`
- **Problem**: The `get_user` endpoint returns `password_hash` in the JSON response. Even if passwords were properly hashed, exposing the hash enables offline brute-force attacks.
- **Fix**: Remove `password_hash` from the response.
```python
return jsonify({"id": row[0], "name": row[1], "email": row[2]})
```

## Important Issues

### 7. No Input Validation on User Creation
- **Location**: `app.py:52-62`
- **Problem**: No validation of required fields, email format, or password strength. Missing keys will raise an unhandled `KeyError` returning a 500 with a stack trace (information leakage when `debug=True`).
- **Fix**: Validate input and return 400 for bad requests.
```python
data = request.get_json()
if not data or not all(k in data for k in ("name", "email", "password")):
    return jsonify({"error": "name, email, and password are required"}), 400
```

### 8. Debug Mode Enabled on 0.0.0.0
- **Location**: `app.py:79`
- **Problem**: `debug=True` with `host="0.0.0.0"` exposes the Werkzeug debugger to all network interfaces. The debugger allows arbitrary code execution on the server.
- **Fix**: Never run debug mode in production. Bind to localhost for development.
```python
if __name__ == "__main__":
    app.run(debug=os.environ.get("FLASK_DEBUG", "false") == "true",
            host="127.0.0.1")
```

### 9. Database Connections Never Closed
- **Location**: `app.py:13-15`
- **Problem**: `get_db()` opens a new connection on every request but never closes it. This leaks connections and will eventually exhaust the SQLite connection limit or file descriptors.
- **Fix**: Use Flask's `g` object and `teardown_appcontext` to manage connection lifecycle.
```python
from flask import g

def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DATABASE)
    return g.db

@app.teardown_appcontext
def close_db(exception):
    db = g.pop("db", None)
    if db is not None:
        db.close()
```

### 10. Timing-Safe Comparison Not Used for API Key
- **Location**: `app.py:69`
- **Problem**: Using `==` to compare the API key allows timing attacks that can leak the key character by character.
- **Fix**: Use `hmac.compare_digest` for constant-time comparison.
```python
import hmac
if hmac.compare_digest(provided_key or "", API_KEY):
```

## Suggestions

### 11. No Rate Limiting on Any Endpoint
- **Location**: All routes
- **Problem**: The search and admin export endpoints are open to abuse. The create endpoint allows unlimited account creation.
- **Fix**: Add rate limiting with `flask-limiter`.

### 12. No Tests
- **Problem**: No test files exist. Every endpoint and error path should have test coverage.
- **Fix**: Add a `tests/` directory with pytest tests covering each route, including injection attempts and auth failures.

## Next Steps
1. Remove the hardcoded API key from source and rotate it immediately (it is now in git history)
2. Replace all string-concatenated SQL with parameterized queries (issues 2, 3, 4)
3. Hash passwords before storage and remove password_hash from API responses (issues 5, 6)
4. Disable debug mode and bind to localhost (issue 8)
5. Add input validation and proper DB connection management (issues 7, 9)
6. Add timing-safe key comparison (issue 10)
7. Add tests and rate limiting (issues 11, 12)
