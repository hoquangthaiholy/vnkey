use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::error::Error;

use crate::db;

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

async fn get_or_create_vnkey_folder(client: &Client, access_token: &str) -> Result<String, String> {
    let query = "name='VNKey' and mimeType='application/vnd.google-apps.folder' and trashed=false";
    let url = format!("https://www.googleapis.com/drive/v3/files?q={}", urlencoding::encode(query));
    let res = client.get(&url).bearer_auth(access_token).send().await.map_err(|e| e.to_string())?;
    
    if res.status().is_success() {
        let list: DriveFileList = res.json().await.map_err(|e| e.to_string())?;
        if let Some(folder) = list.files.first() {
            return Ok(folder.id.clone());
        }
    }
    
    // Create folder
    let url = "https://www.googleapis.com/drive/v3/files";
    let metadata = serde_json::json!({
        "name": "VNKey",
        "mimeType": "application/vnd.google-apps.folder"
    });
    
    let res = client.post(url).bearer_auth(access_token).json(&metadata).send().await.map_err(|e| e.to_string())?;
    if res.status().is_success() {
        let folder: DriveFile = res.json().await.map_err(|e| e.to_string())?;
        Ok(folder.id)
    } else {
        Err("Không thể tạo thư mục VNKey trên Google Drive".into())
    }
}

async fn find_file_id_in_folder(client: &Client, access_token: &str, folder_id: &str, file_name: &str) -> Result<Option<String>, String> {
    let query = format!("name='{}' and '{}' in parents and trashed=false", file_name, folder_id);
    let url = format!("https://www.googleapis.com/drive/v3/files?q={}", urlencoding::encode(&query));
    let res = client.get(&url).bearer_auth(access_token).send().await.map_err(|e| e.to_string())?;
    if res.status().is_success() {
        let list: DriveFileList = res.json().await.map_err(|e| e.to_string())?;
        if let Some(file) = list.files.first() {
            return Ok(Some(file.id.clone()));
        }
    } else {
        return Err(format!("Lỗi xác thực hoặc tìm kiếm file ({}): {}", res.status(), res.text().await.unwrap_or_default()));
    }
    Ok(None)
}

async fn upload_file(client: &Client, access_token: &str, folder_id: &str, file_name: &str, payload: Vec<u8>) -> Result<(), String> {
    let existing_id = find_file_id_in_folder(client, access_token, folder_id, file_name).await?;
    if let Some(file_id) = existing_id {
        let url = format!("https://www.googleapis.com/upload/drive/v3/files/{}?uploadType=media", file_id);
        let res = client.patch(&url).bearer_auth(access_token).header("Content-Type", "application/octet-stream").body(payload).send().await.map_err(|e| e.to_string())?;
        if !res.status().is_success() {
            return Err(format!("Lỗi cập nhật file ({}): {}", res.status(), res.text().await.unwrap_or_default()));
        }
    } else {
        let url = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart";
        let metadata = serde_json::json!({
            "name": file_name,
            "parents": [folder_id]
        });
        
        let metadata_part = reqwest::multipart::Part::text(metadata.to_string())
            .mime_str("application/json").unwrap();
        let file_part = reqwest::multipart::Part::bytes(payload)
            .mime_str("application/octet-stream").unwrap();
            
        let form = reqwest::multipart::Form::new()
            .part("metadata", metadata_part)
            .part("file", file_part);
            
        let res = client.post(url).bearer_auth(access_token).multipart(form).send().await.map_err(|e| e.to_string())?;
        if !res.status().is_success() {
            return Err(format!("Lỗi tải lên ({}): {}", res.status(), res.text().await.unwrap_or_default()));
        }
    }
    Ok(())
}

async fn download_file(client: &Client, access_token: &str, folder_id: &str, file_name: &str) -> Result<Option<Vec<u8>>, String> {
    let existing_id = find_file_id_in_folder(client, access_token, folder_id, file_name).await?;
    if let Some(file_id) = existing_id {
        let url = format!("https://www.googleapis.com/drive/v3/files/{}?alt=media", file_id);
        let res = client.get(&url).bearer_auth(access_token).send().await.map_err(|e| e.to_string())?;
        if res.status().is_success() {
            let bytes = res.bytes().await.map_err(|e| e.to_string())?;
            return Ok(Some(bytes.to_vec()));
        } else {
            return Err(format!("Lỗi tải xuống ({}): {}", res.status(), res.text().await.unwrap_or_default()));
        }
    }
    Ok(None)
}

pub async fn upload_sync_data_gdrive(sync_password: &str) -> Result<(), String> {
    let access_token = get_valid_access_token().await?;
    let client = Client::new();
    let folder_id = get_or_create_vnkey_folder(&client, &access_token).await?;
    
    let payloads = crate::cloud_sync::get_sync_payloads(sync_password).map_err(|e| e.to_string())?;
    
    if let Some(data) = payloads.settings {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_settings.enc", data).await?;
    }
    if let Some(data) = payloads.vietnamese_dict {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_vietnamese_dict.enc", data).await?;
    }
    if let Some(data) = payloads.english_dict {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_english_dict.enc", data).await?;
    }
    if let Some(data) = payloads.programming_keywords {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_programming_keywords.enc", data).await?;
    }
    if let Some(data) = payloads.macros {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_macros.enc", data).await?;
    }
    if let Some(data) = payloads.clipboard {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_clipboard.enc", data).await?;
    }
    if let Some(data) = payloads.app_configs {
        upload_file(&client, &access_token, &folder_id, "vnkey_sync_app_configs.enc", data).await?;
    }
    
    Ok(())
}

pub async fn download_sync_data_gdrive(sync_password: &str) -> Result<(), String> {
    let access_token = get_valid_access_token().await?;
    let client = Client::new();
    let folder_id = get_or_create_vnkey_folder(&client, &access_token).await?;
    
    let settings = download_file(&client, &access_token, &folder_id, "vnkey_sync_settings.enc").await?;
    let vietnamese_dict = download_file(&client, &access_token, &folder_id, "vnkey_sync_vietnamese_dict.enc").await?;
    let english_dict = download_file(&client, &access_token, &folder_id, "vnkey_sync_english_dict.enc").await?;
    let programming_keywords = download_file(&client, &access_token, &folder_id, "vnkey_sync_programming_keywords.enc").await?;
    let macros = download_file(&client, &access_token, &folder_id, "vnkey_sync_macros.enc").await?;
    let clipboard = download_file(&client, &access_token, &folder_id, "vnkey_sync_clipboard.enc").await?;
    let app_configs = download_file(&client, &access_token, &folder_id, "vnkey_sync_app_configs.enc").await?;
    
    crate::cloud_sync::apply_sync_payloads(
        settings.as_deref(),
        vietnamese_dict.as_deref(),
        english_dict.as_deref(),
        programming_keywords.as_deref(),
        macros.as_deref(),
        clipboard.as_deref(),
        app_configs.as_deref(),
        sync_password
    ).map_err(|e| e.to_string())?;
    
    Ok(())
}

