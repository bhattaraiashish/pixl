

//------------------------------------------------------------------------

Box3 :: struct
{
    vmin: Vector3;
    vmax: Vector3;
}

Box3_Empty :: Box3.{
    vmin = .{FLOAT32_INFINITY, FLOAT32_INFINITY, FLOAT32_INFINITY},
    vmax = .{-FLOAT32_INFINITY, -FLOAT32_INFINITY, -FLOAT32_INFINITY}
};

Vertex3 :: struct
{
    p  : Vector3;
    uv : Vector2;
    n  : Vector3;
    t  : Vector3;
    b  : Vector3;
}

Ray :: struct
{
    origin : Vector3;
    dir    : Vector3;
}

BVH_Node :: struct
{
    bbox                     : Box3;
    first_child_or_primitive : u32;
    num_primitives           : u32;
}

Acceleration_Structure :: struct
{
    nodes   : []BVH_Node;
    indices : []u32;
}

Transform :: struct
{
    forward: Matrix4x3;
    inverse: Matrix4x3;
}

MaterialID  :: #type,distinct u32;
PrimitiveID :: #type,distinct u32;

// @todo: move to camera.jai??

FILTER_SIZE :: 1023;

Filter_Type :: enum
{
    BOX;
    BLACKMAN_HARRIS;
}

Filter :: struct
{
    type  := Filter_Type.BLACKMAN_HARRIS;
    width := 1.5;
}

//------------------------------------------------------------------------
// Coordinate System (Right Handedness)
// Right   : +X
// Up      : +Y
// Forward : +Z

Camera_Type :: enum u32
{
    PERSPECTIVE;
    ORTHOGRAPHIC;
}

Camera :: struct
{
    // @todo: add orthographic/spherical camera?
    type               := Camera_Type.PERSPECTIVE;
    position           : Vector3;
    orientation        : Quaternion;
    fov                := 0.17;
    aspect_ratio       := 1.0;
    focus_distance     := 5.0;
    lens_radius        := 0.0;
    filter             : Filter;

    // constructed from above parameters
    // @todo: cleanup; generate them before rendering!!
    xform              : Matrix4;
    dxdu               : Vector3;
    dydv               : Vector3;

    // @todo: move somewhere else??
    filter_lut         : [FILTER_SIZE]float;
}

//------------------------------------------------------------------------

transform_box :: (t: Matrix4x3, box: Box3) -> Box3
{
    center := 0.5 * (box.vmin + box.vmax);
    extent := 0.5 * (box.vmax - box.vmin);

    rcenter := transform_point(t, center);
    half    := Vector3.{0, 0, 0};

    half.x       = abs(extent.x * t.floats[0 + 0]) + abs(extent.y * t.floats[0 + 1]) + abs(extent.z * t.floats[0 + 2]);
    half.y       = abs(extent.x * t.floats[4 + 0]) + abs(extent.y * t.floats[4 + 1]) + abs(extent.z * t.floats[4 + 2]);
    half.z       = abs(extent.x * t.floats[8 + 0]) + abs(extent.y * t.floats[8 + 1]) + abs(extent.z * t.floats[8 + 2]);

    return Box3.{rcenter - half, rcenter + half};
}

box_union :: (b: Box3, p: Vector3) -> Box3
{
    ret: Box3;
    ret.vmin = min(b.vmin, p);
    ret.vmax = max(b.vmax, p);
    return ret;
}

box_union :: (b1: Box3, b2: Box3) -> Box3
{
    ret: Box3;
    ret.vmin = min(b1.vmin, b2.vmin);
    ret.vmax = max(b1.vmax, b2.vmax);
    return ret;
}

fract :: inline (x: float) -> float { return x - floor(x); }

mix :: (x: $T, y: T, t: float) -> T
{
    return x * (1.0 - t) + y * t;
}

average :: inline (s: Spectrum) -> float
{
    return (s.x + s.y + s.z) / 3.0;
}

//------------------------------------------------------------------------

read_lookup_table_1D :: (lookup: []$T, w: int, u: float) -> T
{
    up := u * w - 0.5;
    u0 := clamp(up.(int), 0, w - 1);
    u1 := min(u0 + 1, w - 1);
    uf := fract(up);
    x  := lerp(lookup[u0], lookup[u1], uf);
    return x;
}

read_lookup_table_2D :: (lookup: []$T, w: int, h: int, u: float, v: float) -> T
{
    up := u * w.(float) - 0.5;
    vp := v * h.(float) - 0.5;
    u0 := clamp(up.(int), 0, w - 1);
    v0 := clamp(vp.(int), 0, h - 1);
    u1 := min(u0 + 1, w - 1);
    v1 := min(v0 + 1, h - 1);
    uf := fract(up);
    vf := fract(vp);
    y0 := lerp(lookup[v0 * w + u0], lookup[v0 * w + u1], uf);
    y1 := lerp(lookup[v1 * w + u0], lookup[v1 * w + u1], uf);
    x  := lerp(y0, y1, vf);
    return x;
}

read_lookup_table_3D :: (lookup: []$T, width: int, height: int, depth: int, u: float, v: float, w: float) -> T
{
    up   := u * width.(float)  - 0.5;
    vp   := v * height.(float) - 0.5;
    wp   := w * depth.(float)  - 0.5;
    u0   := clamp(up.(int), 0, width  - 1);
    v0   := clamp(vp.(int), 0, height - 1);
    w0   := clamp(wp.(int), 0, depth  - 1);
    u1   := min(u0 + 1, width  - 1);
    v1   := min(v0 + 1, height - 1);
    w1   := min(w0 + 1, depth  - 1);
    uf   := fract(up);
    vf   := fract(vp);
    wf   := fract(wp);
    z0y0 := lerp(lookup[w0 * width * height + v0 * width + u0], lookup[w0 * width * height + v0 * width + u1], uf);
    z0y1 := lerp(lookup[w0 * width * height + v1 * width + u0], lookup[w0 * width * height + v1 * width + u1], uf);
    z1y0 := lerp(lookup[w1 * width * height + v0 * width + u0], lookup[w1 * width * height + v0 * width + u1], uf);
    z1y1 := lerp(lookup[w1 * width * height + v1 * width + u0], lookup[w1 * width * height + v1 * width + u1], uf);
    z0   := lerp(z0y0, z0y1, vf);
    z1   := lerp(z1y0, z1y1, vf);
    return lerp(z0, z1, wf);
}

#import "Math";
