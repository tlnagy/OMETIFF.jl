using Documenter, OMETIFF

makedocs(
    authors="Tamas Nagy and contributors",
    sitename="OMETIFF.jl Documentation",
    pages = [
        "Home" => "index.md",
        "Library" => Any[
            "Internals" => joinpath("lib", "internals.md")
        ],
    ],
)

deploydocs(
    repo = "github.com/tlnagy/OMETIFF.jl.git",
)