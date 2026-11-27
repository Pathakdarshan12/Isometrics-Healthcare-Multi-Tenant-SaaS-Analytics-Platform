"""Generate an API key and the ISOMETRICS_API_KEYS entry for it.

    python -m api.keys hosp-0001-dashboard HOSPITAL_HOSP_0001_ANALYST

Prints the plaintext key once (give it to the client) and the JSON entry to add
to ISOMETRICS_API_KEYS (only the SHA-256 digest is stored).
"""
import hashlib
import json
import secrets
import sys

from api.config import ConfigError, _identifier


def hash_key(api_key: str) -> str:
    return hashlib.sha256(api_key.encode('utf-8')).hexdigest()


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    name, role = argv
    try:
        role = _identifier(role, 'role')
    except ConfigError as exc:
        print(exc, file=sys.stderr)
        return 2

    api_key = 'imk_' + secrets.token_urlsafe(32)
    print(f'API key (shown once): {api_key}')
    print('ISOMETRICS_API_KEYS entry:')
    print(json.dumps({hash_key(api_key): {'name': name, 'role': role}}))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
