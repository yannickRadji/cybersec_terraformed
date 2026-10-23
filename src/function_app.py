import json
import logging
import os

import azure.functions as func
import pyodbc

from sanitize import validate_name

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)
logger = logging.getLogger("namecounter")


def json_response(body: dict, status: int) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(body), status_code=status, mimetype="application/json")


@app.route(route="http_trigger", methods=["POST"])
def http_trigger(req: func.HttpRequest) -> func.HttpResponse:
    try:
        name = validate_name(req.get_json().get("name"))
    except ValueError:
        logger.warning("Rejected request: body is not valid JSON")
        return json_response({"error": "Body must be valid JSON."}, 400)

    if not name:
        logger.warning("Rejected request: field 'name' missing")
        return json_response({"error": "Field 'name' is required."}, 400)

    conn_str = os.environ.get("SQL_CONNECTION_STRING")
    if not conn_str:
        logger.error("SQL_CONNECTION_STRING is not configured")
        return json_response({"error": "Internal error."}, 500)

    try:
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT count FROM dbo.Names WHERE name = ?", (name,))
            row = cursor.fetchone()
            if row:
                count = row[0] + 1
                cursor.execute("UPDATE dbo.Names SET count = ? WHERE name = ?", (count, name))
            else:
                count = 1
                cursor.execute("INSERT INTO dbo.Names (name, count) VALUES (?, ?)", (name, count))
            conn.commit()
    except pyodbc.Error:
        # Full stack trace and driver message go to Application Insights, never to the caller.
        logger.exception("Database error while updating the counter")
        return json_response({"error": "Internal error."}, 500)

    logger.info("Counter updated, count=%s", count)
    return func.HttpResponse(f"hello {name} this is your {count}th call")