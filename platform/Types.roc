module [
    Args,
    Path,
    Files,
    RelPath,
    path_to_str,
    rel_path_to_str,
    to_rel_path,
]

Path := Str

path_to_str : Path -> Str
path_to_str = \@Path str -> str

RelPath := Str

rel_path_to_str : RelPath -> Str
rel_path_to_str = \@RelPath str -> str

to_rel_path : Str -> RelPath
to_rel_path = @RelPath

Args : {
    inputDir : Path,
    outputDir : Path,
}

Files : {
    url : Str,
    path : Path,
    relpath : RelPath,
}
