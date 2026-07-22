//! Static-site-generation logic: discover markdown files, render markdown to
//! HTML (with Roc/other syntax highlighting), and write output files.

use pulldown_cmark::{html, Options, Parser};
use std::fs;
use std::path::{Component, Path, PathBuf};
use syntect::html::{ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::SyntaxSet;
use syntect::util::LinesWithEndings;

/// A discovered markdown source file and its derived output paths.
pub struct Page {
    pub url: String,
    pub source_path: PathBuf,
    pub output_path: PathBuf,
}

/// Find the markdown `.md` files in a directory (searched recursively).
pub fn find_pages(dir_path: &Path) -> Result<Vec<Page>, String> {
    let mut file_paths = Vec::new();

    find_files_help(dir_path, &mut file_paths)
        .map_err(|err| format!("failed to search {}: {err}", dir_path.display()))?;
    file_paths.sort();

    file_paths
        .into_iter()
        .filter(|path| path.extension().filter(|s| (*s).eq("md")).is_some())
        .map(|source_path| {
            let mut output_path = source_path
                .strip_prefix(dir_path)
                .map_err(|err| err.to_string())?
                .to_path_buf();
            output_path.set_extension("html");

            Ok(Page {
                url: page_url(&output_path),
                source_path,
                output_path,
            })
        })
        .collect()
}

fn find_files_help(dir: &Path, file_paths: &mut Vec<PathBuf>) -> std::io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let file_type = entry.file_type()?;

        // Do not follow directory symlinks (or other symlinks). Besides allowing
        // discovery to leave the content root, directory symlinks can form cycles.
        if file_type.is_symlink() {
            continue;
        }

        let pathbuf = entry.path();
        if file_type.is_dir() {
            find_files_help(&pathbuf, file_paths)?;
        } else {
            file_paths.push(pathbuf);
        }
    }
    Ok(())
}

fn page_url(output_path: &Path) -> String {
    let mut parts = Vec::new();
    for component in output_path.components() {
        match component {
            Component::Normal(part) => parts.push(part.to_string_lossy().into_owned()),
            Component::CurDir => {}
            Component::ParentDir => parts.push("..".to_owned()),
            Component::RootDir | Component::Prefix(_) => {}
        }
    }

    format!("/{}", parts.join("/"))
}

/// Parse a markdown file into html.
pub fn parse_markdown(input_file: &Path) -> Result<String, String> {
    let content_md = fs::read_to_string(input_file)
        .map_err(|err| format!("failed to read {}: {err}", input_file.display()))?;

    let mut content_html = String::new();
    let mut options = Options::all();

    // In the tutorial, this messes up string literals in <samp> blocks.
    // Those could be done as markdown code blocks, but the repl ones need
    // a special class, and there's no way to add that class using markdown alone.
    //
    // We could make this option user-configurable if people actually want it!
    options.remove(Options::ENABLE_SMART_PUNCTUATION);

    let parser = Parser::new_ext(&content_md, options);

    // Build a new event stream because the parser can only be consumed once.
    let mut parser_with_highlighting = Vec::new();
    // Highlight complete code blocks rather than individual lines.
    let mut code_to_highlight = String::new();
    let mut in_code_block = false;
    let mut is_roc_code = false;
    let syntax_set: syntect::parsing::SyntaxSet = SyntaxSet::load_defaults_newlines();

    for event in parser {
        match event {
            pulldown_cmark::Event::Code(code_str) => {
                if let Some(stripped) = code_str.strip_prefix("roc!") {
                    let highlighted_html = crate::roc_syntax::highlight_roc_code_inline(stripped);

                    parser_with_highlighting.push(pulldown_cmark::Event::Html(
                        pulldown_cmark::CowStr::from(highlighted_html),
                    ));
                } else {
                    // Keep this as a Markdown code event so pulldown-cmark applies
                    // the required HTML escaping when it renders the event stream.
                    parser_with_highlighting.push(pulldown_cmark::Event::Code(code_str));
                }
            }
            pulldown_cmark::Event::Start(pulldown_cmark::Tag::CodeBlock(cbk)) => {
                in_code_block = true;
                is_roc_code = is_roc_code_block(&cbk);
            }
            pulldown_cmark::Event::End(pulldown_cmark::Tag::CodeBlock(code_block_kind)) => {
                if in_code_block {
                    let language = match &code_block_kind {
                        pulldown_cmark::CodeBlockKind::Indented => None,
                        pulldown_cmark::CodeBlockKind::Fenced(info) => {
                            info.split_whitespace().next()
                        }
                    };

                    // File replacement directives are supported only in fenced
                    // blocks. Indented code is always rendered as literal code.
                    if language.is_some() {
                        match replacement_directive(&code_to_highlight) {
                            Some(ReplacementDirective::Snippet {
                                file_name,
                                snippet_name,
                            }) => {
                                code_to_highlight =
                                    read_replacement_snippet(file_name, snippet_name, input_file)?;
                            }
                            Some(ReplacementDirective::File { file_name }) => {
                                code_to_highlight = read_replacement_file(file_name, input_file)?;
                            }
                            None => {}
                        }
                    }

                    // Format the whole multi-line code block as HTML all at once
                    let highlighted_html: String;
                    if is_roc_code {
                        highlighted_html = crate::roc_syntax::highlight_roc_code(&code_to_highlight)
                    } else if let Some(syntax) =
                        language.and_then(|token| syntax_set.find_syntax_by_token(token))
                    {
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
                            format!("<pre><samp>{}</samp></pre>", html_generator.finalize())
                    } else {
                        highlighted_html = format!(
                            "<pre><samp>{}</samp></pre>",
                            html_escape::encode_text(&code_to_highlight)
                        )
                    }

                    parser_with_highlighting.push(pulldown_cmark::Event::Html(
                        pulldown_cmark::CowStr::from(highlighted_html),
                    ));
                    code_to_highlight = String::new();
                    in_code_block = false;
                }
            }
            pulldown_cmark::Event::Text(t) => {
                if in_code_block {
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

/// Write the contents to file.
pub fn write_file(output_dir: &Path, output_rel_path: &Path, content: &str) -> Result<(), String> {
    validate_relative_path(output_rel_path, "output path")?;

    fs::create_dir_all(output_dir).map_err(|err| {
        format!(
            "failed to create output directory {}: {err}",
            output_dir.display()
        )
    })?;
    let canonical_output_dir = fs::canonicalize(output_dir).map_err(|err| {
        format!(
            "failed to resolve output directory {}: {err}",
            output_dir.display()
        )
    })?;

    let output_file = output_dir.join(output_rel_path);

    let mut parent_dir = output_dir.to_path_buf();
    if let Some(relative_parent) = output_rel_path.parent() {
        for component in relative_parent.components() {
            let Component::Normal(part) = component else {
                continue;
            };
            parent_dir.push(part);

            match fs::symlink_metadata(&parent_dir) {
                Ok(metadata) if metadata.file_type().is_symlink() => {
                    return Err(format!(
                        "output directory component \"{}\" is a symbolic link",
                        parent_dir.display()
                    ));
                }
                Ok(metadata) if !metadata.is_dir() => {
                    return Err(format!(
                        "output directory component \"{}\" is not a directory",
                        parent_dir.display()
                    ));
                }
                Ok(_) => {}
                Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                    fs::create_dir(&parent_dir).map_err(|err| {
                        format!("failed to create directory {}: {err}", parent_dir.display())
                    })?;
                }
                Err(err) => {
                    return Err(format!(
                        "failed to inspect output directory {}: {err}",
                        parent_dir.display()
                    ));
                }
            }

            let canonical_parent_dir = fs::canonicalize(&parent_dir).map_err(|err| {
                format!(
                    "failed to resolve output directory {}: {err}",
                    parent_dir.display()
                )
            })?;
            if !canonical_parent_dir.starts_with(&canonical_output_dir) {
                return Err(format!(
                    "output path \"{}\" resolves outside output directory \"{}\"",
                    output_rel_path.display(),
                    output_dir.display()
                ));
            }
        }
    }

    if fs::symlink_metadata(&output_file)
        .map(|metadata| metadata.file_type().is_symlink())
        .unwrap_or(false)
    {
        return Err(format!(
            "output path \"{}\" is a symbolic link",
            output_rel_path.display()
        ));
    }

    fs::write(&output_file, content)
        .map_err(|err| format!("failed to write {}: {err}", output_file.display()))
}

enum ReplacementDirective<'a> {
    File {
        file_name: &'a str,
    },
    Snippet {
        file_name: &'a str,
        snippet_name: &'a str,
    },
}

fn replacement_directive(code: &str) -> Option<ReplacementDirective<'_>> {
    let mut parts = code.split(':');
    match (
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
        parts.next(),
    ) {
        (Some("file"), Some(file_name), None, None, None) => Some(ReplacementDirective::File {
            file_name: file_name.trim(),
        }),
        (Some("file"), Some(file_name), Some("snippet"), Some(snippet_name), None) => {
            Some(ReplacementDirective::Snippet {
                file_name: file_name.trim(),
                snippet_name: snippet_name.trim(),
            })
        }
        _ => None,
    }
}

fn is_roc_code_block(cbk: &pulldown_cmark::CodeBlockKind) -> bool {
    match cbk {
        pulldown_cmark::CodeBlockKind::Indented => false,
        pulldown_cmark::CodeBlockKind::Fenced(info) => {
            info.split_whitespace().next() == Some("roc")
        }
    }
}

fn read_replacement_file(replacement_file_name: &str, input_file: &Path) -> Result<String, String> {
    let replacement_path = Path::new(replacement_file_name);
    validate_relative_path(replacement_path, "replacement file")?;

    let input_dir = input_file
        .parent()
        .ok_or_else(|| format!("input file \"{}\" has no parent", input_file.display()))?;
    let input_dir = if input_dir.as_os_str().is_empty() {
        Path::new(".")
    } else {
        input_dir
    };
    let replacement_file_path = input_dir.join(replacement_path);

    let canonical_input_dir = fs::canonicalize(input_dir).map_err(|err| {
        format!(
            "failed to resolve input directory {}: {err}",
            input_dir.display(),
        )
    })?;
    let canonical_replacement_file = fs::canonicalize(&replacement_file_path).map_err(|err| {
        format!(
            "failed to resolve replacement file {}: {err}",
            replacement_file_path.display(),
        )
    })?;
    if !canonical_replacement_file.starts_with(&canonical_input_dir) {
        return Err(format!(
            "replacement file \"{}\" must be located within input directory \"{}\"",
            replacement_file_path.display(),
            input_dir.display()
        ));
    }

    let content = fs::read(&canonical_replacement_file).map_err(|err| {
        format!(
            "failed to read replacement file {}: {err}",
            replacement_file_path.display()
        )
    })?;
    String::from_utf8(content).map_err(|err| {
        format!(
            "replacement file {} is not valid UTF-8: {err}",
            replacement_file_path.display()
        )
    })
}

fn validate_relative_path(path: &Path, description: &str) -> Result<(), String> {
    if path.as_os_str().is_empty() {
        return Err(format!("{} must not be empty", description));
    }

    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(format!(
                    "{} \"{}\" must be relative and must not contain parent traversal",
                    description,
                    path.display()
                ));
            }
        }
    }

    Ok(())
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

    let start_position = replacement_file_content
        .find(&start_marker)
        .ok_or_else(|| format!("failed to find snippet start \"{start_marker}\""))?;
    let snippet_start = start_position + start_marker.len();
    let end_position = replacement_file_content[snippet_start..]
        .find(&end_marker)
        .map(|position| snippet_start + position)
        .ok_or_else(|| format!("failed to find snippet end \"{end_marker}\""))?;

    // Remove markers for nested snippets from the selected content too.
    Ok(remove_snippet_comments(
        &replacement_file_content[snippet_start..end_position],
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT_TEST_DIR: AtomicUsize = AtomicUsize::new(0);

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        fn new(name: &str) -> Self {
            let id = NEXT_TEST_DIR.fetch_add(1, Ordering::Relaxed);
            let path =
                std::env::temp_dir().join(format!("basic-ssg-{name}-{}-{id}", std::process::id()));
            fs::create_dir_all(&path).expect("create test directory");
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn write(path: &Path, content: &str) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create fixture parent directory");
        }
        fs::write(path, content).expect("write fixture");
    }

    fn render_markdown(markdown: &str) -> String {
        let test_dir = TestDir::new("markdown");
        let input = test_dir.path().join("page.md");
        write(&input, markdown);
        parse_markdown(&input).expect("render markdown")
    }

    #[test]
    fn discovery_is_sorted() {
        let test_dir = TestDir::new("sorted-discovery");
        write(&test_dir.path().join("z.md"), "z");
        write(&test_dir.path().join("a.md"), "a");
        write(&test_dir.path().join("nested/b.md"), "b");
        write(&test_dir.path().join("ignored.txt"), "ignored");

        let pages = find_pages(test_dir.path()).expect("discover pages");
        let output_paths: Vec<_> = pages.into_iter().map(|page| page.output_path).collect();

        assert_eq!(
            output_paths,
            vec![
                PathBuf::from("a.html"),
                PathBuf::from("nested/b.html"),
                PathBuf::from("z.html"),
            ]
        );
    }

    #[cfg(unix)]
    #[test]
    fn discovery_does_not_follow_directory_symlinks() {
        use std::os::unix::fs::symlink;

        let test_dir = TestDir::new("symlink-discovery");
        let content = test_dir.path().join("content");
        let external = test_dir.path().join("external");
        write(&content.join("real.md"), "real");
        write(&external.join("escaped.md"), "escaped");
        symlink(&external, content.join("linked")).expect("create directory symlink");

        let pages = find_pages(&content).expect("discover pages");
        let output_paths: Vec<_> = pages.into_iter().map(|page| page.output_path).collect();

        assert_eq!(output_paths, vec![PathBuf::from("real.html")]);
    }

    #[test]
    fn write_file_rejects_paths_outside_output_directory() {
        let test_dir = TestDir::new("write-confinement");
        let output_dir = test_dir.path().join("output");
        let absolute_path = test_dir.path().join("absolute.html");

        assert!(write_file(&output_dir, Path::new("../parent.html"), "bad").is_err());
        assert!(write_file(&output_dir, &absolute_path, "bad").is_err());
        assert!(!test_dir.path().join("parent.html").exists());
        assert!(!absolute_path.exists());

        write_file(&output_dir, Path::new("nested/good.html"), "good")
            .expect("write confined output");
        assert_eq!(
            fs::read_to_string(output_dir.join("nested/good.html")).expect("read output"),
            "good"
        );
    }

    #[cfg(unix)]
    #[test]
    fn write_file_rejects_symlinks_that_escape_output_directory() {
        use std::os::unix::fs::symlink;

        let test_dir = TestDir::new("write-symlink-confinement");
        let output_dir = test_dir.path().join("output");
        let external = test_dir.path().join("external");
        fs::create_dir_all(&output_dir).expect("create output directory");
        fs::create_dir_all(&external).expect("create external directory");
        symlink(&external, output_dir.join("linked")).expect("create output symlink");

        assert!(write_file(&output_dir, Path::new("linked/missing/escaped.html"), "bad").is_err());
        assert!(!external.join("missing").exists());
    }

    #[test]
    fn markdown_escapes_inline_and_unrecognized_code() {
        let inline = render_markdown("`<script>&`\n");
        assert!(inline.contains("<code>&lt;script&gt;&amp;</code>"));

        let fenced = render_markdown("```not-a-language\n<script>&\n```\n");
        assert!(fenced.contains("<pre><samp>&lt;script&gt;&amp;\n</samp></pre>"));
        assert!(!fenced.contains("</pre></samp>"));

        let indented = render_markdown("    <script>&\n");
        assert!(indented.contains("<pre><samp>&lt;script&gt;&amp;\n</samp></pre>"));
    }

    #[test]
    fn replacement_files_must_resolve_within_the_input_directory() {
        let test_dir = TestDir::new("replacement-confinement");
        let input_dir = test_dir.path().join("content");
        let input_file = input_dir.join("page.md");
        let replacement = input_dir.join("snippets/example.roc");
        let outside = test_dir.path().join("outside.roc");
        write(&input_file, "page");
        write(&replacement, "inside");
        write(&outside, "outside");

        assert_eq!(
            read_replacement_file("snippets/example.roc", &input_file)
                .expect("read confined replacement"),
            "inside"
        );
        assert!(read_replacement_file("../outside.roc", &input_file).is_err());
        assert!(
            read_replacement_file(outside.to_str().expect("UTF-8 fixture path"), &input_file)
                .is_err()
        );
    }

    #[test]
    fn markdown_expands_replacement_file_directives() {
        let test_dir = TestDir::new("replacement-directive");
        let input = test_dir.path().join("page.md");
        let replacement = test_dir.path().join("snippets/example.txt");
        write(&replacement, "replacement <content>\n");
        write(
            &input,
            "```not-a-language\nfile:snippets/example.txt\n```\n",
        );

        let html = parse_markdown(&input).expect("render replacement file directive");

        assert!(html.contains("replacement &lt;content&gt;\n"));
        assert!(!html.contains("file:snippets/example.txt"));
    }

    #[test]
    fn markdown_expands_the_named_replacement_snippet() {
        let test_dir = TestDir::new("replacement-snippet");
        let input = test_dir.path().join("page.md");
        let replacement = test_dir.path().join("snippets/example.txt");
        write(
            &replacement,
            concat!(
                "outside before\n",
                "### start snippet selected\n",
                "selected <content>\n",
                "### start snippet nested\n",
                "nested content\n",
                "### end snippet nested\n",
                "### end snippet selected\n",
                "outside after\n",
            ),
        );
        write(
            &input,
            "```not-a-language\nfile:snippets/example.txt:snippet:selected\n```\n",
        );

        let html = parse_markdown(&input).expect("render replacement snippet directive");

        assert!(html.contains("selected &lt;content&gt;"));
        assert!(html.contains("nested content"));
        assert!(!html.contains("outside before"));
        assert!(!html.contains("outside after"));
        assert!(!html.contains("### start snippet"));
        assert!(!html.contains("### end snippet"));
    }

    #[cfg(unix)]
    #[test]
    fn replacement_files_cannot_escape_through_symlinks() {
        use std::os::unix::fs::symlink;

        let test_dir = TestDir::new("replacement-symlink-confinement");
        let input_dir = test_dir.path().join("content");
        let input_file = input_dir.join("page.md");
        let outside = test_dir.path().join("outside.roc");
        write(&input_file, "page");
        write(&outside, "outside");
        symlink(&outside, input_dir.join("linked.roc")).expect("create replacement symlink");

        assert!(read_replacement_file("linked.roc", &input_file).is_err());
    }
}
