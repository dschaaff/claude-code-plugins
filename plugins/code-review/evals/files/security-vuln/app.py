"""User management API."""

import sqlite3
from flask import Flask, request, jsonify

app = Flask(__name__)

API_KEY = "sk-proj-a8f3k2m1n4p5q6r7s8t9u0v1w2x3y4z5"
DATABASE = "users.db"


def get_db():
    conn = sqlite3.connect(DATABASE)
    return conn


@app.route("/users/search")
def search_users():
    query = request.args.get("q", "")
    db = get_db()
    cursor = db.execute(
        "SELECT id, name, email FROM users WHERE name LIKE '%" + query + "%'"
    )
    results = [
        {"id": row[0], "name": row[1], "email": row[2]}
        for row in cursor.fetchall()
    ]
    return jsonify(results)


@app.route("/users/<int:user_id>")
def get_user(user_id):
    db = get_db()
    cursor = db.execute(
        f"SELECT id, name, email, password_hash FROM users WHERE id = {user_id}"
    )
    row = cursor.fetchone()
    if row:
        return jsonify(
            {
                "id": row[0],
                "name": row[1],
                "email": row[2],
                "password_hash": row[3],
            }
        )
    return jsonify({"error": "not found"}), 404


@app.route("/users", methods=["POST"])
def create_user():
    data = request.get_json()
    db = get_db()
    db.execute(
        "INSERT INTO users (name, email, password_hash) VALUES ('"
        + data["name"]
        + "', '"
        + data["email"]
        + "', '"
        + data["password"]
        + "')"
    )
    db.commit()
    return jsonify({"status": "created"}), 201


@app.route("/admin/export")
def export_data():
    provided_key = request.headers.get("X-API-Key")
    if provided_key == API_KEY:
        db = get_db()
        cursor = db.execute("SELECT * FROM users")
        rows = cursor.fetchall()
        return jsonify(rows)
    return jsonify({"error": "unauthorized"}), 401


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0")
