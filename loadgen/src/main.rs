use rand::Rng;
use std::{
    collections::BTreeMap,
    env,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};
use tokio::time::sleep;

struct Config {
    target_url: String,
    rate: f64,
    duration_secs: u64,
    timeout_secs: u64,
    concurrency: usize,
    method: String,
    path: String,
    body_size: usize,
    headers: Vec<(String, String)>,
    validate_content_length: bool,
    validate_status: u16,
    output_json: bool,
}

fn env_str(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

fn env_usize(key: &str, default: usize) -> usize {
    env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_u64(key: &str, default: u64) -> u64 {
    env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_f64(key: &str, default: f64) -> f64 {
    env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
}

fn env_bool(key: &str) -> bool {
    env::var(key).ok().map_or(false, |v| {
        v.eq_ignore_ascii_case("true") || v.eq_ignore_ascii_case("1") || v == "yes"
    })
}

fn parse_headers(s: &str) -> Vec<(String, String)> {
    s.split(',')
        .filter_map(|pair| {
            let mut parts = pair.splitn(2, ':');
            match (parts.next(), parts.next()) {
                (Some(k), Some(v)) => Some((k.trim().to_string(), v.trim().to_string())),
                _ => None,
            }
        })
        .collect()
}

fn load_config() -> Config {
    Config {
        target_url: env_str("TARGET_URL", "http://proxy:80"),
        rate: env_f64("RATE", 10.0),
        duration_secs: env_u64("DURATION_SECS", 30),
        timeout_secs: env_u64("TIMEOUT_SECS", 30),
        concurrency: env_usize("CONCURRENCY", 5),
        method: env_str("METHOD", "GET"),
        path: env_str("REQUEST_PATH", "/"),
        body_size: env_usize("BODY_SIZE", 0),
        headers: parse_headers(&env_str("HEADERS", "")),
        validate_content_length: env_bool("VALIDATE_CONTENT_LENGTH"),
        validate_status: env_u64("VALIDATE_STATUS", 200) as u16,
        output_json: env_bool("OUTPUT_JSON"),
    }
}

struct Stats {
    total: AtomicU64,
    success: AtomicU64,
    failed: AtomicU64,
    status_mismatch: AtomicU64,
    body_mismatch: AtomicU64,
    total_latency_ms: AtomicU64,
    max_latency_ms: AtomicU64,
}

impl Stats {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            total: AtomicU64::new(0),
            success: AtomicU64::new(0),
            failed: AtomicU64::new(0),
            status_mismatch: AtomicU64::new(0),
            body_mismatch: AtomicU64::new(0),
            total_latency_ms: AtomicU64::new(0),
            max_latency_ms: AtomicU64::new(0),
        })
    }
}

fn generate_body(size: usize) -> Vec<u8> {
    let mut body = vec![0u8; size];
    if size > 0 {
        rand::rng().fill_bytes(&mut body[..]);
    }
    body
}

async fn worker(
    config: Arc<Config>,
    stats: Arc<Stats>,
    client: reqwest::Client,
    shutdown: Arc<tokio::sync::Notify>,
) {
    loop {
        tokio::select! {
            _ = shutdown.notified() => break,
            _ = sleep(Duration::from_millis(
                (1000.0 / config.rate.max(1.0)) as u64
            )) => {}
        }

        let url = format!("{}{}", config.target_url.trim_end_matches('/'), config.path);
        let start = Instant::now();

        let mut req = match config.method.to_uppercase().as_str() {
            "POST" => {
                let body = generate_body(config.body_size);
                client.post(&url).body(body)
            }
            "PUT" => {
                let body = generate_body(config.body_size);
                client.put(&url).body(body)
            }
            _ => client.get(&url),
        };

        for (k, v) in &config.headers {
            req = req.header(k, v);
        }

        let result = req.send().await;
        stats.total.fetch_add(1, Ordering::Relaxed);

        match result {
            Ok(resp) => {
                let status = resp.status().as_u16();
                let expected = config.validate_status;

                if status == expected {
                    stats.success.fetch_add(1, Ordering::Relaxed);
                } else {
                    stats.status_mismatch.fetch_add(1, Ordering::Relaxed);
                }

                if config.validate_content_length {
                    let content_length = resp
                        .headers()
                        .get(reqwest::header::CONTENT_LENGTH)
                        .and_then(|v| v.to_str().ok())
                        .and_then(|v| v.parse::<usize>().ok());

                    let body_bytes = resp.bytes().await.unwrap_or_default();
                    if let Some(expected_len) = content_length {
                        if body_bytes.len() != expected_len {
                            stats
                                .body_mismatch
                                .fetch_add(1, Ordering::Relaxed);
                        }
                    }
                }

                let lat = start.elapsed().as_millis() as u64;
                stats.total_latency_ms.fetch_add(lat, Ordering::Relaxed);
                let mut prev = stats.max_latency_ms.load(Ordering::Relaxed);
                while lat > prev {
                    match stats.max_latency_ms.compare_exchange(
                        prev,
                        lat,
                        Ordering::Relaxed,
                        Ordering::Relaxed,
                    ) {
                        Ok(_) => break,
                        Err(current) => prev = current,
                    }
                }
            }
            Err(_) => {
                stats.failed.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let config = Arc::new(load_config());
    let stats = Stats::new();
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(config.timeout_secs))
        .build()
        .unwrap();

    let shutdown = Arc::new(tokio::sync::Notify::new());

    let config_clone = config.clone();
    let stats_clone = stats.clone();
    let shutdown_clone = shutdown.clone();
    let workers: Vec<_> = (0..config.concurrency)
        .map(|_| {
            let c = config.clone();
            let s = stats.clone();
            let sh = shutdown.clone();
            let cl = client.clone();
            tokio::spawn(async move { worker(c, s, cl, sh).await })
        })
        .collect();

    sleep(Duration::from_secs(config.duration_secs)).await;
    shutdown_clone.notify_waiters();

    for w in workers {
        let _ = w.await;
    }

    let total = stats_clone.total.load(Ordering::Relaxed);
    let success = stats_clone.success.load(Ordering::Relaxed);
    let failed = stats_clone.failed.load(Ordering::Relaxed);
    let status_mismatch = stats_clone.status_mismatch.load(Ordering::Relaxed);
    let body_mismatch = stats_clone.body_mismatch.load(Ordering::Relaxed);
    let total_lat = stats_clone.total_latency_ms.load(Ordering::Relaxed);
    let max_lat = stats_clone.max_latency_ms.load(Ordering::Relaxed);
    let avg_lat = if total > 0 { total_lat / total } else { 0 };

    if config_clone.output_json {
        let mut map = BTreeMap::new();
        map.insert("total", total);
        map.insert("success", success);
        map.insert("failed", failed);
        map.insert("status_mismatch", status_mismatch);
        map.insert("body_mismatch", body_mismatch);
        map.insert("avg_latency_ms", avg_lat);
        map.insert("max_latency_ms", max_lat);
        map.insert("timeout_secs", config_clone.timeout_secs);
        println!("{}", serde_json::to_string(&map).unwrap());
    } else {
        println!("Requests: {}, Success: {}, Failed: {}, StatusMismatch: {}, BodyMismatch: {}, AvgLat: {}ms, MaxLat: {}ms",
            total, success, failed, status_mismatch, body_mismatch, avg_lat, max_lat);
    }
}
