# 🚀 Quick Start Guide

Get up and running with Secure Password Manager in 3 minutes!

## Step 1: Install Dependencies

```bash
pip install -r requirements.txt
```

## Step 2: Launch the Application

**Option A: Using Python**
```bash
python app.py
```

**Option B: Using Launcher Scripts**
- **Windows**: Double-click `run.bat`
- **Linux/macOS**: `chmod +x run.sh && ./run.sh`

## Step 3: Create Your Master Password

When you first launch:
1. Enter a **strong master password** (minimum 8 characters)
2. Remember this password - you'll need it every time you open the app
3. Click **"Unlock Vault"**

> 💡 **Tip**: Use a passphrase like "MySecurePass2024!" for better security

## Step 4: Add Your First Credential

1. Click **"➕ Add New"** button
2. Fill in:
   - **Site Name**: e.g., "Gmail", "Facebook"
   - **Username**: Your username/email
   - **Password**: Your password (or click **"🎲 Generate"** for a strong one)
3. Click **"Save"**

## Step 5: Use Your Credentials

1. **View**: Click on any credential in the list
2. **Copy**: Click **"📋 Copy Username"** or **"📋 Copy Password"**
3. **Search**: Type in the search box to filter credentials
4. **Edit**: Select a credential and click **"✏️ Edit"**
5. **Delete**: Select a credential and click **"🗑️ Delete"**

## 🎲 Generate Strong Passwords

1. Go to **Tools → Generate Password...**
2. Adjust settings:
   - **Length**: 8-128 characters (16 recommended)
   - **Character Types**: Uppercase, Lowercase, Digits, Symbols
3. Click **"🎲 Generate"**
4. Click **"📋 Copy"** to copy to clipboard

## 💾 Backup Your Vault

**Export (Backup)**:
1. Go to **File → Export Vault...**
2. Choose a location and filename
3. Save your encrypted vault backup

**Import (Restore)**:
1. Go to **File → Import Vault...**
2. Select your backup file
3. Confirm to replace current vault

> ⚠️ **Important**: Keep your backups secure and encrypted!

## 🔒 Lock Your Vault

- Click **"🔒 Lock"** button or go to **File → Lock Vault**
- Your vault will be locked and you'll need to enter your master password again

## 🆘 Troubleshooting

### "Import Error" or "Module Not Found"
- Make sure you're in the project directory
- Run: `pip install -r requirements.txt`

### "Incorrect Master Password"
- Make sure Caps Lock is off
- Check if you're using the correct password
- If you forgot it, you'll need to restore from backup

### Application Won't Start
- Check Python version: `python --version` (needs 3.8+)
- Reinstall dependencies: `pip install --upgrade -r requirements.txt`

## 📚 Next Steps

- Read [readme.md](readme.md) for full documentation
- Check [SECURITY.md](SECURITY.md) for security details
- See [INSTALL.md](INSTALL.md) for advanced installation

---

**Enjoy secure password management! 🔐**

