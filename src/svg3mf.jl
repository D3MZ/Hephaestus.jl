function generate_3mf_from_svg(svg_path::AbstractString, output_path::AbstractString; height::Real=1.0)
    svg_text = read(svg_path, String)
    poly_re = r"<polygon[^>]*points=\"([^\"]+)\"[^>]*fill=\"([^\"]+)\"[^>]*/?>"
    polys = Tuple{Vector{Point}, String}[]
    for m in eachmatch(poly_re, svg_text)
        pts_raw = split(strip(m.captures[1]))
        pts = Point[]
        for p in pts_raw
            parts = split(p, ",")
            length(parts) == 2 || continue
            x = parse(Float64, parts[1])
            y = parse(Float64, parts[2])
            push!(pts, Point(x, y))
        end
        length(pts) >= 3 || continue
        color = m.captures[2]
        push!(polys, (pts, color))
    end

    isempty(polys) && error("No polygons found in SVG: $(svg_path)")

    color_index = Dict{String, Int}()
    colors = String[]
    function color_id(color::String)
        get!(color_index, color) do
            push!(colors, color)
            return length(colors) - 1
        end
    end

    polys_by_color = Dict{String, Vector{Vector{Point}}}()
    for (pts, color) in polys
        push!(get!(polys_by_color, color, Vector{Vector{Point}}()), pts)
        color_id(color)
    end

    objects = Vector{NamedTuple{(:color, :vertices, :triangles), Tuple{String, Vector{NTuple{3, Float64}}, Vector{NTuple{4, Int}}}}}()
    z0 = 0.0
    z1 = Float64(height)

    for (color, polys_color) in polys_by_color
        vertices = Vector{NTuple{3, Float64}}()
        triangles = Vector{NTuple{4, Int}}()
        cidx = color_index[color]
        for pts in polys_color
            n = length(pts)
            base_index = length(vertices)
            for p in pts
                push!(vertices, (p.x, p.y, z0))
            end
            for p in pts
                push!(vertices, (p.x, p.y, z1))
            end

            top0 = base_index + n
            bot0 = base_index

            for i in 2:(n - 1)
                push!(triangles, (top0, base_index + n + i - 1, base_index + n + i, cidx))
                push!(triangles, (bot0, base_index + i, base_index + i - 1, cidx))
            end

            for i in 1:n
                ni = i == n ? 1 : i + 1
                bi = base_index + i - 1
                bn = base_index + ni - 1
                ti = base_index + n + i - 1
                tn = base_index + n + ni - 1
                push!(triangles, (bi, bn, tn, cidx))
                push!(triangles, (bi, tn, ti, cidx))
            end
        end
        push!(objects, (color=color, vertices=vertices, triangles=triangles))
    end

    model_lines = String[]
    push!(model_lines, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    push!(model_lines, "<model xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\" unit=\"millimeter\">")
    push!(model_lines, "  <resources>")
    push!(model_lines, "    <basematerials id=\"1\">")
    for (i, c) in enumerate(colors)
        push!(model_lines, "      <base name=\"c$(i - 1)\" displaycolor=\"$(c)\"/>")
    end
    push!(model_lines, "    </basematerials>")
    for (obj_index, obj) in enumerate(objects)
        push!(model_lines, "    <object id=\"$(obj_index)\" type=\"model\">")
        push!(model_lines, "      <mesh>")
        push!(model_lines, "        <vertices>")
        for v in obj.vertices
            push!(model_lines, "          <vertex x=\"$(v[1])\" y=\"$(v[2])\" z=\"$(v[3])\"/>")
        end
        push!(model_lines, "        </vertices>")
        push!(model_lines, "        <triangles>")
        for t in obj.triangles
            push!(model_lines, "          <triangle v1=\"$(t[1])\" v2=\"$(t[2])\" v3=\"$(t[3])\" pid=\"1\" p1=\"$(t[4])\"/>")
        end
        push!(model_lines, "        </triangles>")
        push!(model_lines, "      </mesh>")
        push!(model_lines, "    </object>")
    end
    push!(model_lines, "  </resources>")
    push!(model_lines, "  <build>")
    for obj_index in 1:length(objects)
        push!(model_lines, "    <item objectid=\"$(obj_index)\"/>")
    end
    push!(model_lines, "  </build>")
    push!(model_lines, "</model>")

    mkpath(dirname(output_path))
    isfile(output_path) && rm(output_path)

    mktempdir() do dir
        mkpath(joinpath(dir, "3D"))
        mkpath(joinpath(dir, "_rels"))
        open(joinpath(dir, "3D", "3dmodel.model"), "w") do io
            write(io, join(model_lines, "\n"))
        end
        open(joinpath(dir, "[Content_Types].xml"), "w") do io
            write(io,
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" *
                "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\n" *
                "  <Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>\n" *
                "  <Default Extension=\"model\" ContentType=\"application/vnd.ms-package.3dmanufacturing-3dmodel+xml\"/>\n" *
                "</Types>\n")
        end
        open(joinpath(dir, "_rels", ".rels"), "w") do io
            write(io,
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" *
                "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n" *
                "  <Relationship Target=\"/3D/3dmodel.model\" Id=\"rel0\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\"/>\n" *
                "</Relationships>\n")
        end
        zip_path = Sys.which("zip")
        zip_path === nothing && error("zip command not found on PATH; required to create .3mf container")
        cd(dir) do
            run(`$(zip_path) -r -q $(abspath(output_path)) .`)
        end
    end

    return output_path
end
