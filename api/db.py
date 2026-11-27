"""Snowflake access.

Every query runs under the *caller's* Snowflake role (USE ROLE per checkout),
so the hospital_isolation_policy row access policy decides which rows come back.
The API never filters tenants itself; a bug here cannot widen access beyond
what the role is allowed to see.

Secondary roles are disabled on every connection so privileges and policy
evaluation come from the caller's role alone.
"""
from __future__ import annotations

import logging
import queue
from contextlib import contextmanager
from typing import Any, Iterator, Protocol

from api.config import IDENTIFIER, Settings
from utils.snowflake_auth import auth_params

log = logging.getLogger(__name__)


class QueryError(RuntimeError):
    """Database failure; details are logged, never returned to API callers."""


class Repository(Protocol):
    def query(self, role: str, sql: str, params: dict[str, Any]) -> list[dict[str, Any]]: ...

    def close(self) -> None: ...


class SnowflakeRepository:
    def __init__(self, settings: Settings):
        import snowflake.connector  # imported lazily so tests don't need a driver connection

        self._connector = snowflake.connector
        self._settings = settings
        self._pool: queue.Queue = queue.Queue(maxsize=settings.pool_size)

    def _connect(self):
        s = self._settings
        conn = self._connector.connect(
            account=s.snowflake_account,
            user=s.snowflake_user,
            **auth_params(password=s.snowflake_password, private_key_path=s.snowflake_private_key_path),
            warehouse=s.snowflake_warehouse,
            database=s.database,
            schema=s.marts_schema,
            session_parameters={'QUERY_TAG': 'isometrics_api'},
            client_session_keep_alive=False,
        )
        conn.cursor().execute('USE SECONDARY ROLES NONE')
        return conn

    @contextmanager
    def _connection(self) -> Iterator[Any]:
        try:
            conn = self._pool.get_nowait()
        except queue.Empty:
            conn = self._connect()
        healthy = True
        try:
            yield conn
        except Exception:
            healthy = False
            raise
        finally:
            if healthy and not conn.is_closed():
                try:
                    self._pool.put_nowait(conn)
                    conn = None
                except queue.Full:
                    pass
            if conn is not None:
                conn.close()

    def query(self, role: str, sql: str, params: dict[str, Any]) -> list[dict[str, Any]]:
        if not IDENTIFIER.match(role):
            raise QueryError('invalid role')
        try:
            with self._connection() as conn:
                cur = conn.cursor(self._connector.DictCursor)
                try:
                    cur.execute('USE ROLE IDENTIFIER(%(role)s)', {'role': role})
                    cur.execute(sql, params)
                    return [{k.lower(): v for k, v in row.items()} for row in cur.fetchall()]
                finally:
                    cur.close()
        except self._connector.errors.Error as exc:
            log.exception('Snowflake query failed (role=%s)', role)
            raise QueryError('query failed') from exc

    def close(self) -> None:
        while True:
            try:
                self._pool.get_nowait().close()
            except queue.Empty:
                return
