"""Setup script for Secure Password Manager"""
from setuptools import setup, find_packages
import os

# Read README
readme_path = os.path.join(os.path.dirname(__file__), 'readme.md')
long_description = ""
if os.path.exists(readme_path):
    with open(readme_path, 'r', encoding='utf-8') as f:
        long_description = f.read()

setup(
    name="secure-password-manager",
    version="1.0.0",
    description="A world-class secure password management application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="Secure Password Manager Team",
    author_email="",
    url="https://github.com/yourusername/secure-password-manager",
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        "cryptography>=41.0.0",
    ],
    python_requires=">=3.8",
    entry_points={
        "console_scripts": [
            "password-manager=app:main",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: End Users/Desktop",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Security",
        "Topic :: Utilities",
    ],
    keywords="password manager security encryption vault",
)

