#!/usr/bin/env python3
"""Send a test email via Gmail API using host credentials.

Usage: python3 test-gmail.py <recipient-email>

Reads credentials from /etc/hetzbot/google/.
"""

import base64
import json
import sys
from email.mime.text import MIMEText

from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build

CREDS_DIR = "/etc/hetzbot/google"


def main():
    if len(sys.argv) != 2:
        print("usage: test-gmail.py <recipient-email>", file=sys.stderr)
        sys.exit(1)

    recipient = sys.argv[1]

    with open(f"{CREDS_DIR}/google-token.json") as f:
        token_data = json.load(f)

    creds = Credentials(
        token=token_data.get("token"),
        refresh_token=token_data["refresh_token"],
        token_uri=token_data["token_uri"],
        client_id=token_data["client_id"],
        client_secret=token_data["client_secret"],
        scopes=token_data.get("scopes", []),
    )

    if not creds.valid:
        creds.refresh(Request())
        token_data["token"] = creds.token
        with open(f"{CREDS_DIR}/google-token.json", "w") as f:
            json.dump(token_data, f, indent=2)

    service = build("gmail", "v1", credentials=creds)

    profile = service.users().getProfile(userId="me").execute()
    sender = profile["emailAddress"]
    print(f"Authenticated as: {sender}")

    msg = MIMEText(
        "This is a test email from hetzbot.\n\n"
        "Google API credentials are working on this host."
    )
    msg["to"] = recipient
    msg["from"] = sender
    msg["subject"] = "hetzbot test - Google API working"

    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    result = service.users().messages().send(userId="me", body={"raw": raw}).execute()
    print(f"Sent to {recipient} — Message ID: {result['id']}")


if __name__ == "__main__":
    main()
