use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::error::Error;

use crate::db;
use crate::cloud_sync::{get_sync_payload, apply_sync_payload};

const CLIENT_ID: Option<&str> = option_env!("GOOGLE_CLIENT_ID");
const CLIENT_SECRET: Option<&str> = option_env!("GOOGLE_CLIENT_SECRET");
const SCOPE: &str = "https://www.googleapis.com/auth/drive.file";

fn get_client_id() -> Result<&'static str, String> {
    CLIENT_ID.ok_or_else(|| "Google Client ID chưa được cấu hình khi biên dịch".to_string())
}

fn get_client_secret() -> Result<&'static str, String> {
    CLIENT_SECRET.ok_or_else(|| "Google Client Secret chưa được cấu hình khi biên dịch".to_string())
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct DeviceAuthResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_url: String,
    pub expires_in: i32,
    pub interval: i32,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct TokenResponse {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: i32,
    pub token_type: String,
}

pub async fn start_device_auth() -> Result<DeviceAuthResponse, Box<dyn Error>> {
    let client_id = get_client_id().map_err(|e| e.to_string())?;
    let client = Client::new();
    let res = client.post("https://oauth2.googleapis.com/device/code")
        .form(&[
            ("client_id", client_id),
            ("scope", SCOPE)
        ])
        .send()
        .await?;
        
    let status = res.status();
    let text = res.text().await?;
    
    if status.is_success() {
        let auth_res: DeviceAuthResponse = serde_json::from_str(&text)?;
        Ok(auth_res)
    } else {
        Err(format!("Lỗi cấu hình Google API ({}): {}", status, text).into())
    }
}

pub async fn poll_device_auth(device_code: &str) -> Result<TokenResponse, String> {
    let client_id = get_client_id()?;
    let client_secret = get_client_secret()?;
    let client = Client::new();
    let res = client.post("https://oauth2.googleapis.com/token")
        .form(&[
            ("client_id", client_id),
            ("client_secret", client_secret),
            ("device_code", device_code),
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
        ])
        .send()
        .await.map_err(|e| e.to_string())?;

    if res.status().is_success() {
        let text = res.text().await.map_err(|e| e.to_string())?;
        let token_res: TokenResponse = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        Ok(token_res)
    } else {
        let text = res.text().await.map_err(|e| e.to_string())?;
        Err(text) // This will often be {"error": "authorization_pending"}
    }
}

pub async fn refresh_access_token(refresh_token: &str) -> Result<String, String> {
    let client_id = get_client_id()?;
    let client_secret = get_client_secret()?;
    let client = Client::new();
    let res = client.post("https://oauth2.googleapis.com/token")
        .form(&[
            ("client_id", client_id),
            ("client_secret", client_secret),
            ("refresh_token", refresh_token),
            ("grant_type", "refresh_token"),
        ])
        .send()
        .await.map_err(|e| e.to_string())?;

    if res.status().is_success() {
        let text = res.text().await.map_err(|e| e.to_string())?;
        let token_res: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
        if let Some(access_token) = token_res.get("access_token").and_then(|t| t.as_str()) {
            return Ok(access_token.to_string());
        }
    }
    Err("Failed to refresh token".into())
}

async fn get_valid_access_token() -> Result<String, String> {
    let access_token = db::db_get_kv("gdriveAccessToken").unwrap_or_default();
    let refresh_token = db::db_get_kv("gdriveRefreshToken").unwrap_or_default();
    
    if access_token.is_empty() && refresh_token.is_empty() {
        return Err("Chưa đăng nhập Google Drive".into());
    }

    // Try to use the refresh token to get a fresh access token every time to avoid expiration issues.
    // Or we could try the access token first, and if it fails (401), we refresh it.
    // Let's just refresh it if we have a refresh token.
    if !refresh_token.is_empty() {
        if let Ok(new_access_token) = refresh_access_token(&refresh_token).await {
            db::db_set_kv("gdriveAccessToken", &new_access_token);
            return Ok(new_access_token);
        }
    }

    if !access_token.is_empty() {
        return Ok(access_token);
    }

    Err("Token không hợp lệ, vui lòng đăng nhập lại".into())
}

#[derive(Deserialize)]
struct DriveFileList {
    files: Vec<DriveFile>,
}

#[derive(Deserialize)]
struct DriveFile {
    id: String,
}

async fn find_file_id(client: &Client, access_token: &str, file_name: &str) -> Result<Option<String>, String> {
    let query = format!("name='{}' and trashed=false", file_name);
    let url = format!("https://www.googleapis.com/drive/v3/files?q={}", urlencoding::encode(&query));
    let res = client.get(&url)
        .bearer_auth(access_token)
        .send()
        .await.map_err(|e| e.to_string())?;
    
    if res.status().is_success() {
        let list: DriveFileList = res.json().await.map_err(|e| e.to_string())?;
        if let Some(file) = list.files.first() {
            return Ok(Some(file.id.clone()));
        }
    }
    Ok(None)
}

pub async fn upload_sync_data_gdrive(sync_password: &str) -> Result<(), String> {
    let access_token = get_valid_access_token().await?;
    let client = Client::new();
    let payload = get_sync_payload(sync_password).map_err(|e| e.to_string())?;
    
    let file_name = "vnkey_sync.dat";
    let existing_id = find_file_id(&client, &access_token, file_name).await?;

    if let Some(file_id) = existing_id {
        // Update existing file
        let url = format!("https://www.googleapis.com/upload/drive/v3/files/{}?uploadType=media", file_id);
        let res = client.patch(&url)
            .bearer_auth(&access_token)
            .header("Content-Type", "application/octet-stream")
            .body(payload)
            .send()
            .await.map_err(|e| e.to_string())?;
            
        if !res.status().is_success() {
            let error_text = res.text().await.unwrap_or_default();
            return Err(format!("Lỗi khi cập nhật file: {}", error_text));
        }
    } else {
        // Create new file
        let url = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart";
        let metadata = serde_json::json!({
            "name": file_name,
        });
        
        let metadata_part = reqwest::multipart::Part::text(metadata.to_string())
            .mime_str("application/json").unwrap();
        let file_part = reqwest::multipart::Part::bytes(payload)
            .mime_str("application/octet-stream").unwrap();
            
        let form = reqwest::multipart::Form::new()
            .part("metadata", metadata_part)
            .part("file", file_part);
            
        let res = client.post(url)
            .bearer_auth(&access_token)
            .multipart(form)
            .send()
            .await.map_err(|e| e.to_string())?;
            
        if !res.status().is_success() {
            let error_text = res.text().await.unwrap_or_default();
            return Err(format!("Lỗi khi tạo file mới: {}", error_text));
        }
    }
    
    Ok(())
}

pub async fn download_sync_data_gdrive(sync_password: &str) -> Result<(), String> {
    let access_token = get_valid_access_token().await?;
    let client = Client::new();
    let file_name = "vnkey_sync.dat";
    
    let existing_id = find_file_id(&client, &access_token, file_name).await?;
    if let Some(file_id) = existing_id {
        let url = format!("https://www.googleapis.com/drive/v3/files/{}?alt=media", file_id);
        let res = client.get(&url)
            .bearer_auth(&access_token)
            .send()
            .await.map_err(|e| e.to_string())?;
            
        if res.status().is_success() {
            let bytes = res.bytes().await.map_err(|e| e.to_string())?;
            apply_sync_payload(&bytes, sync_password).map_err(|e| e.to_string())?;
            Ok(())
        } else {
            Err("Không thể tải file từ Google Drive".into())
        }
    } else {
        Err("Không tìm thấy dữ liệu đồng bộ trên Google Drive".into())
    }
}
