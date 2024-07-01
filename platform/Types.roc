module [
    Args,
    Path,
    pathToStr,
    RelPath,
    relPathToStr,
    toRelPath,
    Files,
]

Path := Str

pathToStr : Path -> Str
pathToStr = \@Path str -> str

RelPath := Str

relPathToStr : RelPath -> Str
relPathToStr = \@RelPath str -> str

toRelPath : Str -> RelPath
toRelPath = @RelPath

Args : {
    inputDir : Path,
    outputDir : Path,
}

Files : {
    url : Str,
    path : Path,
    relpath : RelPath,
}
