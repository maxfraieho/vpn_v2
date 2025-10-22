import json
import requests
import asyncio
from aiohttp import web
import logging
from datetime import datetime
import os
from bs4 import BeautifulSoup
from urllib.parse import urljoin

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("/data/data/com.termux/files/home/vpn_v2/survey.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

CONFIG_FILE = "/data/data/com.termux/files/home/vpn_v2/config.json"

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

CONFIG = load_config()

class SurveyAutomation:
    def __init__(self):
        self.is_running = False
        self.sessions = {}  # Store session cookies per account

    def get_proxy_for_account(self, email):
        """Returns proxy configuration for an account"""
        account = CONFIG["accounts"].get(email)
        if not account:
            raise ValueError(f"Unknown account: {email}")
        
        port = account["proxy_port"]
        proxy_url = f"http://127.0.0.1:{port}"
        
        return {
            "http": proxy_url,
            "https": proxy_url
        }

    def get_session(self, email):
        """Get or create session for account"""
        if email not in self.sessions:
            session = requests.Session()
            
            # Load cookies if available
            account = CONFIG["accounts"].get(email)
            cookies_file = account.get("cookies_file")
            
            if cookies_file and os.path.exists(cookies_file):
                try:
                    with open(cookies_file, "r") as f:
                        cookies_data = json.load(f)
                        for cookie in cookies_data:
                            session.cookies.set(
                                cookie.get('name'),
                                cookie.get('value'),
                                domain=cookie.get('domain')
                            )
                    logger.info(f"Loaded cookies for {email}")
                except Exception as e:
                    logger.warning(f"Could not load cookies: {e}")
            
            self.sessions[email] = session
        
        return self.sessions[email]

    def save_cookies(self, email, session):
        """Save session cookies"""
        account = CONFIG["accounts"].get(email)
        cookies_file = account.get("cookies_file")
        
        if cookies_file:
            try:
                cookies_data = []
                for cookie in session.cookies:
                    cookies_data.append({
                        'name': cookie.name,
                        'value': cookie.value,
                        'domain': cookie.domain,
                        'path': cookie.path
                    })
                
                with open(cookies_file, "w") as f:
                    json.dump(cookies_data, f)
                
                logger.info(f"Saved cookies for {email}")
            except Exception as e:
                logger.error(f"Failed to save cookies: {e}")

    def check_swiss_ip(self, proxy_config):
        """Check IP through specific proxy"""
        try:
            resp = requests.get(
                "https://ipapi.co/json/",
                proxies=proxy_config,
                timeout=10
            )
            
            data = resp.json()
            country = data.get("country_code", "")
            is_swiss = country == "CH"
            
            return is_swiss, data
        except Exception as e:
            logger.error(f"IP check failed: {e}")
            return False, {}

    def accept_survey_simple(self, email, survey_url, reward=None):
        """Accept survey using requests library (no browser automation)"""
        
        proxy_config = self.get_proxy_for_account(email)
        account = CONFIG["accounts"][email]
        
        # Check IP
        is_swiss, ip_data = self.check_swiss_ip(proxy_config)
        
        logger.info(f"Account: {email}")
        logger.info(f"Proxy: {account['upstream']['name']}")
        logger.info(f"IP: {ip_data.get('ip')} ({ip_data.get('country_name')})")
        
        if not is_swiss:
            logger.error(f"Not in Switzerland! Location: {ip_data}")
            return {"success": False, "error": "Not in Switzerland"}
        
        # Get session
        session = self.get_session(email)
        
        try:
            # Set headers to mimic browser
            headers = {
                'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                'Accept-Language': 'de-CH,de;q=0.9,en;q=0.8',
                'Accept-Encoding': 'gzip, deflate, br',
                'DNT': '1',
                'Connection': 'keep-alive',
                'Upgrade-Insecure-Requests': '1'
            }
            
            # Navigate to survey
            response = session.get(
                survey_url,
                proxies=proxy_config,
                headers=headers,
                timeout=30,
                allow_redirects=True
            )
            
            if response.status_code != 200:
                return {
                    "success": False,
                    "error": f"HTTP {response.status_code}"
                }
            
            # Parse HTML to find survey acceptance form
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Look for forms or buttons that might accept survey
            forms = soup.find_all('form')
            accept_buttons = soup.find_all(['button', 'a'], 
                text=lambda t: t and any(word in t.lower() for word in 
                    ['accept', 'start', 'teilnehmen', 'beantworten', 'begin']))
            
            logger.info(f"Found {len(forms)} forms and {len(accept_buttons)} potential accept buttons")
            
            # Try to submit first form if exists
            if forms:
                form = forms[0]
                action = form.get('action', '')
                method = form.get('method', 'get').lower()
                
                # Build form action URL
                if action:
                    form_url = urljoin(response.url, action)
                else:
                    form_url = response.url
                
                # Collect form data
                form_data = {}
                for input_tag in form.find_all(['input', 'select', 'textarea']):
                    name = input_tag.get('name')
                    if name:
                        value = input_tag.get('value', '')
                        form_data[name] = value
                
                logger.info(f"Submitting form to {form_url}")
                
                # Submit form
                if method == 'post':
                    submit_response = session.post(
                        form_url,
                        data=form_data,
                        proxies=proxy_config,
                        headers=headers,
                        timeout=30
                    )
                else:
                    submit_response = session.get(
                        form_url,
                        params=form_data,
                        proxies=proxy_config,
                        headers=headers,
                        timeout=30
                    )
                
                logger.info(f"Form submitted, response: {submit_response.status_code}")
            
            # Save cookies
            self.save_cookies(email, session)
            
            return {
                "success": True,
                "message": f"Survey page accessed for {email}",
                "url": response.url,
                "forms_found": len(forms),
                "buttons_found": len(accept_buttons)
            }
            
        except requests.RequestException as e:
            logger.error(f"Request error for {email}: {e}")
            return {"success": False, "error": str(e)}
        except Exception as e:
            logger.error(f"Survey error for {email}: {e}")
            return {"success": False, "error": str(e)}

    async def run(self):
        """Main service loop"""
        logger.info("Starting Survey Automation v2 (Simple Mode)...")
        self.is_running = True
        
        async def handle_survey_request(request):
            try:
                data = await request.json()
                email = data.get("email")
                survey_url = data.get("url")
                reward = data.get("reward")
                
                # Run in thread to avoid blocking
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(
                    None,
                    self.accept_survey_simple,
                    email,
                    survey_url,
                    reward
                )
                
                return web.json_response(result)
            except Exception as e:
                logger.error(f"Request handling error: {e}")
                return web.json_response({"error": str(e)}, status=500)
        
        async def handle_status(request):
            return web.json_response({
                "status": "running",
                "mode": "simple",
                "accounts": list(CONFIG["accounts"].keys())
            })
        
        app = web.Application()
        app.router.add_post("/survey", handle_survey_request)
        app.router.add_get("/status", handle_status)
        
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", CONFIG["survey_service_port"])
        await site.start()
        
        logger.info(f"Survey service running on port {CONFIG['survey_service_port']}")
        logger.info("Mode: Simple (no browser automation)")
        
        # Keep running
        while self.is_running:
            await asyncio.sleep(1)

def main():
    automation = SurveyAutomation()
    asyncio.run(automation.run())

if __name__ == "__main__":
    main()