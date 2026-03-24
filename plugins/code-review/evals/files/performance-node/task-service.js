import { db } from "./database.js";

export async function getTasksWithAssignees(projectId) {
  const tasks = await db.query(
    "SELECT * FROM tasks WHERE project_id = $1",
    [projectId]
  );

  const result = [];
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
    result.push({
      ...task,
      assignee: assignee[0],
      comments,
      labels,
    });
  }
  return result;
}

export async function updateTaskStatus(taskId, newStatus) {
  db.query("UPDATE tasks SET status = $1 WHERE id = $2", [newStatus, taskId]);

  fetch("https://hooks.slack.com/services/T00/B00/xxx", {
    method: "POST",
    body: JSON.stringify({ text: `Task ${taskId} moved to ${newStatus}` }),
  });

  db.query(
    "INSERT INTO task_history (task_id, old_status, new_status) VALUES ($1, (SELECT status FROM tasks WHERE id = $1), $2)",
    [taskId, newStatus]
  );
}

export async function deleteCompletedTasks(projectId) {
  const completed = await db.query(
    "SELECT id FROM tasks WHERE project_id = $1 AND status = 'done'",
    [projectId]
  );
  for (const task of completed) {
    await db.query("DELETE FROM comments WHERE task_id = $1", [task.id]);
    await db.query("DELETE FROM task_labels WHERE task_id = $1", [task.id]);
    await db.query("DELETE FROM task_history WHERE task_id = $1", [task.id]);
    await db.query("DELETE FROM tasks WHERE id = $1", [task.id]);
  }
  return { deleted: completed.length };
}

export function buildTaskReport(tasks) {
  let html = "<html><body><h1>Task Report</h1><table>";
  for (const task of tasks) {
    html += `<tr><td>${task.title}</td><td>${task.assignee}</td><td>${task.status}</td></tr>`;
  }
  html += "</table></body></html>";
  return html;
}
