//! Self-contained syntax highlighter for Roc source code.
//!
//! This replaces the old `roc_highlight` crate (which depended on the old Rust
//! compiler's `roc_parse` and does not exist in the new Zig compiler tree). It is
//! a small hand-written scanner that targets *current* Roc syntax and emits the
//! `<span class="…">` classes styled by the example's `www/style.css`
//! (`comment`, `kw`, `op`, `number`, `str`, `paren`, `bracket`, `brace`,
//! `comma`, `colon`). Tokens with no styled class (identifiers, whitespace) are
//! emitted as plain HTML-escaped text.

/// Highlight a multi-line Roc code block, wrapped in `<pre><samp>…</samp></pre>`.
pub fn highlight_roc_code(code: &str) -> String {
    format!("<pre><samp>{}</samp></pre>", highlight_inner(code))
}

/// Highlight an inline Roc snippet, wrapped in `<code>…</code>`.
pub fn highlight_roc_code_inline(code: &str) -> String {
    format!("<code>{}</code>", highlight_inner(code))
}

fn highlight_inner(input: &str) -> String {
    let mut out = String::with_capacity(input.len() * 2);

    // Snippets sometimes start with "»" to show they're in the repl. Special-case
    // it even though it is normally not valid Roc, matching the old highlighter.
    const REPL_PROMPT: &str = "\u{00BB}";
    let code = if let Some(stripped) = input.strip_prefix(REPL_PROMPT) {
        push_span(&mut out, REPL_PROMPT, "kw");
        stripped
    } else {
        input
    };

    let bytes = code.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];

        // Line comment (`#` ... newline). `##` doc comments are covered too.
        if b == b'#' {
            let start = i;
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            push_span(&mut out, &code[start..i], "comment");
            continue;
        }

        // String literal: triple-quoted or single-quoted (with escapes).
        if b == b'"' {
            let start = i;
            if code[i..].starts_with("\"\"\"") {
                i += 3;
                while i < bytes.len() && !code[i..].starts_with("\"\"\"") {
                    i += 1;
                }
                if code[i..].starts_with("\"\"\"") {
                    i += 3;
                }
            } else {
                i += 1;
                while i < bytes.len() && bytes[i] != b'"' {
                    if bytes[i] == b'\\' && i + 1 < bytes.len() {
                        i += 2;
                    } else {
                        i += 1;
                    }
                }
                if i < bytes.len() {
                    i += 1; // closing quote
                }
            }
            push_span(&mut out, &code[start..i], "str");
            continue;
        }

        // Character literal: 'x' (with escapes).
        if b == b'\'' {
            let start = i;
            i += 1;
            while i < bytes.len() && bytes[i] != b'\'' {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    i += 2;
                } else {
                    i += 1;
                }
            }
            if i < bytes.len() {
                i += 1;
            }
            push_span(&mut out, &code[start..i], "str");
            continue;
        }

        // Number literal (also hex/binary/underscored). Stops before the `..`
        // range operator.
        if b.is_ascii_digit() {
            let start = i;
            while i < bytes.len() {
                let c = bytes[i];
                if c == b'.' && i + 1 < bytes.len() && bytes[i + 1] == b'.' {
                    break;
                }
                if c.is_ascii_alphanumeric() || c == b'_' || c == b'.' {
                    i += 1;
                } else {
                    break;
                }
            }
            push_span(&mut out, &code[start..i], "number");
            continue;
        }

        // Identifier or keyword. A trailing `!` is part of effectful names.
        if b.is_ascii_alphabetic() || b == b'_' {
            let start = i;
            while i < bytes.len()
                && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_' || bytes[i] == b'!')
            {
                i += 1;
            }
            let word = &code[start..i];
            if is_keyword(word) {
                push_span(&mut out, word, "kw");
            } else {
                push_escaped(&mut out, word);
            }
            continue;
        }

        // Multi-character operators (longest match first).
        if let Some(len) = match_operator(&code[i..]) {
            push_span(&mut out, &code[i..i + len], "op");
            i += len;
            continue;
        }

        // Single-character delimiters / operators.
        let class = match b {
            b'(' | b')' => Some("paren"),
            b'[' | b']' => Some("bracket"),
            b'{' | b'}' => Some("brace"),
            b',' => Some("comma"),
            b':' => Some("colon"),
            b'=' | b'|' | b'+' | b'-' | b'*' | b'/' | b'%' | b'^' | b'!' | b'?' | b'<' | b'>'
            | b'&' | b'.' => Some("op"),
            _ => None,
        };
        if let Some(class) = class {
            push_span(&mut out, &code[i..i + 1], class);
            i += 1;
            continue;
        }

        // Anything else (whitespace, unicode): emit one char, escaped.
        let len = utf8_char_len(b);
        let end = (i + len).min(bytes.len());
        push_escaped(&mut out, &code[i..end]);
        i = end;
    }

    out
}

fn is_keyword(word: &str) -> bool {
    matches!(
        word,
        "match"
            | "when"
            | "is"
            | "if"
            | "then"
            | "else"
            | "import"
            | "module"
            | "app"
            | "platform"
            | "package"
            | "packages"
            | "provides"
            | "requires"
            | "exposes"
            | "exposing"
            | "hosted"
            | "expect"
            | "crash"
            | "dbg"
            | "return"
            | "for"
            | "in"
            | "var"
            | "as"
            | "where"
            | "implements"
            | "and"
            | "or"
    )
}

/// Returns the byte length of a multi-character operator at the start of `s`, if any.
fn match_operator(s: &str) -> Option<usize> {
    const THREE: [&str; 1] = ["..."];
    const TWO: [&str; 13] = [
        "=>", "->", "|>", "<-", "::", ":=", "..", "==", "!=", "<=", ">=", "||", "&&",
    ];
    for op in THREE {
        if s.starts_with(op) {
            return Some(op.len());
        }
    }
    // "//" integer-division operator.
    if s.starts_with("//") {
        return Some(2);
    }
    for op in TWO {
        if s.starts_with(op) {
            return Some(op.len());
        }
    }
    None
}

fn utf8_char_len(first_byte: u8) -> usize {
    if first_byte < 0x80 {
        1
    } else if first_byte >> 5 == 0b110 {
        2
    } else if first_byte >> 4 == 0b1110 {
        3
    } else {
        4
    }
}

fn push_span(out: &mut String, text: &str, class: &str) {
    out.push_str("<span class=\"");
    out.push_str(class);
    out.push_str("\">");
    out.push_str(&html_escape::encode_text(text));
    out.push_str("</span>");
}

fn push_escaped(out: &mut String, text: &str) {
    out.push_str(&html_escape::encode_text(text));
}
