# Google Cloud Authentication Setup Guide

This guide explains how to set up the necessary Google Cloud credentials to run the Email & Calendar integration.

## Prerequisites

1.  A Google Cloud Project.
2.  Python 3 installed.
3.  Dependencies installed:
    ```bash
    pip3 install -r scripts/auth/requirements.txt
    ```

## Step 1: Create OAuth Credentials

1.  Go to the [Google Cloud Console Credentials Page](https://console.cloud.google.com/apis/credentials).
2.  Select your project (or create a new one).
3.  Click **Create Credentials** -> **OAuth client ID**.
4.  **Application type**: Select **Desktop app**.
5.  **Name**: Enter a name (e.g., "Workstation Auth").
6.  Click **Create**.
7.  Download the JSON file (Look for the "Download JSON" button).
8.  **Rename** the downloaded file to `credentials.json`.
9.  **Move** the file to the `secrets/` directory in this project:
    ```bash
    mv ~/Downloads/client_secret_*.json secrets/credentials.json
    ```

## Step 2: Enable APIs

Ensure the following APIs are enabled for your project:

*   [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com)
*   [Google Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com)

## Step 3: Generate the Token

Run the authentication flow script. This will open a browser window for you to log in and authorize the application.

```bash
# If using the project's venv
./.venv/bin/python scripts/auth/google_auth_flow.py

# Or if running directly
python3 scripts/auth/google_auth_flow.py
```

Upon success, a `secrets/token.json` file will be created.

## Step 4: Validate the Token

Verify that the token was created correctly and has the required fields.

```bash
# If using the project's venv (pointing to the local token path)
GOOGLE_TOKEN_FILE=secrets/token.json ./.venv/bin/python scripts/auth/validate_token.py
```

## Troubleshooting

*   **`credentials.json` not found**: Ensure you renamed the downloaded JSON file and placed it in `secrets/`.
*   **ModuleNotFoundError**: Ensure you installed the requirements (`pip install -r scripts/auth/requirements.txt`).
*   **Token invalid**: Delete `secrets/token.json` and run the auth flow again.
