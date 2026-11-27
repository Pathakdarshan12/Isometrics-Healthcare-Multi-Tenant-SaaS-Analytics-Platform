"""Runtime configuration, read from environment variables (and a root .env file)."""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from functools import lru_cache

from dotenv import load_dotenv

IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_$]*$')
SHA256_HEX = re.compile(r'^[0-9a-f]{64}$')


class ConfigError(ValueError):
    """Raised when the API is misconfigured; the app refuses to start."""


@dataclass(frozen=True)
class ApiClient:
    """A caller identified by an API key, bound to exactly one Snowflake role."""
    name: str
    role: str


@dataclass(frozen=True)
class Settings:
    snowflake_account: str | None
    snowflake_user: str | None
    snowflake_password: str | None
    snowflake_warehouse: str | None
    database: str
    marts_schema: str
    # sha256(api_key) hex digest -> client
    api_clients: dict[str, ApiClient] = field(default_factory=dict)
    pool_size: int = 4
    max_page_size: int = 1000


def _identifier(value: str, name: str) -> str:
    if not IDENTIFIER.match(value):
        raise ConfigError(f'{name} must be a plain Snowflake identifier, got {value!r}')
    return value.upper()


def parse_api_clients(raw: str | None) -> dict[str, ApiClient]:
    """Parse ISOMETRICS_API_KEYS.

    Format (JSON), keyed by the SHA-256 hex digest of the API key so plaintext
    keys are never stored in config:
        {"<sha256-hex>": {"name": "hosp-0001-dashboard", "role": "HOSPITAL_HOSP_0001_ANALYST"}}

    Generate an entry with:  python -m api.keys <client-name> <SNOWFLAKE_ROLE>
    """
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ConfigError(f'ISOMETRICS_API_KEYS is not valid JSON: {exc}') from exc
    if not isinstance(data, dict):
        raise ConfigError('ISOMETRICS_API_KEYS must be a JSON object')

    clients = {}
    for key_hash, entry in data.items():
        if not SHA256_HEX.match(key_hash):
            raise ConfigError('ISOMETRICS_API_KEYS keys must be lowercase SHA-256 hex digests of the API keys')
        if not isinstance(entry, dict) or not entry.get('name') or not entry.get('role'):
            raise ConfigError(f'API key entry {key_hash[:8]}... needs "name" and "role"')
        clients[key_hash] = ApiClient(name=str(entry['name']), role=_identifier(str(entry['role']), 'role'))
    return clients


def load_settings() -> Settings:
    load_dotenv()
    return Settings(
        snowflake_account=os.getenv('SNOWFLAKE_ACCOUNT'),
        snowflake_user=os.getenv('SNOWFLAKE_USER'),
        snowflake_password=os.getenv('SNOWFLAKE_PASSWORD'),
        snowflake_warehouse=os.getenv('SNOWFLAKE_WAREHOUSE'),
        database=_identifier(os.getenv('SNOWFLAKE_DATABASE', 'ISOMETRICS_DEV'), 'SNOWFLAKE_DATABASE'),
        marts_schema=_identifier(os.getenv('ISOMETRICS_MARTS_SCHEMA', 'DBT_DEV_MARTS'), 'ISOMETRICS_MARTS_SCHEMA'),
        api_clients=parse_api_clients(os.getenv('ISOMETRICS_API_KEYS')),
        pool_size=int(os.getenv('ISOMETRICS_API_POOL_SIZE', '4')),
        max_page_size=int(os.getenv('ISOMETRICS_API_MAX_PAGE_SIZE', '1000')),
    )


@lru_cache
def get_settings() -> Settings:
    return load_settings()
