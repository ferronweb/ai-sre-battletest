use axum::{
    Router,
    extract::{Path, Query},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use axum::body::Body;
use tokio_stream::StreamExt;
use rand::Rng;
use rand::distr::{Bernoulli, Distribution, Uniform};
use serde::Deserialize;
use std::time::{Duration, Instant};
use tokio::time::sleep;
use tokio::time::interval;

fn rng() -> rand::rngs::ThreadRng {
    rand::rng()
}

fn gen_bool(p: f64) -> bool {
    Bernoulli::new(p.clamp(0.0, 1.0))
        .map(|d| d.sample(&mut rng()))
        .unwrap_or(false)
}

#[derive(Deserialize)]
struct SlowParams {
    jitter: Option<u64>,
}

#[derive(Deserialize)]
struct ErrorParams {
    pct: Option<f64>,
    code: Option<u16>,
}

#[derive(Deserialize)]
struct RaceParams {
    delay_ms: Option<u64>,
}

fn env_dur(key: &str, default_ms: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default_ms)
}

fn env_f64(key: &str, default: f64) -> f64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_u16(key: &str, default: u16) -> u16 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn env_bool(key: &str) -> Option<bool> {
    std::env::var(key).ok().map(|v| {
        v.eq_ignore_ascii_case("true") || v.eq_ignore_ascii_case("1") || v == "yes"
    })
}

async fn maybe_inject_latency() {
    let lat = env_dur("LATENCY_MS", 0);
    if lat > 0 {
        sleep(Duration::from_millis(lat)).await;
    }
}

async fn maybe_inject_error() -> Option<StatusCode> {
    let pct = env_f64("ERROR_PCT", 0.0);
    if pct > 0.0 && gen_bool(pct.clamp(0.0, 1.0)) {
        let code = env_u16("ERROR_CODE", 500);
        return Some(StatusCode::from_u16(code).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR));
    }
    None
}

async fn handle_root() -> impl IntoResponse {
    maybe_inject_latency().await;
    if let Some(code) = maybe_inject_error().await {
        return (code, "Error".to_string());
    }
    (StatusCode::OK, "Hello, World!".to_string())
}

async fn handle_health() -> StatusCode {
    match env_bool("HEALTHY") {
        Some(false) => StatusCode::SERVICE_UNAVAILABLE,
        _ => StatusCode::OK,
    }
}

async fn handle_slow(
    Path(ms): Path<u64>,
    Query(params): Query<SlowParams>,
) -> (StatusCode, String) {
    maybe_inject_latency().await;
    if let Some(code) = maybe_inject_error().await {
        return (code, "Error".to_string());
    }
    let jitter = params.jitter.unwrap_or(0);
    let delay = if jitter > 0 {
        let j: u64 = Uniform::new(0u64, jitter.saturating_add(1)).unwrap().sample(&mut rng());
        ms + j
    } else {
        ms
    };
    sleep(Duration::from_millis(delay)).await;
    (StatusCode::OK, format!("Slept for {}ms", delay))
}

async fn handle_echo(body: axum::body::Bytes) -> (StatusCode, axum::body::Bytes) {
    maybe_inject_latency().await;
    if let Some(code) = maybe_inject_error().await {
        let msg = format!("Error {}", code.as_u16());
        return (code, axum::body::Bytes::from(msg));
    }
    (StatusCode::OK, body)
}

async fn handle_large(Path(bytes): Path<u64>) -> impl IntoResponse {
    maybe_inject_latency().await;
    let size = bytes.min(10_000_000);
    let mut data = vec![0u8; size as usize];
    rng().fill_bytes(&mut data[..]);

    let corrupt_pct = env_f64("CORRUPT_RESPONSE_PCT", 0.0);
    if corrupt_pct > 0.0 && gen_bool(corrupt_pct.clamp(0.0, 1.0)) {
        let flip_pct = env_f64("CORRUPT_FLIP_PCT", 0.001);
        for byte in data.iter_mut() {
            if gen_bool(flip_pct.clamp(0.0, 1.0)) {
                *byte ^= 0xff;
            }
        }
    }

    if env_bool("MISMATCH_CONTENT_LENGTH").unwrap_or(false) {
        let wrong_size = (size as f64 * env_f64("MISMATCH_FACTOR", 0.9)) as u64;
        let headers = [(header::CONTENT_LENGTH, wrong_size.to_string())];
        return (headers, data);
    }

    let headers = [(header::CONTENT_LENGTH, size.to_string())];
    (headers, data)
}

async fn handle_headers(headers: HeaderMap) -> String {
    maybe_inject_latency().await;
    let mut out = String::from("=== Request Headers ===\n");
    for (name, value) in headers.iter() {
        if let Ok(v) = value.to_str() {
            out.push_str(&format!("{}: {}\n", name, v));
        }
    }
    out
}

async fn handle_error(Query(params): Query<ErrorParams>) -> (StatusCode, String) {
    maybe_inject_latency().await;
    let pct = params.pct.unwrap_or(env_f64("ERROR_PCT", 0.5)).clamp(0.0, 1.0);
    let code = params
        .code
        .unwrap_or(env_u16("ERROR_CODE", 500));
    if gen_bool(pct) {
        (
            StatusCode::from_u16(code).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            format!("Error {}", code),
        )
    } else {
        (StatusCode::OK, "OK".to_string())
    }
}

// /race tests thundering herd — all concurrent requests hit a shared lock
// /race/{delay_ms} with optional delay before releasing
async fn handle_race(Query(params): Query<RaceParams>) -> String {
    maybe_inject_latency().await;
    let delay = params.delay_ms.unwrap_or(500);
    sleep(Duration::from_millis(delay)).await;
    format!("Race complete after {}ms", delay)
}

async fn handle_trace(headers: HeaderMap) -> String {
    let traceparent = headers
        .get("traceparent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("(none)");
    let tracestate = headers
        .get("tracestate")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("(none)");

    let corrupt_pct = env_f64("TRACE_CORRUPT_PCT", 0.0);
    let response_trace = if corrupt_pct > 0.0 && gen_bool(corrupt_pct.clamp(0.0, 1.0))
    {
        "00-00000000000000000000000000000000-0000000000000000-00"
    } else {
        traceparent
    };

    format!(
        "traceparent: {}\ntracestate: {}\nresponse_trace: {}\n",
        traceparent, tracestate, response_trace
    )
}

async fn handle_stream(Path(ms): Path<u64>) -> impl IntoResponse {
    let (tx, rx) = tokio::sync::mpsc::channel::<Result<String, axum::Error>>(16);

    let deadline = Instant::now() + Duration::from_millis(ms);
    tokio::spawn(async move {
        let mut interval = interval(Duration::from_millis(500));
        while Instant::now() < deadline {
            interval.tick().await;
            maybe_inject_latency().await;
            if let Some(code) = maybe_inject_error().await {
                let _ = tx.send(Ok(format!("ERROR {}\n", code))).await;
                break;
            }
            let _ = tx.send(Ok(format!("heartbeat {}\n", Instant::now().elapsed().as_millis()))).await;
        }
    });

    let stream = tokio_stream::wrappers::ReceiverStream::new(rx).map(|r| {
        r.map(|s| s.into_bytes())
    });

    Response::builder()
        .header(header::CONTENT_TYPE, "text/plain")
        .header(header::TRANSFER_ENCODING, "chunked")
        .body(Body::from_stream(stream))
        .unwrap()
}

#[tokio::main]
async fn main() {
    if let Ok(mut sigterm) =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
    {
        tokio::spawn(async move {
            sigterm.recv().await;
            std::process::exit(0);
        });
    }

    let app = Router::new()
        .route("/", get(handle_root))
        .route("/health", get(handle_health))
        .route("/slow/{ms}", get(handle_slow))
        .route("/echo", post(handle_echo))
        .route("/large/{bytes}", get(handle_large))
        .route("/headers", get(handle_headers))
        .route("/error", get(handle_error))
        .route("/race", get(handle_race))
        .route("/trace", get(handle_trace))
        .route("/stream/{ms}", get(handle_stream));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    eprintln!("backend listening on 0.0.0.0:3000");
    axum::serve(listener, app).await.unwrap();
}
