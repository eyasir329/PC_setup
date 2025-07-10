#!/usr/bin/env python3
"""
Setup script for Contest Environment Manager (finalized for Squid/Playwright)
"""

from setuptools import setup, find_packages
import os

def get_version():
    with open(os.path.join('contest_manager', '__init__.py'), 'r') as f:
        for line in f:
            if line.startswith('__version__'):
                return line.split('=')[1].strip().strip('"\'')
    return '1.0.0'

def get_long_description():
    with open('README.md', 'r', encoding='utf-8') as f:
        return f.read()

def get_requirements():
    req_path = os.path.join(os.path.dirname(__file__), 'requirements', 'requirements.txt')
    with open(req_path, 'r') as f:
        return [line.strip() for line in f if line.strip() and not line.startswith('#')]

def get_dev_requirements():
    req_path = os.path.join(os.path.dirname(__file__), 'requirements', 'dev.txt')
    with open(req_path, 'r') as f:
        return [line.strip() for line in f if line.strip() and not line.startswith('#')]

setup(
    name='contest-environment-manager',
    version=get_version(),
    author='Contest Manager Team',
    author_email='support@contest-manager.example.com',
    description='Professional contest environment management system',
    long_description=get_long_description(),
    long_description_content_type='text/markdown',
    url='https://github.com/username/contest-environment-manager',
    packages=find_packages(),
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: System Administrators',
        'Intended Audience :: Education',
        'Topic :: System :: Systems Administration',
        'Topic :: Security',
        'Topic :: Education',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Operating System :: POSIX :: Linux',
        'Environment :: Console',
    ],
    python_requires='>=3.6',
    install_requires=get_requirements(),
    extras_require={
        'dev': get_dev_requirements(),
    },
    entry_points={
        'console_scripts': [
            'contest-manager=contest_manager.cli.main:main',
            'contest-setup=contest_manager.cli.setup:main',
            'contest-restrict=contest_manager.cli.restrict:main',
            'contest-unrestrict=contest_manager.cli.unrestrict:main',
            'contest-reset=contest_manager.cli.reset:main',
        ],
    },
    include_package_data=True,
    package_data={
        'contest_manager': [
            'data/*.txt',
            'data/*.json',
            'templates/*.txt',
            'templates/*.service',
        ],
    },
    zip_safe=False,
    keywords='contest environment security network usb restrictions',
    project_urls={
        'Bug Reports': 'https://github.com/username/contest-environment-manager/issues',
        'Source': 'https://github.com/username/contest-environment-manager',
        'Documentation': 'https://contest-environment-manager.readthedocs.io/',
    },
)
