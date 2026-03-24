# Code Review: main
1 file changed | 2026-03-24

**Pre-review checks**: No test infrastructure found (no package.json, no test files, no linter configs). No project convention files present.

## Strengths
- Queries use parameterized placeholders (`$1`, `$2`), avoiding SQL injection in most paths.
- `getTasksWithAssignees` is well-structured, returning a cleanly composed object per task.

## Critical Issues

### N+1 Query Problem in `getTasksWithAssignees`
- **Location**: `task-service.js:10-22`
- **Problem**: For every task, three additional queries run sequentially (assignees, comments, labels). A project with 100 tasks fires 301 queries. This will cause severe latency and database load.
- **Fix**: Use JOINs or batch queries with `WHERE ... IN (...)`:
```js
const taskIds = tasks.map(t => t.id);
const assigneeIds = tasks.map(t => t.assignee_id);

const [assignees, comments, labels] = await Promise.all([
  db.query(
    "SELECT id, name, email FROM users WHERE id = ANY($1)",
    [assigneeIds]
  ),
  db.query(
    "SELECT * FROM comments WHERE task_id = ANY($1) ORDER BY created_at DESC",
    [taskIds]
  ),
  db.query(
    `SELECT l.*, tl.task_id FROM labels l
     JOIN task_labels tl ON l.id = tl.label_id
     WHERE tl.task_id = ANY($1)`,
    [taskIds]
  ),
]);
```
Then index results by id/task_id into Maps and assemble in a single loop.

### Hardcoded Slack Webhook URL
- **Location**: `task-service.js:36`
- **Problem**: `https://hooks.slack.com/services/T00/B00/xxx` is a hardcoded secret. If this is committed with a real token, anyone with repo access can post to the Slack channel. Even as a placeholder, it sets a pattern that leads to real credentials being committed later.
- **Fix**: Read from an environment variable:
```js
const webhookUrl = process.env.SLACK_WEBHOOK_URL;
if (!webhookUrl) {
  throw new Error("SLACK_WEBHOOK_URL environment variable is not set");
}
```

### Missing `await` on Promises in `updateTaskStatus`
- **Location**: `task-service.js:34-44`
- **Problem**: Neither `db.query` call nor the `fetch` call is awaited. The function returns before any of these operations complete. If any fail, the errors are silently swallowed as unhandled promise rejections. The history INSERT runs concurrently with the UPDATE, so the subquery `(SELECT status FROM tasks WHERE id = $1)` may read either the old or new status depending on timing -- a race condition.
- **Fix**: Await each operation in order:
```js
export async function updateTaskStatus(taskId, newStatus) {
  const oldStatus = await db.query(
    "SELECT status FROM tasks WHERE id = $1", [taskId]
  );
  await db.query(
    "UPDATE tasks SET status = $1 WHERE id = $2", [newStatus, taskId]
  );
  await db.query(
    "INSERT INTO task_history (task_id, old_status, new_status) VALUES ($1, $2, $3)",
    [taskId, oldStatus[0]?.status, newStatus]
  );
  await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text: `Task ${taskId} moved to ${newStatus}` }),
  });
}
```

### XSS Vulnerability in `buildTaskReport`
- **Location**: `task-service.js:60-66`
- **Problem**: `task.title`, `task.assignee`, and `task.status` are interpolated directly into HTML with no escaping. If any field contains `<script>alert(1)</script>`, it executes in the browser.
- **Fix**: Escape HTML entities before interpolation:
```js
function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function buildTaskReport(tasks) {
  let html = "<html><body><h1>Task Report</h1><table>";
  for (const task of tasks) {
    html += `<tr><td>${escapeHtml(task.title)}</td><td>${escapeHtml(task.assignee)}</td><td>${escapeHtml(task.status)}</td></tr>`;
  }
  html += "</table></body></html>";
  return html;
}
```

## Important Issues

### No Transaction for Multi-Table Deletion
- **Location**: `task-service.js:49-57`
- **Problem**: `deleteCompletedTasks` deletes from four tables in sequence without a transaction. If the process crashes after deleting comments but before deleting tasks, the data is left in an inconsistent state (orphaned label/history references, or tasks missing their comments).
- **Fix**: Wrap in a transaction, or use `ON DELETE CASCADE` foreign keys so a single `DELETE FROM tasks` handles related rows:
```js
export async function deleteCompletedTasks(projectId) {
  const completed = await db.query(
    "SELECT id FROM tasks WHERE project_id = $1 AND status = 'done'",
    [projectId]
  );
  const taskIds = completed.map(t => t.id);
  if (taskIds.length === 0) return { deleted: 0 };

  await db.query("BEGIN");
  try {
    await db.query("DELETE FROM comments WHERE task_id = ANY($1)", [taskIds]);
    await db.query("DELETE FROM task_labels WHERE task_id = ANY($1)", [taskIds]);
    await db.query("DELETE FROM task_history WHERE task_id = ANY($1)", [taskIds]);
    await db.query("DELETE FROM tasks WHERE id = ANY($1)", [taskIds]);
    await db.query("COMMIT");
  } catch (err) {
    await db.query("ROLLBACK");
    throw err;
  }
  return { deleted: taskIds.length };
}
```
This also eliminates the N+1 deletion loop.

### No Input Validation
- **Location**: `task-service.js:33`, `task-service.js:48`, `task-service.js:3`
- **Problem**: None of the exported functions validate their inputs. `updateTaskStatus` accepts any string as `newStatus` -- there is no check against valid statuses. `taskId` and `projectId` are passed straight to queries without type or presence checks.
- **Fix**: Validate at function entry. For example:
```js
const VALID_STATUSES = new Set(["todo", "in_progress", "done"]);

export async function updateTaskStatus(taskId, newStatus) {
  if (!taskId || typeof taskId !== "number") {
    throw new Error(`Invalid taskId: ${taskId}`);
  }
  if (!VALID_STATUSES.has(newStatus)) {
    throw new Error(`Invalid status: ${newStatus}`);
  }
  // ...
}
```

### No Error Handling on External `fetch` Call
- **Location**: `task-service.js:36-39`
- **Problem**: The Slack webhook `fetch` has no error handling. A network failure or non-2xx response would throw (once awaited) and abort the entire status update, even though the notification is a side effect, not the primary operation.
- **Fix**: Catch and log fetch failures so they don't block the core operation:
```js
try {
  await fetch(webhookUrl, { /* ... */ });
} catch (err) {
  console.error("Slack notification failed:", err.message);
}
```

## Suggestions

### Missing Test Coverage
- **Location**: project-wide
- **Problem**: No tests exist for any function. These functions have multiple failure modes (empty results, concurrent modifications, network failures) that are easy to miss.
- **Fix**: Add a test file with at least happy-path and error-path tests for each exported function. Set up `package.json` with a test runner (e.g., `vitest`).

### `deleteCompletedTasks` Could Use Soft Deletes
- **Location**: `task-service.js:48-58`
- **Problem**: Hard-deleting tasks and all related data is irreversible. In a task management system, users frequently want to recover deleted items.
- **Fix**: Consider a `deleted_at` timestamp column instead of `DELETE` statements.

## Next Steps
1. Add `await` to all async calls in `updateTaskStatus` and fix the race condition on history insertion.
2. Move the Slack webhook URL to an environment variable.
3. Escape HTML output in `buildTaskReport` to prevent XSS.
4. Replace the N+1 query loop with batch queries in `getTasksWithAssignees`.
5. Wrap `deleteCompletedTasks` in a transaction.
6. Add input validation to all exported functions.
7. Add error handling around the Slack notification.
8. Set up package.json, a test runner, and initial tests.
