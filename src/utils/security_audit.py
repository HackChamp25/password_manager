"""Security audit utilities for password vault"""
from typing import Dict, List, Tuple
from .password_generator import PasswordGenerator


class SecurityAuditor:
    """Audit password vault for security issues"""
    
    @staticmethod
    def audit_passwords(vault_data: Dict, fernet) -> Dict:
        """
        Audit all passwords in vault for security issues.
        
        Returns:
            Dictionary with audit results
        """
        issues = {
            'weak_passwords': [],
            'duplicate_passwords': [],
            'duplicate_usernames': [],
            'no_password': [],
            'total_credentials': len(vault_data),
            'security_score': 100
        }
        
        password_map = {}  # password -> [sites]
        username_map = {}  # username -> [sites]
        
        for site, entry in vault_data.items():
            try:
                # Decrypt password
                encrypted_password = entry.get('password', '')
                if not encrypted_password:
                    issues['no_password'].append(site)
                    continue
                
                password = fernet.decrypt(encrypted_password.encode('utf-8')).decode('utf-8')
                
                # Check password strength
                strength = PasswordGenerator.check_strength(password)
                if strength['score'] < 40:
                    issues['weak_passwords'].append({
                        'site': site,
                        'score': strength['score'],
                        'strength': strength['strength']
                    })
                
                # Track duplicates
                if password in password_map:
                    password_map[password].append(site)
                else:
                    password_map[password] = [site]
                
                # Decrypt and track usernames
                encrypted_username = entry.get('username', '')
                if encrypted_username:
                    username = fernet.decrypt(encrypted_username.encode('utf-8')).decode('utf-8')
                    if username in username_map:
                        username_map[username].append(site)
                    else:
                        username_map[username] = [site]
                        
            except Exception:
                # Skip if decryption fails
                continue
        
        # Find duplicate passwords
        for password, sites in password_map.items():
            if len(sites) > 1:
                issues['duplicate_passwords'].append({
                    'sites': sites,
                    'count': len(sites)
                })
        
        # Find duplicate usernames
        for username, sites in username_map.items():
            if len(sites) > 1:
                issues['duplicate_usernames'].append({
                    'username': username,
                    'sites': sites,
                    'count': len(sites)
                })
        
        # Calculate security score
        score = 100
        score -= len(issues['weak_passwords']) * 5
        score -= len(issues['duplicate_passwords']) * 10
        score -= len(issues['no_password']) * 15
        issues['security_score'] = max(0, score)
        
        return issues

