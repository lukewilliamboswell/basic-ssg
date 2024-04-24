interface InternalTypes
    exposes [
        UrlPath,
        Args,
    ]
    imports []

Args : {
    inputDir : Str, 
    outputDir: Str,
}

UrlPath : {
    url : Str, 
    path : Str,
}