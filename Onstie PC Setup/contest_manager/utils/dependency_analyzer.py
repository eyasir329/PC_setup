#!/usr/bin/env python3
"""
Website Dependency Analyzer
Analyzes websites to discover essential external dependencies using Playwright.
"""

import time
import json
import re
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright


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

    def analyze_domain(self, domain):
        """Analyze a domain and discover its dependencies using Playwright HAR capture."""
        print(f"🔍 Analyzing {domain}...")
        dependencies = set()
        url = f"https://{domain}"
        har_path = f"/tmp/{domain.replace('.', '_')}.har"
        try:
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True)
                context = browser.new_context(record_har_path=har_path)
                page = context.new_page()
                page.goto(url)
                page.wait_for_timeout(5000)
                context.close()
                browser.close()
            # Parse HAR file for domains
            with open(har_path, 'r') as f:
                har = json.load(f)
            for entry in har['log']['entries']:
                req_url = entry['request']['url']
                dep_domain = self.extract_domain(req_url)
                if dep_domain and dep_domain != domain:
                    dependencies.add(dep_domain)
        except Exception as e:
            print(f"  ❌ Error analyzing {domain}: {e}")
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

    def filter_dependencies(self, dependencies):
        """Filter dependencies to keep only essential ones."""
        essential_deps = set()
        
        for dep in dependencies:
            # Skip if it matches blocked keywords
            is_blocked = any(keyword in dep.lower() for keyword in self.blocked_keywords)
            if is_blocked:
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
