using Colors
using Random
using Printf

const EPSILON = 1e-6
const INV_EPSILON = 1e6

struct Point
    x::Float64
    y::Float64
end

Base.:+(a::Point, b::Point) = Point(a.x + b.x, a.y + b.y)
Base.:-(a::Point, b::Point) = Point(a.x - b.x, a.y - b.y)
Base.:*(a::Point, s::Real) = Point(a.x * s, a.y * s)
Base.:/(a::Point, s::Real) = Point(a.x / s, a.y / s)

mod1(i::Int, n::Int) = ((i - 1) % n) + 1

struct GridLine
    angle::Int
    index::Float64
end

struct Tile
    dual_pts::Vector{Point}
    mean::Point
    area_key::String
    angles_key::String
    num_vertices::Int
end

struct TilingOptions
    symmetry::Int
    radius::Float64
    pattern::Float64
    pan::Float64
    disorder::Float64
    random_seed::Float64
    zoom::Float64
    rotate::Float64
    show_stroke::Bool
    stroke::Float64
    reverse_colors::Bool
    orientation_coloring::Bool
    hue::Float64
    hue_range::Float64
    contrast::Float64
    sat::Float64
    width::Int
    height::Int
    cropwidth::Int
    cropheight::Int
end

function TilingOptions(; symmetry::Int=5,
    radius::Real=75.0,
    pattern::Real=0.2,
    pan::Real=0.0,
    disorder::Real=0.0,
    random_seed::Real=0.0,
    zoom::Real=1.0,
    rotate::Real=0.0,
    show_stroke::Bool=false,
    stroke::Real=128.0,
    reverse_colors::Bool=false,
    orientation_coloring::Bool=false,
    hue::Real=342.0,
    hue_range::Real=62.0,
    contrast::Real=36.0,
    sat::Real=74.0,
    width::Int=1000,
    height::Int=1000,
    cropwidth::Int=width,
    cropheight::Int=height)
    return TilingOptions(symmetry, Float64(radius), Float64(pattern), Float64(pan),
        Float64(disorder), Float64(random_seed), Float64(zoom), Float64(rotate),
        show_stroke, Float64(stroke), reverse_colors, orientation_coloring,
        Float64(hue), Float64(hue_range), Float64(contrast), Float64(sat),
        width, height, cropwidth, cropheight)
end

approx(x) = round(x * INV_EPSILON) / INV_EPSILON

dist2(x1, y1, x2, y2) = (x2 - x1)^2 + (y2 - y1)^2

function steps_from_radius(radius::Float64, symmetry::Int)
    raw = radius / (symmetry - 1) - 1
    return 2 * round(Int, raw / 2) + 1
end

function make_1d_grid(steps::Int)
    vals = collect(0:steps-1) .- (steps - 1) / 2
    sort(vals; by=abs)
end

function sincos_table(symmetry::Int)
    table = Vector{Tuple{Float64, Float64}}(undef, symmetry)
    for i in 0:symmetry-1
        angle = 2π * i / symmetry
        table[i + 1] = (sin(angle), cos(angle))
    end
    return table
end

function offsets_for(symmetry::Int, pattern::Float64, disorder::Float64, random_seed::Float64, pan::Float64, rotate::Float64, steps::Int)
    offsets = fill(pattern, symmetry)
    if disorder > 0
        seed = hash(("random seed", symmetry, random_seed))
        rng = MersenneTwister(seed)
        offsets = offsets .+ disorder .* (rand(rng, symmetry) .- 0.5)
    end
    if pan != 0
        rot = deg2rad(rotate)
        shift = [cos(2π * i / symmetry) * cos(rot) - sin(2π * i / symmetry) * sin(rot) for i in 0:symmetry-1]
        offsets = offsets .- steps .* pan .* shift
    end
    return offsets
end

function grid_lines(symmetry::Int, steps::Int, offsets::Vector{Float64})
    lines = GridLine[]
    grid_vals = make_1d_grid(steps)
    for i in 1:symmetry
        for n in grid_vals
            idx = n + (offsets[i] - floor(offsets[i]))
            push!(lines, GridLine(i - 1, idx))
        end
    end
    return lines
end

function intersection_points(lines::Vector{GridLine}, symmetry::Int, steps::Int,
    spacing::Float64, rotate::Float64, width::Int, height::Int, offsets::Vector{Float64})
    table = sincos_table(symmetry)
    pts = Dict{Tuple{Float64, Float64}, Any}()
    rot = deg2rad(rotate)
    for i in 1:length(lines)
        line1 = lines[i]
        for j in i+1:length(lines)
            line2 = lines[j]
            line1.angle < line2.angle || continue
            s1, c1 = table[line1.angle + 1]
            s2, c2 = table[line2.angle + 1]
            s12 = s1 * c2 - c1 * s2
            abs(s12) > EPSILON || continue
            x = (line2.index * s1 - line1.index * s2) / s12
            y = (line2.index * c1 - line1.index * c2) / (-s12)
            xprime = x * cos(rot) - y * sin(rot)
            yprime = x * sin(rot) + y * cos(rot)
            if abs(xprime * spacing) > width / 2 + spacing || abs(yprime * spacing) > height / 2 + spacing
                continue
            end
            d2 = dist2(x, y, 0.0, 0.0)
            if (steps == 1 && d2 <= (0.5 * steps)^2) || d2 <= (0.5 * (steps - 1))^2
                key = (approx(x), approx(y))
                if haskey(pts, key)
                    entry = pts[key]
                    if !any(l -> l.angle == line1.angle && l.index == line1.index, entry.lines)
                        push!(entry.lines, line1)
                    end
                    if !any(l -> l.angle == line2.angle && l.index == line2.index, entry.lines)
                        push!(entry.lines, line2)
                    end
                else
                    pts[key] = (x=x, y=y, lines=[line1, line2])
                end
            end
        end
    end
    return pts
end

function dual_tiles(pts::Dict{Tuple{Float64, Float64}, Any}, symmetry::Int, offsets::Vector{Float64})
    table = sincos_table(symmetry)
    tiles = Tile[]
    for entry in values(pts)
        angles = [l.angle * 2π / symmetry for l in entry.lines]
        angles2 = map(a -> mod(a + π, 2π), angles)
        merged = vcat(angles, angles2)
        merged = sort(unique(approx.(merged)))
        offset_pts = [Point(entry.x + EPSILON * -sin(a), entry.y + EPSILON * cos(a)) for a in merged]
        median_pts = Point[]
        for i in 1:length(offset_pts)
            p0 = offset_pts[i]
            p1 = offset_pts[mod1(i + 1, length(offset_pts))]
            push!(median_pts, Point((p0.x + p1.x) / 2, (p0.y + p1.y) / 2))
        end
        dual_pts = Point[]
        mean = Point(0, 0)
        for mypt in median_pts
            xd = 0.0
            yd = 0.0
            for i in 0:symmetry-1
                s, c = table[i + 1]
                k = floor(mypt.x * c + mypt.y * s - offsets[i + 1])
                xd += k * c
                yd += k * s
            end
            dp = Point(xd, yd)
            push!(dual_pts, dp)
            mean += dp
        end
        mean = mean / length(dual_pts)
        area = 0.0
        for i in 1:length(dual_pts)
            p0 = dual_pts[i]
            p1 = dual_pts[mod1(i + 1, length(dual_pts))]
            area += 0.5 * (p0.x * p1.y - p0.y * p1.x)
        end
        area_key = string(round(area * 1000) / 1000)
        angles_key = join(string.(merged), ",")
        push!(tiles, Tile(dual_pts, mean, area_key, angles_key, length(merged)))
    end
    return tiles
end

function hsluv_to_rgb(h::Float64, s::Float64, l::Float64)
    if isdefined(Colors, :HSLuv)
        return convert(RGB, Colors.HSLuv(h, s, l))
    end
    return RGB(Colors.HSL(mod(h, 360) / 360, clamp(s / 100, 0, 1), clamp(l / 100, 0, 1)))
end

function rgb_hex(c::RGB)
    r = clamp(round(Int, c.r * 255), 0, 255)
    g = clamp(round(Int, c.g * 255), 0, 255)
    b = clamp(round(Int, c.b * 255), 0, 255)
    return @sprintf("#%02x%02x%02x", r, g, b)
end

function tile_palette(tiles::Vector{Tile}, opts::TilingOptions)
    if isempty(tiles)
        return Dict{String, RGB}()
    end
    function key(tile::Tile)
        return opts.orientation_coloring ? tile.angles_key : tile.area_key
    end
    proto = Dict{String, Tile}()
    for tile in tiles
        k = key(tile)
        if !haskey(proto, k)
            proto[k] = tile
        end
    end
    proto_tiles = sort(collect(values(proto)); by=t -> t.num_vertices)
    n = length(proto_tiles)
    start = (opts.hue + opts.hue_range, opts.sat, 50 + opts.contrast)
    fin = (opts.hue - opts.hue_range, opts.sat, 50 - opts.contrast)
    colors = Dict{String, RGB}()
    denom = max(1, n - 1/2)
    for (i, tile) in enumerate(proto_tiles)
        t = (i - 1) / denom
        h = mod(start[1] + t * (fin[1] - start[1]), 360)
        s = start[2] + t * (fin[2] - start[2])
        l = start[3] + t * (fin[3] - start[3])
        colors[key(tile)] = hsluv_to_rgb(h, s, l)
    end
    if opts.reverse_colors
        keys_sorted = map(key, proto_tiles)
        values_sorted = reverse([colors[k] for k in keys_sorted])
        colors = Dict(zip(keys_sorted, values_sorted))
    end
    return colors
end

"""
    generate_tiling_svg(output_path; kwargs...)

Generate a de Bruijn multigrid quasiperiodic tiling SVG based on the
Pattern Collider web version logic.
"""
function generate_tiling_svg(output_path::AbstractString; kwargs...)
    opts = TilingOptions(; kwargs...)
    steps = steps_from_radius(opts.radius, opts.symmetry)
    spacing = opts.zoom * min(opts.width, opts.height) / steps
    pre_factor = spacing * (2π / opts.symmetry) / π
    pre_factor *= opts.zoom
    offsets = offsets_for(opts.symmetry, opts.pattern, opts.disorder, opts.random_seed, opts.pan, opts.rotate, steps)
    lines = grid_lines(opts.symmetry, steps, offsets)
    pts = intersection_points(lines, opts.symmetry, steps, spacing, opts.rotate, opts.width, opts.height, offsets)
    tiles = dual_tiles(pts, opts.symmetry, offsets)
    palette = tile_palette(tiles, opts)
    mkpath(dirname(output_path))
    rot = deg2rad(opts.rotate)
    pan_px = -opts.zoom * min(opts.width, opts.height) * opts.pan
    stroke_color = rgb_hex(RGB(opts.stroke / 255, opts.stroke / 255, opts.stroke / 255))
    open(output_path, "w") do io
        println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        crop_w = clamp(opts.cropwidth, 1, opts.width)
        crop_h = clamp(opts.cropheight, 1, opts.height)
        crop_x = (opts.width - crop_w) / 2
        crop_y = (opts.height - crop_h) / 2
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$(crop_w)\" height=\"$(crop_h)\" viewBox=\"$(crop_x) $(crop_y) $(crop_w) $(crop_h)\">")
        for tile in tiles
            key = opts.orientation_coloring ? tile.angles_key : tile.area_key
            color = rgb_hex(get(palette, key, RGB(1, 1, 1)))
            pts_scaled = [Point(pre_factor * p.x, pre_factor * p.y) for p in tile.dual_pts]
            pts_rot = [Point(p.x * cos(rot) - p.y * sin(rot), p.x * sin(rot) + p.y * cos(rot)) for p in pts_scaled]
            pts_final = [Point(p.x + opts.width / 2 + pan_px, p.y + opts.height / 2) for p in pts_rot]
            pts_str = join([string(p.x, ",", p.y) for p in pts_final], " ")
            if opts.show_stroke
                println(io, "<polygon points=\"$pts_str\" fill=\"$color\" stroke=\"$stroke_color\" stroke-width=\"1\"/>")
            else
                println(io, "<polygon points=\"$pts_str\" fill=\"$color\" stroke=\"none\"/>")
            end
        end
        println(io, "</svg>")
    end
    return output_path
end
