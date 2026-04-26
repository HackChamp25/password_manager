"""Vault management for password storage"""
import json
import os
import time
from typing import Dict, Optional, Tuple
from cryptography.fernet import Fernet
from .crypto import (
    get_key_from_password,
    get_fernet,
    derive_hmac_key,
    compute_hmac,
    verify_hmac,
    _atomic_write_file,
    secure_delete,
    SALT_FILE
)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VAULT_DIR = os.path.join(BASE_DIR, "vault")
os.makedirs(VAULT_DIR, exist_ok=True)
VERIFY_FILE = os.path.join(VAULT_DIR, "verify.key")
DATA_FILE = os.path.join(VAULT_DIR, "vault.json")

# Rate limiting for brute force protection
MAX_LOGIN_ATTEMPTS = 5
LOGIN_ATTEMPT_DELAY = 2  # seconds


class VaultManager:
    """Manages encrypted vault operations"""
    
    def __init__(self):
        self.fernet: Optional[Fernet] = None
        self.hmac_key: Optional[bytes] = None
        self.master_key: Optional[bytes] = None
        self.failed_attempts = 0
        self.last_attempt_time = 0
    
    def unlock(self, master_password: str) -> Tuple[bool, str]:
        """Unlock vault with master password. Returns (success, message)"""
        try:
            # Derive keys
            key = get_key_from_password(master_password)
            fernet = get_fernet(key)
            hmac_key = derive_hmac_key(key)
            
            # Clear master password from memory (best effort)
            secure_delete(master_password.encode('utf-8'))
            
            # Initialize and verify
            self._initialize_master_key(fernet)
            
            if not self._verify_master_password(fernet):
                secure_delete(key)
                return False, "Incorrect master password"
            
            # Store keys
            self.master_key = key
            self.fernet = fernet
            self.hmac_key = hmac_key
            self.failed_attempts = 0
            
            return True, "Vault unlocked successfully"
            
        except ValueError as e:
            return False, str(e)
        except Exception as e:
            return False, f"Failed to unlock vault: {str(e)}"
    
    def lock(self):
        """Lock vault and clear keys from memory"""
        if self.master_key:
            secure_delete(self.master_key)
        if self.hmac_key:
            secure_delete(self.hmac_key)
        self.fernet = None
        self.hmac_key = None
        self.master_key = None
    
    def _initialize_master_key(self, fernet: Fernet) -> None:
        """Initialize master key verification file."""
        if not os.path.exists(VERIFY_FILE):
            try:
                verify_token = fernet.encrypt(b"VERIFY_MASTER_KEY_2024")
                _atomic_write_file(VERIFY_FILE, verify_token, mode='wb')
            except Exception as e:
                raise ValueError(f"Failed to initialize master key: {str(e)}")
    
    def _verify_master_password(self, fernet: Fernet) -> bool:
        """Verify master password with rate limiting."""
        # Rate limiting
        current_time = time.time()
        if self.failed_attempts >= MAX_LOGIN_ATTEMPTS:
            if current_time - self.last_attempt_time < LOGIN_ATTEMPT_DELAY * (2 ** min(self.failed_attempts - MAX_LOGIN_ATTEMPTS, 5)):
                return False
        
        try:
            if not os.path.exists(VERIFY_FILE):
                return False
            
            with open(VERIFY_FILE, 'rb') as f:
                token = f.read()
            
            decrypted = fernet.decrypt(token)
            is_valid = decrypted == b"VERIFY_MASTER_KEY_2024"
            
            if not is_valid:
                self.failed_attempts += 1
                self.last_attempt_time = current_time
            
            return is_valid
            
        except Exception:
            self.failed_attempts += 1
            self.last_attempt_time = current_time
            return False

    def is_initialized(self) -> bool:
        """Return whether a vault has been initialized."""
        return os.path.exists(VERIFY_FILE)

    def reset_vault(self) -> Tuple[bool, str]:
        """Reset vault state and remove encrypted data so the user can set a new master password."""
        try:
            for path in [VERIFY_FILE, DATA_FILE, SALT_FILE]:
                if os.path.exists(path):
                    os.remove(path)
            self.lock()
            return True, "Vault has been reset. You can now create a new master password."
        except Exception as e:
            return False, f"Failed to reset vault: {str(e)}"

    def _validate_input(self, text: str, field_name: str, min_length: int = 1, max_length: int = 256) -> str:
        """Validate and sanitize user input."""
        if not text:
            raise ValueError(f"{field_name} cannot be empty")
        text = text.strip()
        if len(text) < min_length or len(text) > max_length:
            raise ValueError(f"{field_name} must be between {min_length} and {max_length} characters")
        # Prevent path traversal and other injection attacks
        if any(char in text for char in ['/', '\\', '..', '\x00']):
            raise ValueError(f"{field_name} contains invalid characters")
        return text
    
    def load_data(self) -> Dict:
        """Load and verify encrypted vault data with integrity check."""
        if not self.hmac_key:
            raise ValueError("Vault is locked")
        
        if not os.path.exists(DATA_FILE):
            return {}
        
        try:
            with open(DATA_FILE, 'rb') as f:
                content = f.read()
            
            # Verify HMAC if data exists
            if len(content) > 0:
                try:
                    data_json = json.loads(content)
                    if 'data' in data_json and 'hmac' in data_json:
                        if not verify_hmac(self.hmac_key, data_json['data'].encode('utf-8'), bytes.fromhex(data_json['hmac'])):
                            raise ValueError("Data integrity check failed - vault may be tampered with!")
                        return json.loads(data_json['data'])
                except (json.JSONDecodeError, ValueError, KeyError) as e:
                    raise ValueError(f"Vault file corrupted or tampered: {str(e)}")
            
            return {}
        except Exception as e:
            raise ValueError(f"Failed to load vault: {str(e)}")
    
    def save_data(self, data: Dict) -> None:
        """Save encrypted vault data with integrity protection."""
        if not self.hmac_key:
            raise ValueError("Vault is locked")
        
        try:
            # Serialize data
            data_json_str = json.dumps(data, indent=2)
            data_bytes = data_json_str.encode('utf-8')
            
            # Compute HMAC for integrity
            mac = compute_hmac(self.hmac_key, data_bytes)
            
            # Create structure with data and HMAC
            vault_structure = {
                'data': data_json_str,
                'hmac': mac.hex()
            }
            
            # Atomic write
            vault_json = json.dumps(vault_structure, indent=2).encode('utf-8')
            _atomic_write_file(DATA_FILE, vault_json, mode='wb')
            
        except Exception as e:
            raise ValueError(f"Failed to save vault: {str(e)}")
    
    def add_credential(self, site: str, username: str, password: str) -> Tuple[bool, str]:
        """Add new credentials. Returns (success, message)"""
        if not self.fernet:
            return False, "Vault is locked"
        
        try:
            site = self._validate_input(site, "Site name", min_length=1, max_length=128)
            username = self._validate_input(username, "Username", min_length=1, max_length=256)
            
            if not password or len(password) < 1:
                raise ValueError("Password cannot be empty")
            
            # Encrypt both username and password
            encrypted_username = self.fernet.encrypt(username.encode('utf-8')).decode('utf-8')
            encrypted_password = self.fernet.encrypt(password.encode('utf-8')).decode('utf-8')
            
            # Clear password from memory (best effort)
            secure_delete(password.encode('utf-8'))
            
            data = self.load_data()
            data[site] = {
                "username": encrypted_username,
                "password": encrypted_password
            }
            self.save_data(data)
            return True, "Credentials saved successfully"
            
        except ValueError as e:
            return False, str(e)
        except Exception as e:
            return False, f"Failed to add credentials: {str(e)}"
    
    def get_credential(self, site: str) -> Tuple[bool, Optional[Dict[str, str]], str]:
        """Get credentials for a site. Returns (success, credentials_dict, message)"""
        if not self.fernet:
            return False, None, "Vault is locked"
        
        try:
            site = self._validate_input(site, "Site name", min_length=1, max_length=128)
            data = self.load_data()
            
            if site not in data:
                return False, None, f"No credentials found for site: {site}"
            
            entry = data[site]
            try:
                decrypted_username = self.fernet.decrypt(entry['username'].encode('utf-8')).decode('utf-8')
                decrypted_password = self.fernet.decrypt(entry['password'].encode('utf-8')).decode('utf-8')
                
                return True, {
                    'username': decrypted_username,
                    'password': decrypted_password
                }, "Credentials retrieved successfully"
                
            except Exception as e:
                return False, None, f"Failed to decrypt credentials: {str(e)}"
                
        except ValueError as e:
            return False, None, str(e)
        except Exception as e:
            return False, None, f"Failed to retrieve credentials: {str(e)}"
    
    def delete_credential(self, site: str) -> Tuple[bool, str]:
        """Delete credentials for a site. Returns (success, message)"""
        if not self.fernet:
            return False, "Vault is locked"
        
        try:
            site = self._validate_input(site, "Site name", min_length=1, max_length=128)
            data = self.load_data()
            
            if site not in data:
                return False, f"No credentials found for site: {site}"
            
            del data[site]
            self.save_data(data)
            return True, f"Credentials for {site} deleted successfully"
            
        except ValueError as e:
            return False, str(e)
        except Exception as e:
            return False, f"Failed to delete credentials: {str(e)}"
    
    def list_sites(self) -> Tuple[bool, list, str]:
        """List all stored sites. Returns (success, sites_list, message)"""
        if not self.hmac_key:
            return False, [], "Vault is locked"
        
        try:
            data = self.load_data()
            sites = sorted(data.keys())
            return True, sites, f"Found {len(sites)} site(s)"
        except Exception as e:
            return False, [], f"Failed to list sites: {str(e)}"
    
    def export_vault(self, export_path: str) -> Tuple[bool, str]:
        """Export vault to JSON file (encrypted data). Returns (success, message)"""
        if not self.hmac_key:
            return False, "Vault is locked"
        
        try:
            data = self.load_data()
            with open(export_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
            return True, f"Vault exported to {export_path}"
        except Exception as e:
            return False, f"Failed to export vault: {str(e)}"
    
    def import_vault(self, import_path: str) -> Tuple[bool, str]:
        """Import vault from JSON file. Returns (success, message)"""
        if not self.hmac_key:
            return False, "Vault is locked"
        
        try:
            with open(import_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            self.save_data(data)
            return True, f"Vault imported from {import_path}"
        except Exception as e:
            return False, f"Failed to import vault: {str(e)}"

