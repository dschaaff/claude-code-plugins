# Code Review: main
1 file changed | 2026-03-24

**Pre-review checks**: No test infrastructure, linter configs, or dependency files found in the repository. No tests to run.

## Strengths
- Clear route structure with RESTful URL patterns (`app.py`)
- Docstring present at the module level
- Proper use of HTTP status codes (201 for creation, 404 for not found, 401 for unauthorized)

## Critical Issues

### 1. Hardcoded API Key
- **Location**: `app.py:8`
- **Problem**: A secret API key is committed directly in source code. This will be visible in version control history and to anyone with repo access.
  ```python
  API_KEY = "sk-proj-a8f3k2m1n4p5q6r7s8t9u0v1w2x3y4z5"
  ```
- **Fix**: Load the key from an environment variable. Fail fast if it is missing.
  ```python
  import os

  API_KEY = os.environ["API_KEY"]
  ```

### 2. SQL Injection in Search Endpoint
- **Location**: `app.py:22-23`
- **Problem**: User input from the query string is concatenated directly into a SQL query, allowing arbitrary SQL injection.
  ```python
  cursor = db.execute(
      "SELECT id, name, email FROM users WHERE name LIKE '%" + query + "%'"
  )
  ```
- **Fix**: Use parameterized queries.
  ```python
  cursor = db.execute(
      "SELECT id, name, email FROM users WHERE name LIKE ?",
      ("%" + query + "%",),
  )
  ```

### 3. SQL Injection in Get User Endpoint
- **Location**: `app.py:35-37`
- **Problem**: Although `user_id` is typed as `int` by Flask's route converter (which mitigates the risk here), the query still uses an f-string rather than parameterization. This sets a dangerous pattern for the codebase.
  ```python
  cursor = db.execute(
      f"SELECT id, name, email, password_hash FROM users WHERE id = {user_id}"
  )
  ```
- **Fix**: Use a parameterized query.
  ```python
  cursor = db.execute(
      "SELECT id, name, email, password_hash FROM users WHERE id = ?",
      (user_id,),
  )
  ```

### 4. SQL Injection in Create User Endpoint
- **Location**: `app.py:55-61`
- **Problem**: All three user-supplied fields are concatenated directly into an INSERT statement. This is the most exploitable injection point since POST body data is fully attacker-controlled.
  ```python
  db.execute(
      "INSERT INTO users (name, email, password_hash) VALUES ('"
      + data["name"]
      + "', '"
      + data["email"]
      + "', '"
      + data["password"]
      + "')"
  )
  ```
- **Fix**: Use parameterized queries and hash the password before storing it.
  ```python
  from werkzeug.security import generate_password_hash

  db.execute(
      "INSERT INTO users (name, email, password_hash) VALUES (?, ?, ?)",
      (data["name"], data["email"], generate_password_hash(data["password"])),
  )
  ```

### 5. Password Hash Exposed in API Response
- **Location**: `app.py:40-46`
- **Problem**: The `get_user` endpoint returns `password_hash` to the client. Password hashes must never leave the server.
  ```python
  return jsonify(
      {
          "id": row[0],
          "name": row[1],
          "email": row[2],
          "password_hash": row[3],
      }
  )
  ```
- **Fix**: Remove `password_hash` from the response and the SELECT query.
  ```python
  cursor = db.execute(
      "SELECT id, name, email FROM users WHERE id = ?",
      (user_id,),
  )
  row = cursor.fetchone()
  if row:
      return jsonify({"id": row[0], "name": row[1], "email": row[2]})
  return jsonify({"error": "not found"}), 404
  ```

### 6. Plaintext Password Storage
- **Location**: `app.py:55-61`
- **Problem**: The `create_user` endpoint stores `data["password"]` directly in the `password_hash` column without hashing. Despite the column name, no hashing is applied.
  ```python
  + data["password"]
  ```
- **Fix**: Hash the password before storage (see fix in issue 4 above using `generate_password_hash`).

## Important Issues

### 7. No Input Validation on User Creation
- **Location**: `app.py:53-54`
- **Problem**: The endpoint blindly accesses `data["name"]`, `data["email"]`, and `data["password"]` without checking that the JSON body exists or that these keys are present. A missing key raises an unhandled `KeyError`/`TypeError` that leaks a stack trace (especially with `debug=True`).
- **Fix**: Validate required fields and return a 400 on bad input.
  ```python
  @app.route("/users", methods=["POST"])
  def create_user():
      data = request.get_json()
      if not data:
          return jsonify({"error": "request body required"}), 400
      for field in ("name", "email", "password"):
          if field not in data:
              return jsonify({"error": f"missing field: {field}"}), 400
      # ... proceed with parameterized insert
  ```

### 8. Debug Mode Enabled on All Interfaces
- **Location**: `app.py:79`
- **Problem**: Running with `debug=True` and `host="0.0.0.0"` exposes the Werkzeug debugger on all network interfaces. The debugger allows arbitrary code execution.
  ```python
  app.run(debug=True, host="0.0.0.0")
  ```
- **Fix**: Never enable debug mode in production. Use environment-based configuration.
  ```python
  if __name__ == "__main__":
      app.run(
          debug=os.environ.get("FLASK_DEBUG", "false").lower() == "true",
          host="127.0.0.1",
      )
  ```

### 9. Database Connections Are Never Closed
- **Location**: `app.py:13-14`
- **Problem**: `get_db()` creates a new connection on every call and never closes it, leaking connections over time.
  ```python
  def get_db():
      conn = sqlite3.connect(DATABASE)
      return conn
  ```
- **Fix**: Use Flask's `g` object for per-request connection management with teardown cleanup.
  ```python
  from flask import g

  def get_db():
      if "db" not in g:
          g.db = sqlite3.connect(DATABASE)
          g.db.row_factory = sqlite3.Row
      return g.db

  @app.teardown_appcontext
  def close_db(exception):
      db = g.pop("db", None)
      if db is not None:
          db.close()
  ```

### 10. Timing-Based API Key Comparison
- **Location**: `app.py:69`
- **Problem**: Using `==` to compare the provided API key against the stored key is vulnerable to timing attacks, which can allow an attacker to determine the key one character at a time.
  ```python
  if provided_key == API_KEY:
  ```
- **Fix**: Use a constant-time comparison function.
  ```python
  import hmac

  if provided_key and hmac.compare_digest(provided_key, API_KEY):
  ```

## Suggestions

### 11. No Rate Limiting on Any Endpoint
- **Location**: `app.py` (all routes)
- **Problem**: The search and admin export endpoints are publicly accessible without rate limiting, making them susceptible to abuse and data scraping.
- **Fix**: Add rate limiting using `flask-limiter` or similar middleware.

### 12. No Test Coverage
- **Problem**: There are no tests for any of the endpoints. Given the number of security issues, tests would have helped surface problems like the password hash exposure and missing input validation.
- **Fix**: Add a `tests/` directory with tests for each endpoint covering happy path, error cases, and input validation.

## Next Steps
1. Remove the hardcoded API key and load it from the environment
2. Replace all string-concatenated SQL with parameterized queries (issues 2, 3, 4)
3. Hash passwords before storage and remove password hash from API responses (issues 5, 6)
4. Add input validation for the create user endpoint (issue 7)
5. Disable debug mode and bind to localhost (issue 8)
6. Fix database connection lifecycle (issue 9)
7. Use constant-time comparison for API key (issue 10)
8. Add tests and rate limiting (issues 11, 12)
