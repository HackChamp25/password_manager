from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.paths import ensure_app_directories

ensure_app_directories()
from app.core.vault import VaultManager

app = FastAPI(title="Password Manager API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_methods=["*"],
    allow_headers=["*"],
)

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
    raise HTTPException(status_code=500, detail=message)


@app.get("/credential/{site}")
async def get_credential(site: str):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, cred, message = vault.get_credential(site)
    if success:
        return cred
    raise HTTPException(status_code=404, detail=message)


@app.post("/credential")
async def add_credential(request: AddCredentialRequest):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, message = vault.add_credential(request.site, request.username, request.password)
    if success:
        return {"message": message}
    raise HTTPException(status_code=400, detail=message)


@app.get("/credentials")
async def get_all_credentials():
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, sites, message = vault.list_sites()
    if not success:
        raise HTTPException(status_code=500, detail=message)
    credentials = {}
    for s in sites:
        ok, cred, _ = vault.get_credential(s)
        if ok and cred is not None:
            credentials[s] = cred
    return credentials


@app.put("/credential/{old_site}")
async def update_credential(old_site: str, request: AddCredentialRequest):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success1, msg1 = vault.delete_credential(old_site)
    if not success1:
        raise HTTPException(status_code=404, detail=msg1)
    success2, msg2 = vault.add_credential(request.site, request.username, request.password)
    if success2:
        return {"message": msg2}
    raise HTTPException(status_code=400, detail=msg2)


@app.delete("/credential/{site}")
async def delete_credential_endpoint(site: str):
    if not vault.fernet:
        raise HTTPException(status_code=401, detail="Vault is locked")
    success, message = vault.delete_credential(site)
    if success:
        return {"message": message}
    raise HTTPException(status_code=404, detail=message)


@app.get("/initialized")
async def is_initialized():
    return {"initialized": vault.is_initialized()}


@app.post("/reset")
async def reset_vault():
    success, message = vault.reset_vault()
    if success:
        return {"message": message}
    raise HTTPException(status_code=500, detail=message)
