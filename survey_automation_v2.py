# Survey Automation v2 - Multi-IP Routing
import json
import requests
import asyncio
from playwright.async_api import async_playwright
import logging
from datetime import datetime
import os

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

# Load configuration
CONFIG_FILE = "/data/data/com.termux/files/home/vpn_v2/config.json"

def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

CONFIG = load_config()

class SurveyAutomation:
    def __init__(self):
        self.is_running = False

    def get_proxy_for_account(self, email: str):
        """Returns proxy configuration for an account"""
        
        account = CONFIG["accounts"].get(email)
        if not account:
            raise ValueError(f"Unknown account: {email}")
        
        port = account["proxy_port"]
        proxy_url = f"http://127.0.0.1:{port}"
        
        return {
            "server": proxy_url,
            "username": None,
            "password": None
        }

    async def check_swiss_ip(self, proxy_config):
        """Check IP through specific proxy"""
        try:
            proxies = {
                "http": proxy_config["server"],
                "https": proxy_config["server"]
            }
            
            resp = requests.get(
                "https://ipapi.co/json/",
                proxies=proxies,
                timeout=10
            )
            
            data = resp.json()
            country = data.get("country_code", "")
            is_swiss = country == "CH"
            
            return is_swiss, data
        except Exception as e:
            logger.error(f"IP check failed: {e}")
            return False, {}

    async def accept_survey(self, email, survey_url, reward=None):
        """Accept survey with automatic proxy selection"""
        
        # Get proxy for this account
        proxy_config = self.get_proxy_for_account(email)
        
        account = CONFIG["accounts"][email]
        
        # Check IP through the correct proxy
        is_swiss, ip_data = await self.check_swiss_ip(proxy_config)
        
        logger.info(f"Account: {email}")
        logger.info(f"Proxy: {account['upstream']['name']}")
        logger.info(f"IP: {ip_data.get('ip')} ({ip_data.get('country_name')})")
        
        if not is_swiss:
            logger.error(f"Not in Switzerland! Location: {ip_data}")
            return {"success": False, "error": "Not in Switzerland"}
        
        # Launch browser with the correct proxy
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=False)
            
            context = await browser.new_context(
                proxy=proxy_config,  # ← AUTO SELECTS CORRECT PROXY
                viewport={"width": 1920, "height": 1080},
                user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                locale="de-CH",
                timezone_id="Europe/Zurich"
            )
            
            # Add cookies if available
            cookies_file = account.get("cookies_file")
            if cookies_file and os.path.exists(cookies_file):
                try:
                    with open(cookies_file, "r") as f:
                        cookies = json.load(f)
                    await context.add_cookies(cookies)
                except Exception as e:
                    logger.warning(f"Could not load cookies: {e}")
            
            page = await context.new_page()
            
            try:
                # Navigate to survey
                await page.goto(survey_url, wait_until="networkidle")
                
                # Wait for potential login or cookie acceptance
                await page.wait_for_timeout(2000)
                
                # Look for survey acceptance button - FIXED: Properly quoted selectors
                accept_selectors = [
                    'button:has-text("Accept Survey")',
                    'button:has-text("Start Survey")', 
                    'button:has-text("Beantworten")',
                    'button:has-text("Teilnehmen")',
                    'button[type="submit"]',
                    '.survey-start-btn',
                    'a[href*="accept"]',
                    'a[href*="start"]'
                ]
                
                accepted = False
                for selector in accept_selectors:
                    try:
                        # Wait a bit to ensure page is loaded
                        await page.wait_for_timeout(1000)
                        
                        # Try to find and click the element
                        element = page.locator(selector).first
                        
                        # Check if element is visible
                        if await element.is_visible(timeout=3000):
                            await element.click()
                            logger.info(f"Clicked: {selector}")
                            accepted = True
                            break
                    except Exception as e:
                        # Element not found or not clickable, try next selector
                        logger.debug(f"Selector {selector} failed: {e}")
                        continue
                
                if not accepted:
                    logger.warning("Could not find survey acceptance button")
                
                # Wait and monitor for survey completion
                await page.wait_for_timeout(5000)
                
                # Save cookies for next time
                cookies = await context.cookies()
                with open(account["cookies_file"], "w") as f:
                    json.dump(cookies, f)
                
                logger.info(f"Survey session completed for {email}")
                
                return {"success": True, "message": f"Survey completed for {email}"}
                
            except Exception as e:
                logger.error(f"Survey error for {email}: {e}")
                return {"success": False, "error": str(e)}
            finally:
                await browser.close()

    async def run(self):
        """Main service loop"""
        logger.info("Starting Survey Automation v2...")
        self.is_running = True
        
        # Start HTTP server to receive survey requests
        from aiohttp import web
        
        async def handle_survey_request(request):
            try:
                data = await request.json()
                email = data.get("email")
                survey_url = data.get("url")
                reward = data.get("reward")
                
                result = await self.accept_survey(email, survey_url, reward)
                return web.json_response(result)
            except Exception as e:
                logger.error(f"Request handling error: {e}")
                return web.json_response({"error": str(e)}, status=500)
        
        app = web.Application()
        app.router.add_post("/survey", handle_survey_request)
        
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", CONFIG["survey_service_port"])
        await site.start()
        
        logger.info(f"Survey service running on port {CONFIG['survey_service_port']}")
        
        # Keep running
        while self.is_running:
            await asyncio.sleep(1)

def main():
    automation = SurveyAutomation()
    asyncio.run(automation.run())

if __name__ == "__main__": 
    main()
