using Hephaestus
using Documenter

DocMeta.setdocmeta!(Hephaestus, :DocTestSetup, :(using Hephaestus); recursive=true)

makedocs(;
    modules=[Hephaestus],
    authors="Demetrius Michael <arrrwalktheplank@gmail.com>",
    sitename="Hephaestus.jl",
    format=Documenter.HTML(;
        canonical="https://D3MZ.github.io/Hephaestus.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/D3MZ/Hephaestus.jl",
    devbranch="main",
)
