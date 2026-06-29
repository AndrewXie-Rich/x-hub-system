use std::io::Read;
use std::net::TcpStream;

pub(crate) struct HttpRequest {
    pub(crate) method: String,
    pub(crate) path: String,
    pub(crate) body: String,
    pub(crate) headers: Vec<(String, String)>,
}

impl HttpRequest {
    pub(crate) fn header(&self, name: &str) -> Option<&str> {
        let normalized = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(header_name, _)| header_name == &normalized)
            .map(|(_, value)| value.as_str())
    }
}

pub(crate) fn read_http_request(stream: &mut TcpStream) -> Result<HttpRequest, String> {
    const MAX_REQUEST_BYTES: usize = 1024 * 1024;
    let mut bytes = Vec::with_capacity(4096);
    let header_end = loop {
        if let Some(index) = find_bytes(&bytes, b"\r\n\r\n") {
            break index;
        }
        if bytes.len() >= MAX_REQUEST_BYTES {
            return Err("http request too large".to_string());
        }
        let mut chunk = [0_u8; 4096];
        let read = stream.read(&mut chunk).map_err(|err| err.to_string())?;
        if read == 0 {
            if bytes.is_empty() {
                return Err("empty http request".to_string());
            }
            return Err("incomplete http request headers".to_string());
        }
        bytes.extend_from_slice(&chunk[..read]);
    };
    let header_text = String::from_utf8_lossy(&bytes[..header_end]);
    let first_line = header_text.lines().next().unwrap_or("");
    let mut first_parts = first_line.split_whitespace();
    let method = first_parts.next().unwrap_or("GET").to_ascii_uppercase();
    let path = first_parts.next().unwrap_or("/").to_string();
    let headers = header_text
        .lines()
        .skip(1)
        .filter_map(|line| {
            let (name, value) = line.split_once(':')?;
            Some((name.trim().to_ascii_lowercase(), value.trim().to_string()))
        })
        .collect::<Vec<_>>();
    let content_length = header_text
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            if name.trim().eq_ignore_ascii_case("content-length") {
                value.trim().parse::<usize>().ok()
            } else {
                None
            }
        })
        .unwrap_or(0);
    if content_length > MAX_REQUEST_BYTES {
        return Err("http request body too large".to_string());
    }
    let body_start = header_end + 4;
    while bytes.len().saturating_sub(body_start) < content_length {
        if bytes.len() >= MAX_REQUEST_BYTES {
            return Err("http request too large".to_string());
        }
        let mut chunk = [0_u8; 4096];
        let read = stream.read(&mut chunk).map_err(|err| err.to_string())?;
        if read == 0 {
            return Err("incomplete http request body".to_string());
        }
        bytes.extend_from_slice(&chunk[..read]);
    }
    let body_end = body_start + content_length;
    let body = String::from_utf8_lossy(&bytes[body_start..body_end]).to_string();
    Ok(HttpRequest {
        method,
        path,
        body,
        headers,
    })
}

pub(crate) fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack
        .windows(needle.len())
        .position(|window| window == needle)
}

pub(crate) fn split_path_query(path: &str) -> (&str, &str) {
    match path.split_once('?') {
        Some((route_path, query)) => (route_path, query.split('#').next().unwrap_or("")),
        None => (path.split('#').next().unwrap_or(path), ""),
    }
}
