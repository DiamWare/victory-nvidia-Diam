//! A tiny JSON writer. The project deliberately has no `serde_json` dependency;
//! reports only ever need to be written, never parsed.

/// Minimal JSON value used to build a report before serialising it.
#[derive(Clone, Debug, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Int(u64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(&'static str, Json)>),
}

impl Json {
    pub fn string(value: impl Into<String>) -> Self {
        Self::Str(value.into())
    }

    pub fn number(value: f64) -> Self {
        if value.is_finite() {
            Self::Num(value)
        } else {
            Self::Null
        }
    }

    /// Appends this value to `out` using compact, valid JSON.
    pub fn write(&self, out: &mut String) {
        match self {
            Self::Null => out.push_str("null"),
            Self::Bool(true) => out.push_str("true"),
            Self::Bool(false) => out.push_str("false"),
            Self::Int(value) => out.push_str(&value.to_string()),
            Self::Num(value) => {
                let text = value.to_string();
                if text.contains('.') || text.contains('e') || text.contains('E') {
                    out.push_str(&text);
                } else {
                    out.push_str(&text);
                    out.push_str(".0");
                }
            }
            Self::Str(value) => write_string(value, out),
            Self::Arr(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    item.write(out);
                }
                out.push(']');
            }
            Self::Obj(fields) => {
                out.push('{');
                for (i, (key, value)) in fields.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_string(key, out);
                    out.push(':');
                    value.write(out);
                }
                out.push('}');
            }
        }
    }
}

impl std::fmt::Display for Json {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut out = String::new();
        self.write(&mut out);
        f.write_str(&out)
    }
}

fn write_string(value: &str, out: &mut String) {
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c < ' ' => {
                out.push_str("\\u");
                out.push_str(&format!("{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

/// Pulls a simple JSON string field out of a response. Enough for the token
/// returned by `/register`; not a general parser.
pub fn find_string(body: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\"");
    let start = body.find(&needle)? + needle.len();
    let rest = body.get(start..)?;
    let colon = rest.find(':')?;
    let rest = rest[colon + 1..].trim_start();
    if !rest.starts_with('"') {
        return None;
    }
    let mut out = String::new();
    let mut escaped = false;
    for c in rest[1..].chars() {
        if escaped {
            out.push(match c {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                other => other,
            });
            escaped = false;
        } else if c == '\\' {
            escaped = true;
        } else if c == '"' {
            return Some(out);
        } else {
            out.push(c);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_control_characters() {
        let value = Json::Obj(vec![
            ("path", Json::string("C:\\Users\\me\nnext")),
            ("ok", Json::Bool(true)),
            ("n", Json::number(1.5)),
        ]);
        assert_eq!(
            value.to_string(),
            r#"{"path":"C:\\Users\\me\nnext","ok":true,"n":1.5}"#
        );
    }

    #[test]
    fn non_finite_numbers_become_null() {
        assert_eq!(Json::number(f64::NAN), Json::Null);
    }

    #[test]
    fn reads_a_token_from_a_response() {
        let body = r#"{"ok":true,"token":"vti_abc123","machine_id":"aa"}"#;
        assert_eq!(find_string(body, "token").as_deref(), Some("vti_abc123"));
        assert!(find_string(body, "missing").is_none());
    }
}
