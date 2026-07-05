use axum::{
    http::{HeaderMap, StatusCode},
    routing::get,
    Router,
};
use rand::Rng;
use std::env;

fn env_f64(key: &str, default: f64) -> f64 {
    env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_bool(key: &str) -> bool {
    env::var(key)
        .ok()
        .map(|v| v.eq_ignore_ascii_case("true") || v.eq_ignore_ascii_case("1") || v == "yes")
        .unwrap_or(false)
}

async fn health() -> StatusCode {
    if env_bool("HEALTHY") {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    }
}

async fn auth(headers: HeaderMap) -> (StatusCode, HeaderMap) {
    let fail_pct = env_f64("AUTH_FAIL_PCT", 0.0);
    if fail_pct > 0.0 && rand::thread_rng().gen_bool(fail_pct.clamp(0.0, 1.0)) {
        return (StatusCode::UNAUTHORIZED, HeaderMap::new());
    }

    let client_ip = headers
        .get("X-Forwarded-For")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    let mut resp_headers = HeaderMap::new();
    resp_headers.insert("X-Auth-User", client_ip.parse().unwrap());
    resp_headers.insert("X-Auth-Status", "allowed".parse().unwrap());

    (StatusCode::OK, resp_headers)
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/health", get(health))
        .route("/auth", get(auth));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .unwrap();
    eprintln!("auth-backend listening on 0.0.0.0:8080");
    axum::serve(listener, app).await.unwrap();
}
