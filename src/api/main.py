from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from src.core.vault import VaultManager

app = FastAPI(title="Password Manager API", version="1.0.0")

vault = VaultManager()

class LoginRequest(BaseModel):
    password: str

class AddCredentialRequest(BaseModel):
    site: str
    username: str
    password: str

@app.post("/login")
async def login(request: LoginRequest):
    success, message = vault.unlock(request.password)
    if success:
        return {"message": message}
    else:
        raise HTTPException(status_code=401, detail=message)

@app.post("/logout")
async def logout():
    vault.lock()
    return {"message": "Vault locked"}

@app.get("/sites")
async def list_sites():
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, sites, message = vault.list_sites()
    if success:
        return {"sites": sites}
    else:
        raise HTTPException(status_code=500, detail=message)

@app.get("/credential/{site}")
async def get_credential(site: str):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, cred, message = vault.get_credential(site)
    if success:
        return cred
    else:
        raise HTTPException(status_code=404, detail=message)

@app.post("/credential")
async def add_credential(request: AddCredentialRequest):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, message = vault.add_credential(request.site, request.username, request.password)
    if success:
        return {"message": message}
    else:
        raise HTTPException(status_code=400, detail=message)

@app.get("/credentials")
async def get_all_credentials():
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, sites, message = vault.list_sites()
    if not success:
        raise HTTPException(status_code=500, detail=message)
    credentials = {}
    for site in sites:
        success2, cred, msg = vault.get_credential(site)
        if success2:
            credentials[site] = cred
    return credentials

@app.put("/credential/{old_site}")
async def update_credential(old_site: str, request: AddCredentialRequest):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    # Delete old
    success1, msg1 = vault.delete_credential(old_site)
    if not success1:
        raise HTTPException(status_code=404, detail=msg1)
    # Add new
    success2, msg2 = vault.add_credential(request.site, request.username, request.password)
    if success2:
        return {"message": msg2}
    else:
        raise HTTPException(status_code=400, detail=msg2)

@app.get("/initialized")
async def is_initialized():
    return {"initialized": vault.is_initialized()}

@app.post("/reset")
async def reset_vault():
    success, message = vault.reset_vault()
    if success:
        return {"message": message}
    else:
        raise HTTPException(status_code=500, detail=message)