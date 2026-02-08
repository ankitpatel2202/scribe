# Salesforce OAuth (Connected App) Setup

To connect Social Scribe to Salesforce:

1. **Create a Salesforce org** (if needed)
   - [Developer Edition](https://developer.salesforce.com/signup) (free) — recommended for development
   - Or use an existing org / sandbox

2. **Create a Connected App**
   - In Salesforce: **Setup** → **Apps** → **App Manager** → **New Connected App**
   - Enable **OAuth Settings**
   - **Callback URL**: must match **exactly** (including `/dashboard`). Add one of:
     - Local: `http://localhost:4000/dashboard/auth/salesforce/callback`
     - Production: `https://yourdomain.com/dashboard/auth/salesforce/callback`
   - Note: The path is `/dashboard/auth/salesforce/callback` (not `/auth/salesforce/callback`).
   - **Selected OAuth Scopes**: add at least:
     - Access and manage your data (api)
     - Perform requests on your behalf at any time (refresh_token, offline_access)
     - Provide access to your data via the Web (web)
   - Save and note the **Consumer Key** (Client ID) and **Consumer Secret** (Client Secret).
   - This app uses **PKCE** (code_challenge / code_verifier); no extra Connected App settings are required for that.

3. **Configure environment variables**
   - `SALESFORCE_CLIENT_ID` = Consumer Key
   - `SALESFORCE_CLIENT_SECRET` = Consumer Secret
   - `SALESFORCE_REDIRECT_URI` = **exact** Callback URL (must include `/dashboard`):
     - Local: `http://localhost:4000/dashboard/auth/salesforce/callback`
     - Production: `https://yourdomain.com/dashboard/auth/salesforce/callback`
   - **Sandbox only:** `SALESFORCE_AUTH_BASE_URL=https://test.salesforce.com` (omit for production)

4. **Developer Edition vs Sandbox**
   - **Developer Edition (main org):** You log in at `login.salesforce.com`. Use **production** settings: do **not** set `SALESFORCE_AUTH_BASE_URL`. Create the Connected App in **Setup** in that org and use its Consumer Key/Secret.
   - **Sandbox (e.g. from Developer Edition):** You log in at `test.salesforce.com` or a `*.sandbox.my.salesforce.com` URL. Set `SALESFORCE_AUTH_BASE_URL=https://test.salesforce.com`. Create the Connected App **inside the sandbox** (open the sandbox, then Setup → App Manager) and use that app’s Consumer Key/Secret. Production and sandbox Connected Apps have different keys and cannot be mixed.

### Troubleshooting

- **`redirect_uri_mismatch`**  
  Callback URL in the Connected App must match exactly (including `http` vs `https`, port, and path with `/dashboard`). Use the same value in `.env` as `SALESFORCE_REDIRECT_URI`.

- **`invalid_client_id` / "client identifier invalid"**  
  Salesforce doesn’t recognise the Consumer Key. Check:
  1. **Same org and environment:** The Consumer Key and Secret must come from the **same** org (and same login host) you use to sign in. For **sandbox**, create the Connected App in the sandbox org (Setup in the sandbox) and use `SALESFORCE_AUTH_BASE_URL=https://test.salesforce.com`. Use the **sandbox** Connected App’s Consumer Key/Secret, not a production app’s.
  2. **Copy correctly:** In the sandbox go to **Setup → App Manager → your app → Manage → View** and copy the **Consumer Key** and **Consumer Secret** into `.env` with no extra spaces or line breaks.
  3. **App is active:** After creating the Connected App, save it. If your org uses it, ensure the app is **Available** or activated so OAuth can use it.

References:
- [Create a Connected App](https://help.salesforce.com/articleView?id=connected_app_create.htm)
- [OAuth 2.0 Web Server Flow](https://help.salesforce.com/articleView?id=remoteaccess_oauth_web_server_flow.htm)
