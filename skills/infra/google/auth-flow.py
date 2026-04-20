#!/usr/bin/env python3
"""Run Google OAuth2 consent flow and save refresh token.

Opens a browser for consent, runs a local callback server.

Usage:
    python3 auth-flow.py \
        --credentials .secrets/google/google-credentials.json \
        --token .secrets/google/google-token.json \
        --scopes https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/gmail.send
"""

import argparse
import json
import sys

try:
    from google_auth_oauthlib.flow import InstalledAppFlow
except ImportError:
    print("Missing dependencies. Install with:")
    print("  pip install google-auth google-auth-oauthlib google-api-python-client")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--scopes", required=True, help="Comma-separated scope URLs")
    args = parser.parse_args()

    scopes = [s.strip() for s in args.scopes.split(",")]

    flow = InstalledAppFlow.from_client_secrets_file(args.credentials, scopes)
    creds = flow.run_local_server(port=8085, open_browser=False)

    print(f"\nOpen this URL if a browser didn't open automatically:")
    print(f"  http://localhost:8085")

    token_data = {
        "token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri": creds.token_uri,
        "client_id": creds.client_id,
        "client_secret": creds.client_secret,
        "scopes": list(creds.scopes) if creds.scopes else scopes,
    }

    with open(args.token, "w") as f:
        json.dump(token_data, f, indent=2)

    print(f"Token saved to {args.token}")


if __name__ == "__main__":
    main()
