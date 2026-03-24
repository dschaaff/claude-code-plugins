# Code Review Summary
**Branch**: main
**Files Changed**: 1 file — `task-service.js` (68 lines added)
**Review Date**: 2026-03-24

## Overall Assessment

This is a new Node.js task management service module with four exported functions for querying, updating, deleting, and reporting on tasks. The code has several critical performance and security issues that must be addressed before merging: a classic N+1 query pattern, unawaited async operations that silently discard errors, missing input validation, and an XSS vulnerability in HTML generation.

## Strengths

- Parameterized SQL queries are used consistently (`$1`, `$2` placeholders), which prevents SQL injection in the database layer.
- Functions are small and focused — each handles a single responsibility.
- The `deleteCompletedTasks` function returns a meaningful result object with the count of deleted items.

## Critical Issues (Must Fix)

### 1. N+1 Query Problem in `getTasksWithAssignees`

- **Location**: `task-service.js:10-22`
- **Problem**: For every task returned by the initial query, three additional queries are executed (assignee, comments, labels). A project with 100 tasks triggers 301 database queries.
- **Impact**: Response time grows linearly with task count. This will cause severe latency and database load under real-world usage.
- **Fix**: Use JOINs or batch queries to fetch related data in constant query count.

```js
export async function getTasksWithAssignees(projectId) {
  const tasks = await db.query(
    `SELECT t.*, u.id AS assignee_user_id, u.name AS assignee_name, u.email AS assignee_email
     FROM tasks t
     LEFT JOIN users u ON u.id = t.assignee_id
     WHERE t.project_id = $1`,
    [projectId]
  );

  const taskIds = tasks.map((t) => t.id);
  if (taskIds.length === 0) return [];

  const comments = await db.query(
    `SELECT * FROM comments WHERE task_id = ANY($1) ORDER BY created_at DESC`,
    [taskIds]
  );
  const labels = await db.query(
    `SELECT l.*, tl.task_id FROM labels l
     JOIN task_labels tl ON l.id = tl.label_id
     WHERE tl.task_id = ANY($1)`,
    [taskIds]
  );

  const commentsByTask = Object.groupBy(comments, (c) => c.task_id);
  const labelsByTask = Object.groupBy(labels, (l) => l.task_id);

  return tasks.map((task) => ({
    ...task,
    assignee: { id: task.assignee_user_id, name: task.assignee_name, email: task.assignee_email },
    comments: commentsByTask[task.id] ?? [],
    labels: labelsByTask[task.id] ?? [],
  }));
}
```

### 2. Unawaited Promises in `updateTaskStatus` — Silent Failures and Race Condition

- **Location**: `task-service.js:34-46`
- **Problem**: All three operations (`db.query` UPDATE, `fetch` to Slack, `db.query` INSERT) are called without `await`. The function returns immediately, errors are silently swallowed, and the history INSERT reads `old_status` via a subquery *after* the UPDATE may or may not have completed — creating a race condition where the old status is already overwritten.
- **Impact**: The caller has no idea if the update succeeded. The task history will record incorrect `old_status` values. Slack notifications fail silently. Any database error is lost.
- **Fix**: Await operations in correct order, capture old status before updating, and handle errors.

```js
export async function updateTaskStatus(taskId, newStatus) {
  const [current] = await db.query(
    "SELECT status FROM tasks WHERE id = $1",
    [taskId]
  );
  if (!current) {
    throw new Error(`Task ${taskId} not found`);
  }

  await db.query("UPDATE tasks SET status = $1 WHERE id = $2", [newStatus, taskId]);

  await db.query(
    "INSERT INTO task_history (task_id, old_status, new_status) VALUES ($1, $2, $3)",
    [taskId, current.status, newStatus]
  );

  // Fire-and-forget is acceptable for notifications, but log failures
  fetch("https://hooks.slack.com/services/T00/B00/xxx", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text: `Task ${taskId} moved to ${newStatus}` }),
  }).catch((err) => console.error("Slack notification failed:", err));
}
```

### 3. Hardcoded Slack Webhook URL

- **Location**: `task-service.js:36`
- **Problem**: The Slack webhook URL `https://hooks.slack.com/services/T00/B00/xxx` is hardcoded in source code. While this appears to be a placeholder, the pattern invites committing a real secret later.
- **Impact**: If a real webhook URL is committed, anyone with repo access can send messages to the Slack channel or abuse the webhook.
- **Fix**: Read the URL from an environment variable or a configuration module.

```js
const slackWebhookUrl = process.env.SLACK_WEBHOOK_URL;
if (slackWebhookUrl) {
  fetch(slackWebhookUrl, { /* ... */ }).catch(/* ... */);
}
```

### 4. XSS Vulnerability in `buildTaskReport`

- **Location**: `task-service.js:62`
- **Problem**: `task.title`, `task.assignee`, and `task.status` are interpolated directly into HTML without escaping. If any field contains user-controlled data (which task titles certainly do), arbitrary HTML/JavaScript can be injected.
- **Impact**: Stored XSS — an attacker can inject malicious scripts by setting a task title to `<script>...</script>`, which executes when anyone views the report.
- **Fix**: Escape HTML entities before interpolation.

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

## Important Issues (Should Fix)

### 5. No Transaction for Multi-Table Deletion in `deleteCompletedTasks`

- **Location**: `task-service.js:48-58`
- **Problem**: Deleting related records across four tables (comments, task_labels, task_history, tasks) is done as individual queries without a transaction. If any query fails mid-loop, the database is left in an inconsistent state with orphaned or partially-deleted records.
- **Impact**: Data integrity loss on any failure during deletion.
- **Fix**: Wrap the entire operation in a database transaction. Also, this is another N+1 pattern — use `WHERE task_id = ANY($1)` to batch-delete.

```js
export async function deleteCompletedTasks(projectId) {
  const completed = await db.query(
    "SELECT id FROM tasks WHERE project_id = $1 AND status = 'done'",
    [projectId]
  );
  const ids = completed.map((t) => t.id);
  if (ids.length === 0) return { deleted: 0 };

  await db.transaction(async (tx) => {
    await tx.query("DELETE FROM comments WHERE task_id = ANY($1)", [ids]);
    await tx.query("DELETE FROM task_labels WHERE task_id = ANY($1)", [ids]);
    await tx.query("DELETE FROM task_history WHERE task_id = ANY($1)", [ids]);
    await tx.query("DELETE FROM tasks WHERE id = ANY($1)", [ids]);
  });
  return { deleted: ids.length };
}
```

### 6. No Input Validation on Any Function

- **Location**: All exported functions
- **Problem**: None of the functions validate their inputs. `projectId`, `taskId`, and `newStatus` are passed directly to queries without checking for `null`, `undefined`, or invalid types. `newStatus` is not validated against a set of allowed values.
- **Impact**: Invalid state transitions (e.g., setting status to an arbitrary string), confusing database errors, or unexpected behavior.
- **Fix**: Validate inputs at function entry. Define allowed statuses as a constant.

```js
const VALID_STATUSES = new Set(["todo", "in_progress", "review", "done"]);

export async function updateTaskStatus(taskId, newStatus) {
  if (!taskId) throw new Error("taskId is required");
  if (!VALID_STATUSES.has(newStatus)) {
    throw new Error(`Invalid status: ${newStatus}. Must be one of: ${[...VALID_STATUSES].join(", ")}`);
  }
  // ...
}
```

### 7. Missing `Content-Type` Header on Slack Webhook Request

- **Location**: `task-service.js:37-39`
- **Problem**: The `fetch` call sends JSON but does not set `Content-Type: application/json`. Slack may reject the payload or misinterpret it.
- **Impact**: Slack notifications may silently fail.
- **Fix**: Add the header: `headers: { "Content-Type": "application/json" }`.

## Suggestions (Nice to Have)

### 8. `SELECT *` Usage

- **Location**: `task-service.js:4`, `task-service.js:15`
- **Problem**: `SELECT *` fetches all columns, including any that may be added in the future. This can leak sensitive columns and causes unnecessary data transfer.
- **Fix**: Specify the columns you need explicitly.

### 9. No Pagination on `getTasksWithAssignees`

- **Location**: `task-service.js:3`
- **Problem**: Fetches all tasks for a project with no LIMIT. Projects with thousands of tasks will return enormous result sets.
- **Fix**: Add `limit` and `offset` parameters for pagination.

### 10. No Tests

- **Location**: Entire module
- **Problem**: There are no test files in the repository. A module with database operations, external API calls, and HTML generation needs tests to catch regressions.
- **Fix**: Add tests covering at minimum the happy path for each function, error handling in `updateTaskStatus`, and XSS prevention in `buildTaskReport`.

## Quality Metrics

- **Test Coverage**: None — no test files exist in the repository
- **Security**: Fail — hardcoded webhook URL, XSS in HTML output, no input validation
- **Performance**: Fail — N+1 queries in two functions, no pagination
- **Documentation**: Needs improvement — no JSDoc or inline comments explaining business logic

## Review Checklist

- [ ] All tests pass (no tests exist)
- [ ] No security vulnerabilities (XSS in `buildTaskReport`, hardcoded webhook)
- [ ] Error handling is comprehensive (unawaited promises in `updateTaskStatus`, no input validation)
- [ ] Documentation updated (no documentation present)
- [ ] Breaking changes documented (N/A — new file)
- [ ] Performance acceptable (N+1 queries, no pagination)
- [ ] Code follows project conventions (cannot assess — single file repo)
- [ ] No TODO/FIXME left unaddressed (none found)

## Next Steps

1. **Fix unawaited promises** in `updateTaskStatus` — this causes silent data loss and race conditions (Critical #2).
2. **Fix the N+1 query** in `getTasksWithAssignees` by using JOINs or batch queries (Critical #1).
3. **Escape HTML output** in `buildTaskReport` to prevent XSS (Critical #4).
4. **Move the Slack webhook URL** to an environment variable (Critical #3).
5. **Wrap `deleteCompletedTasks`** in a transaction and batch the deletes (Important #5).
6. **Add input validation** to all exported functions (Important #6).
7. **Add tests** for all four functions.
