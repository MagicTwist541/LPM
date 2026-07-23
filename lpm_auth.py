import http.server
import socketserver
import urllib.parse
import webbrowser
from pathlib import Path
import json

CONFIG_DIR = Path.home() / ".local/share/lpm"
TOKEN_FILE = CONFIG_DIR / "tokens.json"

# OAuth App Credentials (or Self-Hosted Gateway)
PROVIDERS = {
    "gdrive": {
        "name": "Google Drive",
        "auth_url": "https://accounts.google.com/o/oauth2/v2/auth",
        "client_id": "YOUR_GDRIVE_CLIENT_ID.apps.googleusercontent.com",
        "scope": "https://www.googleapis.com/auth/drive.file"
    },
    "dropbox": {
        "name": "Dropbox",
        "auth_url": "https://www.dropbox.com/oauth2/authorize",
        "client_id": "YOUR_DROPBOX_CLIENT_ID",
        "scope": "files.content.write files.content.read"
    }
}

class OAuthHandler(http.server.SimpleHTTPRequestHandler):
    """Temporary local HTTP server to receive the auth token/code callback."""
    def do_GET(self):
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        
        if "code" in params:
            auth_code = params["code"][0]
            
            # Save token
            tokens = {}
            if TOKEN_FILE.exists():
                try:
                    with open(TOKEN_FILE, "r") as f:
                        tokens = json.load(f)
                except Exception:
                    pass
            
            tokens[self.server.provider_key] = {"code": auth_code}
            with open(TOKEN_FILE, "w") as f:
                json.dump(tokens, f, indent=2)

            # Send success page to user's browser
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            self.wfile.write(b"<h1>SUCCESS! Signed into Linux Package Manager.</h1><p>You can close this tab and return to your terminal.</p>")
            self.server.auth_successful = True
        else:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Authentication failed.")

    def log_message(self, format, *args):
        # Suppress standard HTTP server logs
        return

def sign_in_provider(provider_key):
    if provider_key not in PROVIDERS:
        print("❌ Provider not supported for direct browser sign-in.")
        return

    prov = PROVIDERS[provider_key]
    redirect_uri = "http://localhost:8080"
    
    # Construct auth URL
    params = {
        "client_id": prov["client_id"],
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": prov["scope"],
        "access_type": "offline"
    }
    url = f"{prov['auth_url']}?{urllib.parse.urlencode(params)}"

    print(f"\n🌐 Opening browser to sign into {prov['name']}...")
    webbrowser.open(url)

    # Listen on localhost:8080 for callback
    with socketserver.TCPServer(("localhost", 8080), OAuthHandler) as httpd:
        httpd.provider_key = provider_key
        httpd.auth_successful = False
        print("⏳ Waiting for sign-in in browser...")
        
        while not httpd.auth_successful:
            httpd.handle_request()

    print(f"🎉 Successfully signed into {prov['name']}!")
