#!/usr/bin/env python3
"""
Intelligent Website Dependency Analyzer
Analyzes websites to discover essential external dependencies using browser automation.
"""

import time
import json
import re
import subprocess
from urllib.parse import urlparse
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, WebDriverException
import requests


class DependencyAnalyzer:
    def __init__(self):
        self.blocked_keywords = [
            # AI and Chatbots
            'openai', 'chatgpt', 'anthropic', 'claude', 'gemini', 'bard',
            # Search Engines
            'google', 'bing', 'yahoo', 'duckduckgo', 'yandex', 'baidu',
            # Social Media
            'facebook', 'twitter', 'instagram', 'linkedin', 'reddit', 'discord',
            'telegram', 'whatsapp', 'tiktok', 'youtube', 'snapchat',
            # Development/Coding
            'github', 'gitlab', 'stackoverflow', 'stackexchange', 'medium',
            'dev.to', 'hackernews', 'codepen', 'jsfiddle',
            # Educational/Tutorial
            'wikipedia', 'w3schools', 'tutorialspoint', 'freecodecamp',
            'coursera', 'udemy', 'khan', 'edx',
            # Shopping/Commerce
            'amazon', 'ebay', 'alibaba', 'shopify',
            # Cloud/Storage
            'dropbox', 'onedrive', 'icloud', 'mega',
            # News/Media
            'cnn', 'bbc', 'reuters', 'news', 'techcrunch'
        ]
        
        self.essential_keywords = [
            # CDNs and Static Content
            'cdn', 'static', 'assets', 'img', 'css', 'js', 'fonts',
            'cloudflare', 'cloudfront', 'fastly', 'jsdelivr', 'unpkg',
            'bootstrapcdn', 'jquery', 'ajax', 'gstatic',
            # Security and Auth
            'captcha', 'recaptcha', 'hcaptcha', 'auth', 'oauth',
            'ssl', 'tls', 'cert', 'security',
            # Essential APIs
            'api', 'webhook', 'analytics', 'tracking',
            # Math and Rendering
            'mathjax', 'katex', 'mermaid', 'highlight',
            # Fonts and Icons
            'fontawesome', 'typekit', 'googlefonts'
        ]

    def setup_browser(self):
        """Setup headless Chrome browser with network logging."""
        chrome_options = Options()
        chrome_options.add_argument('--headless')
        chrome_options.add_argument('--no-sandbox')
        chrome_options.add_argument('--disable-dev-shm-usage')
        chrome_options.add_argument('--disable-gpu')
        chrome_options.add_argument('--window-size=1920,1080')
        chrome_options.add_argument('--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
        
        # Enable logging
        chrome_options.add_argument('--enable-logging')
        chrome_options.add_argument('--log-level=0')
        chrome_options.add_experimental_option('useAutomationExtension', False)
        chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
        
        # Enable performance logging to capture network requests
        chrome_options.add_experimental_option('perfLoggingPrefs', {
            'enableNetwork': True,
            'enablePage': False,
        })
        chrome_options.add_experimental_option('loggingPrefs', {'performance': 'ALL'})
        
        try:
            driver = webdriver.Chrome(options=chrome_options)
            return driver
        except Exception as e:
            print(f"❌ Failed to setup Chrome browser: {e}")
            print("→ Installing Chrome and ChromeDriver...")
            self.install_chrome_dependencies()
            driver = webdriver.Chrome(options=chrome_options)
            return driver

    def install_chrome_dependencies(self):
        """Install Chrome and ChromeDriver if not available."""
        try:
            # Install Chrome
            subprocess.run(['wget', '-q', '-O', '/tmp/chrome.deb', 
                          'https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb'], 
                         check=True)
            subprocess.run(['dpkg', '-i', '/tmp/chrome.deb'], check=False)
            subprocess.run(['apt-get', 'install', '-f', '-y'], check=True)
            
            # Install ChromeDriver
            subprocess.run(['apt-get', 'install', '-y', 'chromium-chromedriver'], check=True)
            
            print("✅ Chrome dependencies installed successfully")
        except Exception as e:
            print(f"❌ Failed to install Chrome dependencies: {e}")
            raise

    def analyze_domain(self, domain):
        """Analyze a domain and discover its dependencies."""
        print(f"🔍 Analyzing {domain}...")
        
        dependencies = set()
        driver = None
        
        try:
            driver = self.setup_browser()
            
            # Try different URL variations
            urls_to_try = [
                f"https://{domain}",
                f"http://{domain}",
                f"https://www.{domain}",
                f"http://www.{domain}"
            ]
            
            for url in urls_to_try:
                try:
                    print(f"  → Trying {url}")
                    driver.get(url)
                    
                    # Wait for page to load
                    WebDriverWait(driver, 10).until(
                        lambda d: d.execute_script("return document.readyState") == "complete"
                    )
                    
                    # Additional wait for dynamic content
                    time.sleep(3)
                    
                    # Get network logs
                    logs = driver.get_log('performance')
                    for log in logs:
                        message = json.loads(log['message'])
                        if message['message']['method'] == 'Network.requestWillBeSent':
                            request_url = message['message']['params']['request']['url']
                            dep_domain = self.extract_domain(request_url)
                            if dep_domain and dep_domain != domain:
                                dependencies.add(dep_domain)
                    
                    # Also analyze page source for additional dependencies
                    page_source = driver.page_source
                    source_deps = self.extract_dependencies_from_source(page_source, domain)
                    dependencies.update(source_deps)
                    
                    break  # Successfully loaded, no need to try other URLs
                    
                except TimeoutException:
                    print(f"  ⚠️ Timeout loading {url}")
                    continue
                except WebDriverException as e:
                    print(f"  ⚠️ Failed to load {url}: {str(e)[:100]}")
                    continue
            
        except Exception as e:
            print(f"  ❌ Error analyzing {domain}: {e}")
        finally:
            if driver:
                driver.quit()
        
        # Filter dependencies
        filtered_deps = self.filter_dependencies(dependencies)
        print(f"  ✅ Found {len(filtered_deps)} essential dependencies")
        
        return filtered_deps

    def extract_domain(self, url):
        """Extract domain from URL."""
        try:
            parsed = urlparse(url)
            domain = parsed.netloc.lower()
            # Remove port numbers
            if ':' in domain:
                domain = domain.split(':')[0]
            # Remove www prefix for consistency
            if domain.startswith('www.'):
                domain = domain[4:]
            return domain if domain else None
        except:
            return None

    def extract_dependencies_from_source(self, html, main_domain):
        """Extract dependencies from HTML source."""
        dependencies = set()
        
        # Regex patterns for finding URLs in HTML
        patterns = [
            r'src=["\']([^"\']+)["\']',
            r'href=["\']([^"\']+)["\']',
            r'url\(["\']?([^"\'()]+)["\']?\)',
            r'@import\s+["\']([^"\']+)["\']'
        ]
        
        for pattern in patterns:
            matches = re.findall(pattern, html, re.IGNORECASE)
            for match in matches:
                if match.startswith(('http://', 'https://')):
                    domain = self.extract_domain(match)
                    if domain and domain != main_domain:
                        dependencies.add(domain)
        
        return dependencies

    def filter_dependencies(self, dependencies):
        """Filter dependencies to keep only essential ones."""
        essential_deps = set()
        
        for dep in dependencies:
            # Skip if it matches blocked keywords
            is_blocked = any(keyword in dep.lower() for keyword in self.blocked_keywords)
            if is_blocked:
                print(f"    🚫 Blocked: {dep}")
                continue
            
            # Include if it matches essential keywords
            is_essential = any(keyword in dep.lower() for keyword in self.essential_keywords)
            
            # Also include CDN patterns and common essential services
            is_cdn = any(pattern in dep.lower() for pattern in [
                'cdn.', 'static.', 'assets.', 'img.', 'css.', 'js.',
                'fonts.', 'api.', 'auth.', 'ssl.', 'captcha'
            ])
            
            # Include common TLD patterns for CDNs
            is_common_cdn = dep.endswith(('.net', '.io')) and any(cdn in dep.lower() for cdn in [
                'cloudflare', 'fastly', 'amazon', 'microsoft', 'akamai'
            ])
            
            if is_essential or is_cdn or is_common_cdn:
                essential_deps.add(dep)
                print(f"    ✅ Essential: {dep}")
            else:
                print(f"    ❓ Skipped: {dep}")
        
        return essential_deps

    def analyze_domain(self, domain):
        """Analyze a domain and discover its dependencies."""
        print(f"🔍 Analyzing {domain}...")
        
        dependencies = set()
        driver = None
        
        try:
            driver = self.setup_browser()
            
            # Try different URL variations
            urls_to_try = [
                f"https://{domain}",
                f"http://{domain}",
                f"https://www.{domain}",
                f"http://www.{domain}"
            ]
            
            for url in urls_to_try:
                try:
                    print(f"  → Trying {url}")
                    driver.get(url)
                    
                    # Wait for page to load
                    WebDriverWait(driver, 10).until(
                        lambda d: d.execute_script("return document.readyState") == "complete"
                    )
                    
                    # Additional wait for dynamic content
                    time.sleep(3)
                    
                    # Get network logs
                    logs = driver.get_log('performance')
                    for log in logs:
                        message = json.loads(log['message'])
                        if message['message']['method'] == 'Network.requestWillBeSent':
                            request_url = message['message']['params']['request']['url']
                            dep_domain = self.extract_domain(request_url)
                            if dep_domain and dep_domain != domain:
                                dependencies.add(dep_domain)
                    
                    # Also analyze page source for additional dependencies
                    page_source = driver.page_source
                    source_deps = self.extract_dependencies_from_source(page_source, domain)
                    dependencies.update(source_deps)
                    
                    break  # Successfully loaded, no need to try other URLs
                    
                except TimeoutException:
                    print(f"  ⚠️ Timeout loading {url}")
                    continue
                except WebDriverException as e:
                    print(f"  ⚠️ Failed to load {url}: {str(e)[:100]}")
                    continue
            
        except Exception as e:
            print(f"  ❌ Error analyzing {domain}: {e}")
        finally:
            if driver:
                driver.quit()
        
        # Filter dependencies
        filtered_deps = self.filter_dependencies(dependencies)
        print(f"  ✅ Found {len(filtered_deps)} essential dependencies")
        
        return filtered_deps

    def extract_domain(self, url):
        """Extract domain from URL."""
        try:
            parsed = urlparse(url)
            domain = parsed.netloc.lower()
            # Remove port numbers
            if ':' in domain:
                domain = domain.split(':')[0]
            # Remove www prefix for consistency
            if domain.startswith('www.'):
                domain = domain[4:]
            return domain if domain else None
        except:
            return None

    def extract_dependencies_from_source(self, html, main_domain):
        """Extract dependencies from HTML source."""
        dependencies = set()
        
        # Regex patterns for finding URLs in HTML
        patterns = [
            r'src=["\']([^"\']+)["\']',
            r'href=["\']([^"\']+)["\']',
            r'url\(["\']?([^"\'()]+)["\']?\)',
            r'@import\s+["\']([^"\']+)["\']'
        ]
        
        for pattern in patterns:
            matches = re.findall(pattern, html, re.IGNORECASE)
            for match in matches:
                if match.startswith(('http://', 'https://')):
                    domain = self.extract_domain(match)
                    if domain and domain != main_domain:
                        dependencies.add(domain)
        
        return dependencies

    def filter_dependencies(self, dependencies):
        """Filter dependencies to keep only essential ones."""
        essential_deps = set()
        
        for dep in dependencies:
            # Skip if it matches blocked keywords
            is_blocked = any(keyword in dep.lower() for keyword in self.blocked_keywords)
            if is_blocked:
                print(f"    🚫 Blocked: {dep}")
                continue
            
            # Include if it matches essential keywords
            is_essential = any(keyword in dep.lower() for keyword in self.essential_keywords)
            
            # Also include CDN patterns and common essential services
            is_cdn = any(pattern in dep.lower() for pattern in [
                'cdn.', 'static.', 'assets.', 'img.', 'css.', 'js.',
                'fonts.', 'api.', 'auth.', 'ssl.', 'captcha'
            ])
            
            # Include common TLD patterns for CDNs
            is_common_cdn = dep.endswith(('.net', '.io')) and any(cdn in dep.lower() for cdn in [
                'cloudflare', 'fastly', 'amazon', 'microsoft', 'akamai'
            ])
            
            if is_essential or is_cdn or is_common_cdn:
                essential_deps.add(dep)
                print(f"    ✅ Essential: {dep}")
            else:
                print(f"    ❓ Skipped: {dep}")
        
        return essential_deps

    def analyze_site(self, site: str):
        """Analyze a site and return essential dependencies (wrapper for restrict.py compatibility)."""
        return self.analyze_domain(site)
    
    def analyze_domains_from_file(self, whitelist_file):
        """Analyze all domains from a whitelist file."""
        dependencies = set()
        
        try:
            with open(whitelist_file, 'r') as f:
                domains = [line.strip() for line in f if line.strip() and not line.startswith('#')]
            
            print(f"📋 Analyzing {len(domains)} domains...")
            
            for domain in domains:
                # Clean domain name
                domain = domain.replace('http://', '').replace('https://', '').split('/')[0]
                deps = self.analyze_domain(domain)
                dependencies.update(deps)
                time.sleep(2)  # Rate limiting
            
            print(f"🎯 Total essential dependencies found: {len(dependencies)}")
            return dependencies
            
        except FileNotFoundError:
            print(f"❌ Whitelist file not found: {whitelist_file}")
            return set()
        except Exception as e:
            print(f"❌ Error reading whitelist file: {e}")
            return set()


def main():
    """Test the dependency analyzer."""
    analyzer = DependencyAnalyzer()
    
    # Test with a single domain
    test_domain = "codeforces.com"
    deps = analyzer.analyze_domain(test_domain)
    
    print(f"\nDependencies for {test_domain}:")
    for dep in sorted(deps):
        print(f"  • {dep}")


if __name__ == "__main__":
    main()
