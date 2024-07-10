use pulldown_cmark::{html, Options, Parser};
use roc_std::RocStr;
use std::fs;
use std::path::{Path, PathBuf};
use syntect::easy::HighlightLines;
use syntect::highlighting::ThemeSet;
use syntect::html::{ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Files {
    pub path: roc_std::RocStr,
    pub relpath: roc_std::RocStr,
    pub url: roc_std::RocStr,
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Args {
    pub input_dir: roc_std::RocStr,
    pub output_dir: roc_std::RocStr,
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct Types {
    pub a: Files,
    pub b: Args,
    pub c: roc_std::RocStr,
    pub d: roc_std::RocStr,
}

/// Find the markdown `.md` files in a directory
pub fn find_files(dir_path: PathBuf) -> Result<Vec<Files>, String> {
    let mut file_paths = Vec::new();

    match find_files_help(&dir_path, &mut file_paths) {
        Ok(()) => Ok(file_paths
            .iter()
            .filter(|path| path.extension().filter(|s| (*s).eq("md")).is_some())
            .filter_map(|path_buf| {
                let path: RocStr = format!("{}", path_buf.display()).as_str().into();

                match path_buf.strip_prefix(&dir_path).map(|p| p.to_path_buf()) {
                    Err(..) => None,
                    Ok(ref mut stripped_path_buf) => {
                        stripped_path_buf.set_extension("html");

                        let relpath: RocStr =
                            format!("{}", stripped_path_buf.display()).as_str().into();

                        let url: RocStr =
                            format!("/{}", stripped_path_buf.display()).as_str().into();

                        Some(Files { url, path, relpath })
                    }
                }
            })
            .collect()),
        Err(err) => Err(err.to_string()),
    }
}

fn find_files_help(dir: &Path, file_paths: &mut Vec<PathBuf>) -> std::io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let pathbuf = entry?.path();
        if pathbuf.is_dir() {
            find_files_help(&pathbuf, file_paths)?;
        } else {
            file_paths.push(pathbuf);
        }
    }
    Ok(())
}

/// Parse a markdown file into html
pub fn parse_markdown(input_file: PathBuf) -> Result<String, String> {
    let content_md = match fs::read_to_string(&input_file) {
        Ok(str) => str,
        Err(err) => {
            return Err(format!(
                "Error reading {}: {}",
                input_file.to_str().unwrap_or("an input file"),
                err
            ))
        }
    };

    let mut content_html = String::new();
    let mut options = Options::all();

    // In the tutorial, this messes up string literals in <samp> blocks.
    // Those could be done as markdown code blocks, but the repl ones need
    // a special class, and there's no way to add that class using markdown alone.
    //
    // We could make this option user-configurable if people actually want it!
    options.remove(Options::ENABLE_SMART_PUNCTUATION);

    let parser = Parser::new_ext(&content_md, options);

    // We'll build a new vector of events since we can only consume the parser once
    let mut parser_with_highlighting = Vec::new();
    // As we go along, we'll want to highlight code in bundles, not lines
    let mut code_to_highlight = String::new();
    // And track a little bit of state
    let mut in_code_block = false;
    let mut is_roc_code = false;
    let syntax_set: syntect::parsing::SyntaxSet = SyntaxSet::load_defaults_newlines();
    let theme_set: syntect::highlighting::ThemeSet = ThemeSet::load_defaults();

    for event in parser {
        match event {
            pulldown_cmark::Event::Code(code_str) => {
                if code_str.starts_with("roc!") {
                    let stripped = code_str
                        .strip_prefix("roc!")
                        .expect("expected leading 'roc!'");

                    let highlighted_html =
                        roc_highlight::highlight_roc_code_inline(stripped.to_string().as_str());

                    parser_with_highlighting.push(pulldown_cmark::Event::Html(
                        pulldown_cmark::CowStr::from(highlighted_html),
                    ));
                } else {
                    let inline_code =
                        pulldown_cmark::CowStr::from(format!("<code>{}</code>", code_str));
                    parser_with_highlighting.push(pulldown_cmark::Event::Html(inline_code));
                }
            }
            pulldown_cmark::Event::Start(pulldown_cmark::Tag::CodeBlock(cbk)) => {
                in_code_block = true;
                is_roc_code = is_roc_code_block(&cbk);
            }
            pulldown_cmark::Event::End(pulldown_cmark::Tag::CodeBlock(
                pulldown_cmark::CodeBlockKind::Fenced(extension_str),
            )) => {
                if in_code_block {
                    match &code_to_highlight.split(':').collect::<Vec<_>>()[..] {
                        ["file", replacement_file_name, "snippet", snippet_name] => {
                            code_to_highlight = read_replacement_snippet(
                                replacement_file_name.trim(),
                                snippet_name.trim(),
                                input_file.as_path(),
                            )?;
                        }
                        ["file", replacement_file_name] => {
                            code_to_highlight = read_replacement_file(
                                replacement_file_name.trim(),
                                input_file.as_path(),
                            )?;
                        }
                        _ => {}
                    }

                    // Format the whole multi-line code block as HTML all at once
                    let highlighted_html: String;
                    if is_roc_code {
                        highlighted_html = roc_highlight::highlight_roc_code(&code_to_highlight)
                    } else if let Some(syntax) = syntax_set.find_syntax_by_token(&extension_str) {
                        HighlightLines::new(syntax, &theme_set.themes["base16-ocean.dark"]);

                        let mut html_generator = ClassedHTMLGenerator::new_with_class_style(
                            syntax,
                            &syntax_set,
                            ClassStyle::Spaced,
                        );
                        for line in LinesWithEndings::from(&code_to_highlight) {
                            if let Err(err) =
                                html_generator.parse_html_for_line_which_includes_newline(line)
                            {
                                return Err(err.to_string());
                            };
                        }
                        highlighted_html =
                            format!("<pre><samp>{}</pre></samp>", html_generator.finalize())
                    } else {
                        highlighted_html = format!("<pre><samp>{}</pre></samp>", &code_to_highlight)
                    }

                    // And put it into the vector
                    parser_with_highlighting.push(pulldown_cmark::Event::Html(
                        pulldown_cmark::CowStr::from(highlighted_html),
                    ));
                    code_to_highlight = String::new();
                    in_code_block = false;
                }
            }
            pulldown_cmark::Event::Text(t) => {
                if in_code_block {
                    // If we're in a code block, build up the string of text
                    code_to_highlight.push_str(&t);
                } else {
                    parser_with_highlighting.push(pulldown_cmark::Event::Text(t))
                }
            }
            e => {
                parser_with_highlighting.push(e);
            }
        }
    }

    html::push_html(&mut content_html, parser_with_highlighting.into_iter());

    Ok(content_html)
}

/// Write the contents to file
pub fn write_file(
    output_dir: PathBuf,
    output_rel_path: PathBuf,
    content: String,
) -> Result<(), String> {
    let output_file = output_dir.join(output_rel_path);

    // Create parent directory if it doesn't exist
    let parent_dir = output_file.parent().unwrap();
    if !parent_dir.exists() {
        fs::create_dir_all(parent_dir).unwrap();
    }

    match fs::write(&output_file, content) {
        Ok(()) => {
            println!("{} successfully written to disk", output_file.display());

            Ok(())
        }
        Err(err) => Err(err.to_string()),
    }
}

fn is_roc_code_block(cbk: &pulldown_cmark::CodeBlockKind) -> bool {
    match cbk {
        pulldown_cmark::CodeBlockKind::Indented => false,
        pulldown_cmark::CodeBlockKind::Fenced(cow_str) => cow_str.contains("roc"),
    }
}

fn read_replacement_file(replacement_file_name: &str, input_file: &Path) -> Result<String, String> {
    if replacement_file_name.contains("../") {
        return Err(format!(
            "ERROR File \"{}\" must be located within the input diretory.",
            replacement_file_name
        ));
    }

    let input_dir = input_file.parent().unwrap();
    let replacement_file_path = input_dir.join(replacement_file_name);

    fs::read(&replacement_file_path)
        .map(|content| {
            String::from_utf8(content).map_err(|err| format!("bad utf8 in file snippet: {}", err))
        })
        .map_err(|err| {
            format!(
                "ERROR File \"{}\" is unreadable:\n\t{}",
                replacement_file_path.to_str().unwrap(),
                err
            )
        })?
}

fn remove_snippet_comments(input: &str) -> String {
    let line_ending = if input.contains("\r\n") { "\r\n" } else { "\n" };

    input
        .lines()
        .filter(|line| !line.contains("### start snippet") && !line.contains("### end snippet"))
        .collect::<Vec<&str>>()
        .join(line_ending)
}

fn read_replacement_snippet(
    replacement_file_name: &str,
    snippet_name: &str,
    input_file: &Path,
) -> Result<String, String> {
    let start_marker = format!("### start snippet {}", snippet_name);
    let end_marker = format!("### end snippet {}", snippet_name);

    let replacement_file_content = read_replacement_file(replacement_file_name.trim(), input_file)?;

    let start_position = &replacement_file_content
        .find(&start_marker)
        .ok_or(format!("ERROR Failed to find snippet start \"{}\". ", &start_marker).as_str())?;

    let end_position = &replacement_file_content
        .find(&end_marker)
        .ok_or(format!("ERROR Failed to find snippet end \"{}\". ", &end_marker).as_str())?;

    if start_position >= end_position {
        let start_position_str = start_position.to_string();
        let end_position_str = end_position.to_string();

        Err(format!("ERROR Detected start position ({start_position_str}) of snippet \"{snippet_name}\" was greater than or equal to detected end position ({end_position_str})."))
    } else {
        // We want to remove other snippet comments inside this one if they exist.
        Ok(remove_snippet_comments(
            &replacement_file_content[start_position + start_marker.len()..*end_position],
        ))
    }
}
