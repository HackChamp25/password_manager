# Installation Guide

## Quick Start

### Option 1: Run from Source

1. **Clone or download the repository**
   ```bash
   cd password_manager
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Run the application**
   ```bash
   python app.py
   ```

### Option 2: Install as Package

1. **Install the package**
   ```bash
   pip install -e .
   ```

2. **Run the application**
   ```bash
   password-manager
   ```
   Or:
   ```bash
   python app.py
   ```

## System Requirements

- **Python**: 3.8 or higher
- **Operating System**: Windows, macOS, or Linux
- **Dependencies**: See `requirements.txt`

## First Run

1. Launch the application
2. Enter a **strong master password** (minimum 8 characters)
   - This will be your only password to remember
   - Make it strong and unique!
3. The vault will be created automatically
4. Start adding your credentials

## Features

- ✅ **Secure Encryption**: AES-128 encryption with PBKDF2 key derivation
- ✅ **Modern GUI**: Professional desktop interface
- ✅ **Password Generator**: Create strong passwords instantly
- ✅ **Search & Filter**: Quickly find your credentials
- ✅ **Export/Import**: Backup and restore your vault
- ✅ **Copy to Clipboard**: One-click copy for usernames and passwords
- ✅ **Password Strength Checker**: Verify password quality

## Troubleshooting

### Import Errors
If you encounter import errors, make sure you're running from the project root directory:
```bash
cd D:\Cybersecurity\projects\password_manager
python app.py
```

### Permission Errors (Linux/macOS)
If you get permission errors, the vault directory should be created automatically with proper permissions. If issues persist:
```bash
chmod 700 vault/
```

### Windows Defender / Antivirus
Some antivirus software may flag password managers. This is a false positive. You can:
- Add the application folder to exclusions
- Report it as a false positive to your antivirus vendor

## Security Notes

- **Master Password**: Never share your master password
- **Backup**: Regularly export your vault as backup
- **Updates**: Keep the application updated
- **System Security**: Ensure your system is secure and malware-free

## Support

For issues or questions, please check:
- `SECURITY.md` for security documentation
- `readme.md` for general information

