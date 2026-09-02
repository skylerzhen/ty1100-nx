#!/usr/bin/env python3
"""Generate password hash for auth.users.json"""

import hashlib
import sys

if len(sys.argv) < 3:
    print("Usage: python gen_auth_hash.py <salt> <password>")
    sys.exit(1)

salt, password = sys.argv[1], sys.argv[2]
print(hashlib.sha256(f"{salt}:{password}".encode()).hexdigest())
