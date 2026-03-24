# Code Review: main
1 file changed | 2026-03-24

**Pre-review checks**: No test infrastructure found (no `package.json`, test framework, or linter configs in the repository).

## Strengths
- All SQL queries use parameterized queries (`$1`, `$2`), which prevents SQL injection.
- Clear function naming that communicates intent (`getTasksWithAssignees`, `deleteCompletedTasks`).

## Critical Issues

### N+1 query problem in `getTasksWithAssignees`
- **Location**: `task-service.js:10-22`
- **Problem**: For every task returned by the initial query, three additional queries are executed inside the loop (assignee, comments, labels). For a project with 100 tasks, this fires 301 queries instead of 4.
  ```js
  for (const task of tasks) {
    const assignee = await db.query(
      "SELECT id, name, email FROM users WHERE id = $1",
      [task.assignee_id]
    );
    const comments = await db.query(
      "SELECT * FROM comments WHERE task_id = $1 ORDER BY created_at DESC",
      [task.id]
    );
    const labels = await db.query(
      "SELECT l.* FROM labels l JOIN task_labels tl ON l.id = tl.label_id WHERE tl.task_id = $1",
      [task.id]
    );
  }
  ```
- **Fix**: Use JOINs or batch the queries using `WHERE ... IN (...)`:
  ```js
  export async function getTasksWithAssignees(projectId) {
    const tasks = await db.query(
      "SELECT * FROM tasks WHERE project_id = $1",
      [projectId]
    );

    if (tasks.length === 0) return [];

    const taskIds = tasks.map((t) => t.id);
    const assigneeIds = tasks.map((t) => t.assignee_id).filter(Boolean);

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
        "SELECT l.*, tl.task_id FROM labels l JOIN task_labels tl ON l.id = tl.label_id WHERE tl.task_id = ANY($1)",
        [taskIds]
      ),
    ]);

    const assigneeMap = new Map(assignees.map((a) => [a.id, a]));
    const commentMap = Map.groupBy(comments, (c) => c.task_id);
    const labelMap = Map.groupBy(labels, (l) => l.task_id);

    return tasks.map((task) => ({
      ...task,
      assignee: assigneeMap.get(task.assignee_id),
      comments: commentMap.get(task.id) ?? [],
      labels: labelMap.get(task.id) ?? [],
    }));
  }
  ```

### Missing `await` on all async operations in `updateTaskStatus`
- **Location**: `task-service.js:34-44`
- **Problem**: Neither the `db.query` calls nor the `fetch` call are awaited. This means errors are silently swallowed (unhandled promise rejections), the function returns before any work completes, and the history insert races with the status update -- it reads the old status via a subquery that may execute before or after the UPDATE.
  ```js
  db.query("UPDATE tasks SET status = $1 WHERE id = $2", [newStatus, taskId]);

  fetch("https://hooks.slack.com/services/T00/B00/xxx", {
    method: "POST",
    body: JSON.stringify({ text: `Task ${taskId} moved to ${newStatus}` }),
  });

  db.query(
    "INSERT INTO task_history ...",
    [taskId, newStatus]
  );
  ```
- **Fix**: Await database operations and handle the webhook call properly. Capture old status before updating to avoid the race condition:
  ```js
  export async function updateTaskStatus(taskId, newStatus) {
    const [current] = await db.query(
      "SELECT status FROM tasks WHERE id = $1",
      [taskId]
    );
    if (!current) {
      throw new Error(`Task ${taskId} not found`);
    }

    await db.query(
      "UPDATE tasks SET status = $1 WHERE id = $2",
      [newStatus, taskId]
    );

    await db.query(
      "INSERT INTO task_history (task_id, old_status, new_status) VALUES ($1, $2, $3)",
      [taskId, current.status, newStatus]
    );

    // Fire-and-forget is acceptable for webhooks, but log failures
    fetch("https://hooks.slack.com/services/T00/B00/xxx", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: `Task ${taskId} moved to ${newStatus}` }),
    }).catch((err) => console.error("Slack notification failed:", err));
  }
  ```

### XSS vulnerability in `buildTaskReport`
- **Location**: `task-service.js:60-66`
- **Problem**: Task title, assignee, and status are interpolated directly into HTML without escaping. If any field contains `<script>` tags or HTML entities, they will be rendered as live markup.
  ```js
  html += `<tr><td>${task.title}</td><td>${task.assignee}</td><td>${task.status}</td></tr>`;
  ```
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

### No transaction for multi-table delete in `deleteCompletedTasks`
- **Location**: `task-service.js:48-57`
- **Problem**: Deleting across four tables (comments, task_labels, task_history, tasks) without a transaction means a failure partway through leaves orphaned or inconsistent data. Each iteration also runs four sequential queries per task -- another N+1 pattern.
  ```js
  for (const task of completed) {
    await db.query("DELETE FROM comments WHERE task_id = $1", [task.id]);
    await db.query("DELETE FROM task_labels WHERE task_id = $1", [task.id]);
    await db.query("DELETE FROM task_history WHERE task_id = $1", [task.id]);
    await db.query("DELETE FROM tasks WHERE id = $1", [task.id]);
  }
  ```
- **Fix**: Wrap in a transaction and batch by task IDs:
  ```js
  export async function deleteCompletedTasks(projectId) {
    const completed = await db.query(
      "SELECT id FROM tasks WHERE project_id = $1 AND status = 'done'",
      [projectId]
    );
    if (completed.length === 0) return { deleted: 0 };

    const ids = completed.map((t) => t.id);

    await db.query("BEGIN");
    try {
      await db.query("DELETE FROM comments WHERE task_id = ANY($1)", [ids]);
      await db.query("DELETE FROM task_labels WHERE task_id = ANY($1)", [ids]);
      await db.query("DELETE FROM task_history WHERE task_id = ANY($1)", [ids]);
      await db.query("DELETE FROM tasks WHERE id = ANY($1)", [ids]);
      await db.query("COMMIT");
    } catch (err) {
      await db.query("ROLLBACK");
      throw err;
    }

    return { deleted: completed.length };
  }
  ```

### Hardcoded Slack webhook URL
- **Location**: `task-service.js:36`
- **Problem**: The Slack webhook URL is hardcoded in source code. Webhook URLs are secrets that grant posting access to a Slack channel.
  ```js
  fetch("https://hooks.slack.com/services/T00/B00/xxx", {
  ```
- **Fix**: Read from an environment variable:
  ```js
  const url = process.env.SLACK_WEBHOOK_URL;
  if (url) {
    fetch(url, { ... }).catch(...);
  }
  ```

### No input validation in `updateTaskStatus`
- **Location**: `task-service.js:33`
- **Problem**: `newStatus` is accepted without validation. Any arbitrary string will be written to the database. There is also no check that `taskId` corresponds to an existing task.
- **Fix**: Validate against allowed statuses:
  ```js
  const VALID_STATUSES = new Set(["todo", "in_progress", "in_review", "done"]);

  export async function updateTaskStatus(taskId, newStatus) {
    if (!VALID_STATUSES.has(newStatus)) {
      throw new Error(`Invalid status: ${newStatus}`);
    }
    // ... rest of function
  }
  ```

## Suggestions

### No tests
- **Location**: project-wide
- **Problem**: There are no test files and no test infrastructure. Every function here has non-trivial logic (batching, transaction safety, HTML escaping) that should be verified.
- **Fix**: Add a `package.json` with a test framework (e.g., vitest) and write tests covering at minimum: the N+1 fix returning correct shape, `updateTaskStatus` error paths, `deleteCompletedTasks` rollback on failure, and `buildTaskReport` HTML escaping.

### `SELECT *` usage
- **Location**: `task-service.js:4`, `task-service.js:15`
- **Problem**: `SELECT *` pulls all columns, which couples the code to the table schema and transfers unnecessary data. If a column is added to `tasks` or `comments`, callers silently receive it.
- **Fix**: Specify the columns you need explicitly.

## Next Steps
1. Add `await` to all async operations in `updateTaskStatus` and fix the race condition on old status capture.
2. Replace the N+1 loops in `getTasksWithAssignees` and `deleteCompletedTasks` with batched queries.
3. Wrap `deleteCompletedTasks` in a transaction.
4. Escape HTML output in `buildTaskReport`.
5. Move the Slack webhook URL to an environment variable.
6. Add input validation to `updateTaskStatus`.
7. Set up a test framework and add tests.
