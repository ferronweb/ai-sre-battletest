use opentelemetry::trace::{Tracer, Span, SpanKind, TracerProvider};
use opentelemetry::{KeyValue};
use opentelemetry_sdk::trace::{SdkTracerProvider, BatchSpanProcessor};
use opentelemetry_sdk::Resource;
use opentelemetry_otlp::WithExportConfig;
use rand::RngExt;
use std::env;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Notify;
use tokio::time::sleep;
use uuid::Uuid;

struct Config {
    span_rate: f64,
    otlp_endpoint: String,
    duration_secs: u64,
    cardinality: usize,
}

fn load_config() -> Config {
    fn env_f64(key: &str, default: f64) -> f64 {
        env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
    }
    fn env_u64(key: &str, default: u64) -> u64 {
        env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
    }
    fn env_str(key: &str, default: &str) -> String {
        env::var(key).unwrap_or_else(|_| default.to_string())
    }
    fn env_usize(key: &str, default: usize) -> usize {
        env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
    }

    Config {
        span_rate: env_f64("SPAN_RATE", 10000.0),
        otlp_endpoint: env_str("OTLP_ENDPOINT", "http://otel-collector:4317"),
        duration_secs: env_u64("DURATION_SECS", 90),
        cardinality: env_usize("CARDINALITY", 20),
    }
}

fn build_tracer_provider(config: &Config) -> SdkTracerProvider {
    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_tonic()
        .with_endpoint(&config.otlp_endpoint)
        .build()
        .unwrap();

    let batch_processor = BatchSpanProcessor::builder(exporter).build();

    let resource = Resource::builder_empty()
        .with_attributes(vec![
            KeyValue::new("service.name", "trace-flood"),
            KeyValue::new("service.version", "0.1.0"),
        ])
        .build();

    SdkTracerProvider::builder()
        .with_span_processor(batch_processor)
        .with_resource(resource)
        .build()
}

fn generate_high_cardinality_attributes(cardinality: usize) -> Vec<KeyValue> {
    let mut attrs = Vec::with_capacity(cardinality);
    let mut rng = rand::rng();
    for i in 0..cardinality {
        let value = match i % 5 {
            0 => Uuid::new_v4().to_string(),
            1 => format!("user_{}", rng.random::<u64>() % 100000),
            2 => format!("session_{}", rng.random::<u64>() % 50000),
            3 => format!("tenant_{}", rng.random::<u64>() % 500),
            4 => format!("req_{}", rng.random::<u64>() % 999999),
            _ => unreachable!(),
        };
        attrs.push(KeyValue::new(format!("attr_{}", i), value));
    }
    attrs
}

async fn worker(
    tracer: opentelemetry_sdk::trace::Tracer,
    rate: f64,
    cardinality: usize,
    shutdown: Arc<Notify>,
) {
    loop {
        tokio::select! {
            _ = shutdown.notified() => break,
            _ = sleep(Duration::from_millis(
                (1000.0 / rate.max(1.0)) as u64
            )) => {}
        }

        let mut span = tracer
            .span_builder("flood-span")
            .with_kind(SpanKind::Internal)
            .with_attributes(generate_high_cardinality_attributes(cardinality))
            .start(&tracer);

        span.set_attribute(KeyValue::new("flood.timestamp", chrono_now()));
        span.set_attribute(KeyValue::new("flood.batch", Uuid::new_v4().to_string()));

        span.add_event("processing", vec![
            KeyValue::new("event.type", "flood"),
            KeyValue::new("event.id", Uuid::new_v4().to_string()),
        ]);

        drop(span);
    }
}

fn chrono_now() -> String {
    use std::time::SystemTime;
    SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_nanos().to_string())
        .unwrap_or_default()
}

#[tokio::main]
async fn main() {
    let config = Arc::new(load_config());
    let provider = build_tracer_provider(&config);
    let tracer = provider.tracer("trace-flood");

    let num_workers = 8;
    let rate_per_worker = config.span_rate / num_workers as f64;

    let shutdown = Arc::new(Notify::new());

    let handles: Vec<_> = (0..num_workers)
        .map(|_| {
            let tracer = tracer.clone();
            let shutdown = shutdown.clone();
            let cardinality = config.cardinality;
            tokio::spawn(async move {
                worker(tracer, rate_per_worker, cardinality, shutdown).await
            })
        })
        .collect();

    eprintln!(
        "trace-flood: starting {} workers at {:.0} spans/s each for {}s",
        num_workers, rate_per_worker, config.duration_secs
    );

    sleep(Duration::from_secs(config.duration_secs)).await;
    shutdown.notify_waiters();

    for h in handles {
        let _ = h.await;
    }

    if let Err(e) = provider.shutdown() {
        eprintln!("trace-flood: shutdown error: {:?}", e);
    }

    eprintln!("trace-flood: finished");
}
