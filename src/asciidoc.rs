//! Secure AsciiDoc parsing and conversion into a semantic document.

use asciidoc_parser::{
    blocks::{Block, BreakType, FindBlocks, IsBlock, ListType, MediaType, SimpleBlockStyle},
    HasSpan, Parser,
};

pub struct Document {
    pub title: String,
    pub id: String,
    pub roles: Vec<String>,
    pub blocks: Vec<SemanticBlock>,
    pub warnings: Vec<Warning>,
}

pub struct SemanticBlock {
    pub kind: String,
    pub id: String,
    pub roles: Vec<String>,
    pub title: String,
    pub level: u64,
    pub source: String,
    pub inline_html: Option<String>,
    pub html: String,
}

pub struct Warning {
    pub message: String,
    pub line: u64,
    pub column: u64,
}

pub fn parse(source: &str) -> Document {
    // Parser defaults to Secure and no external-resource handlers are installed.
    let parsed = Parser::new().parse(source);
    let blocks = parsed.child_blocks().map(semantic_block).collect();
    let warnings = parsed
        .warnings()
        .map(|warning| Warning {
            message: warning.warning.to_string(),
            line: warning.source.line() as u64,
            column: warning.source.col() as u64,
        })
        .collect();
    Document {
        title: parsed.doctitle().unwrap_or_default().to_owned(),
        id: parsed.header().id().unwrap_or_default().to_owned(),
        roles: parsed
            .header()
            .roles()
            .into_iter()
            .map(str::to_owned)
            .collect(),
        blocks,
        warnings,
    }
}

fn semantic_block(block: &Block<'_>) -> SemanticBlock {
    SemanticBlock {
        kind: block.resolved_context().as_ref().to_owned(),
        id: block.id().unwrap_or_default().to_owned(),
        roles: block.roles().into_iter().map(str::to_owned).collect(),
        title: block.title().unwrap_or_default().to_owned(),
        level: match block {
            Block::Section(section) => section.level() as u64,
            _ => 0,
        },
        source: block.span().data().to_owned(),
        inline_html: block.rendered_content().map(str::to_owned),
        html: render_block(block),
    }
}

fn render_block(block: &Block<'_>) -> String {
    let context = block.resolved_context();
    let id = block
        .id()
        .map(|value| {
            format!(
                " id=\"{}\"",
                html_escape::encode_double_quoted_attribute(value)
            )
        })
        .unwrap_or_default();
    let roles = block.roles();
    let role_suffix = if roles.is_empty() {
        String::new()
    } else {
        format!(" {}", roles.join(" "))
    };
    match block {
        Block::Section(section) => {
            let level = section.level().clamp(1, 6);
            let children = block.child_blocks().map(render_block).collect::<String>();
            format!("<div class=\"sect{level}{role_suffix}\"><h{level}{id}>{}</h{level}>{children}</div>", section.section_title())
        }
        Block::Simple(simple) => match simple.style() {
            SimpleBlockStyle::Paragraph => format!("<div class=\"paragraph{role_suffix}\"{id}><p>{}</p></div>", simple.content().rendered()),
            SimpleBlockStyle::Source | SimpleBlockStyle::Listing => {
                let code = simple.content().original().data();
                let highlighted = crate::ssg::highlight_code(code, source_language(block)).unwrap_or_else(|_| format!("<pre><samp>{}</samp></pre>", html_escape::encode_text(code)));
                format!("<div class=\"listingblock{role_suffix}\"{id}><div class=\"content\">{highlighted}</div></div>")
            }
            SimpleBlockStyle::Literal => format!("<div class=\"literalblock{role_suffix}\"{id}><div class=\"content\"><pre>{}</pre></div></div>", simple.content().rendered()),
        },
        Block::RawDelimited(raw) if block.declared_style() == Some("source") => {
            let code = raw.content().original().data();
            let highlighted = crate::ssg::highlight_code(code, source_language(block))
                .unwrap_or_else(|_| format!("<pre><samp>{}</samp></pre>", html_escape::encode_text(code)));
            format!("<div class=\"listingblock{role_suffix}\"{id}><div class=\"content\">{highlighted}</div></div>")
        }
        Block::List(list) => {
            let tag = match list.type_() {
                ListType::Ordered | ListType::Callout => "ol",
                ListType::Unordered => "ul",
                ListType::Description => "dl",
            };
            let items = block.child_blocks().map(render_block).collect::<String>();
            format!("<{tag} class=\"{context}{role_suffix}\"{id}>{items}</{tag}>")
        }
        Block::ListItem(item) => {
            let text = item.rendered_content().unwrap_or_default();
            let children = block.child_blocks().map(render_block).collect::<String>();
            format!("<li{id}>{text}{children}</li>")
        }
        Block::Admonition(admonition) => {
            let name = admonition.name().to_lowercase();
            let content = admonition.content().map(|c| c.rendered()).unwrap_or_default();
            let children = block.child_blocks().map(render_block).collect::<String>();
            format!("<div class=\"admonitionblock {name}{role_suffix}\"{id}><table><tr><td class=\"icon\"><div class=\"title\">{}</div></td><td class=\"content\">{content}{children}</td></tr></table></div>", admonition.label())
        }
        Block::Media(media) => {
            let target = html_escape::encode_double_quoted_attribute(media.resolved_target());
            match media.type_() {
                MediaType::Image => format!("<div class=\"imageblock{role_suffix}\"{id}><div class=\"content\"><img src=\"{target}\" alt=\"\"></div></div>"),
                MediaType::Audio => format!("<div class=\"audioblock{role_suffix}\"{id}><div class=\"content\"><audio src=\"{target}\" controls></audio></div></div>"),
                MediaType::Video => format!("<div class=\"videoblock{role_suffix}\"{id}><div class=\"content\"><video src=\"{target}\" controls></video></div></div>"),
            }
        }
        Block::Break(break_) => match break_.type_() {
            BreakType::Thematic => "<hr>".to_owned(),
            BreakType::Page => "<div style=\"page-break-after: always;\"></div>".to_owned(),
        },
        _ => {
            let content = block.rendered_content().unwrap_or_default();
            let children = block.child_blocks().map(render_block).collect::<String>();
            format!("<div class=\"{}block{role_suffix}\"{id}><div class=\"content\">{content}{children}</div></div>", html_escape::encode_double_quoted_attribute(&context))
        }
    }
}

fn source_language<'a>(block: &'a Block<'a>) -> Option<&'a str> {
    if block.declared_style() != Some("source") {
        return None;
    }
    block
        .attrlist()?
        .nth_attribute(2)
        .map(|attribute| attribute.value().trim())
        .filter(|value| !value.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_title_sections_and_inline_markup() {
        let doc =
            parse("= Hello\n\n== Intro\n\nThis is *strong* and https://example.com[a link].\n");
        assert_eq!(doc.title, "Hello");
        assert_eq!(doc.blocks[0].kind, "section");
        assert!(doc.blocks[0].html.contains("<strong>strong</strong>"));
    }

    #[test]
    fn secure_parser_does_not_expand_includes() {
        let doc = parse("include::/etc/passwd[]\n");
        assert!(!doc
            .blocks
            .iter()
            .any(|block| block.html.contains("root:x:")));
    }

    #[test]
    fn preserves_passthrough_html() {
        let doc = parse("+++<mark>trusted</mark>+++\n");
        assert!(doc.blocks[0].html.contains("<mark>trusted</mark>"));
    }

    #[test]
    fn highlights_delimited_roc_source() {
        let doc = parse("[source,roc]\n----\nvalue = \"Roc\"\n----\n");
        assert!(
            doc.blocks[0].html.contains("class=\"str\""),
            "{}",
            doc.blocks[0].html
        );
    }
}
