using Hephaestus

svg_path = joinpath(@__DIR__, "outputs", "TilingPattern2.svg")
generate_tiling_svg(svg_path;
    symmetry=5,
    radius=500,
    pattern=0.2,
    pan=0.0,
    disorder=0.0,
    random_seed=0.0,
    zoom=1.0,
    rotate=0.0,
    show_stroke=false,
    stroke=128.0,
    reverse_colors=true,
    orientation_coloring=false,
    width=500,
    height=500,
    # cropwidth=100,
    # cropheight=100
    )

generate_3mf_from_svg(svg_path, joinpath(@__DIR__, "outputs", "TilingPattern2.3mf"); height=0.2)
