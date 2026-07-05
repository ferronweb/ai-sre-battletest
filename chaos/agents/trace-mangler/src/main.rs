use rand::RngExt;
use rand::distr::{Bernoulli, Distribution};
use std::env;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

fn gen_bool(p: f64) -> bool {
    Bernoulli::new(p.clamp(0.0, 1.0))
        .map(|d| d.sample(&mut rand::rng()))
        .unwrap_or(false)
}

#[tokio::main]
async fn main() {
    let listen_addr = env::var("LISTEN_ADDR").unwrap_or_else(|_| "0.0.0.0:3001".to_string());
    let corrupt_pct: f64 = env::var("CORRUPT_PCT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0);

    let listener = TcpListener::bind(&listen_addr).await.unwrap();
    eprintln!(
        "trace-mangler listening on {} (corrupt_pct={})",
        listen_addr, corrupt_pct
    );

    loop {
        let (client, _) = listener.accept().await.unwrap();
        tokio::spawn(async move {
            handle_connection(client, corrupt_pct).await;
        });
    }
}

async fn handle_connection(mut client: TcpStream, corrupt_pct: f64) {
    let mut buf = vec![0u8; 65536];
    let n = client.read(&mut buf).await.unwrap_or(0);
    if n == 0 {
        return;
    }

    let request = String::from_utf8_lossy(&buf[..n]);
    let mut mangled = request.to_string();

    if mangled.contains("traceparent:") && gen_bool(corrupt_pct) {
        if let Some(start) = mangled.find("traceparent: ") {
            if let Some(end) = mangled[start..].find('\n') {
                let before = &mangled[..start];
                let after = &mangled[start + end..];
                mangled = format!(
                    "{}traceparent: 00-00000000000000000000000000000000-0000000000000000-00{}",
                    before, after
                );
                eprintln!("trace-mangler: corrupted traceparent header");
            }
        }
    }

    let upstreams = ["backend-1:3000", "backend-2:3000", "backend-3:3000"];
    let idx: usize = rand::rng().random_range(0..upstreams.len());
    let upstream = upstreams[idx];

    let backend = TcpStream::connect(upstream).await;
    match backend {
        Ok(mut conn) => {
            if let Err(e) = conn.write_all(mangled.as_bytes()).await {
                eprintln!("trace-mangler: write error: {}", e);
                return;
            }
            let mut resp = vec![0u8; 65536];
            let n = conn.read(&mut resp).await.unwrap_or(0);
            if n > 0 {
                let _ = client.write_all(&resp[..n]).await;
            }
        }
        Err(e) => {
            eprintln!("trace-mangler: connect error to {}: {}", upstream, e);
            let _ = client
                .write_all(b"HTTP/1.1 502 Bad Gateway\r\n\r\nBad Gateway")
                .await;
        }
    }
}
