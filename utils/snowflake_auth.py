"""Snowflake authentication parameters shared by every Python client.

Service users (DBT_USER, DBT_PROD_USER) authenticate with an RSA key pair:
Snowflake no longer allows single-factor password sign-in for newly created
users (they must be TYPE = SERVICE, which has no password). Password auth is
kept as a fallback for accounts where it still works (e.g. trial accounts).

Environment:
    SNOWFLAKE_PRIVATE_KEY_PATH        path to the PKCS#8 private key (.p8)
    SNOWFLAKE_PRIVATE_KEY_PASSPHRASE  only if the key is encrypted
    SNOWFLAKE_PASSWORD                fallback when no key path is set
"""
import os
from typing import Optional


def auth_params(
        password: Optional[str] = None,
        private_key_path: Optional[str] = None,
        private_key_passphrase: Optional[str] = None,
) -> dict:
    """Keyword arguments for snowflake.connector.connect(): key pair if configured, else password."""
    key_path = private_key_path or os.getenv('SNOWFLAKE_PRIVATE_KEY_PATH')
    if key_path:
        params = {'private_key_file': os.path.expanduser(key_path)}
        passphrase = private_key_passphrase or os.getenv('SNOWFLAKE_PRIVATE_KEY_PASSPHRASE')
        if passphrase:
            params['private_key_file_pwd'] = passphrase
        return params
    return {'password': password or os.getenv('SNOWFLAKE_PASSWORD')}
