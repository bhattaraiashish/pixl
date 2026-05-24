Simp :: #import "Simp";

Primitive_Sphere :: struct
{
    radius: float;
}

Primitive_Disk :: struct
{
    radius: float;
}

Primitive_Box :: struct
{
    vmin: Vector3;
    vmax: Vector3;
}

Primitive_Mesh :: struct
{
    indices: []u32;
    vertices: []Vertex3;
    blas: Acceleration_Structure;
}

Primitive_Shape :: union
{
    sphere : Primitive_Sphere;
    disk   : Primitive_Disk;
    box    : Primitive_Box;
    mesh   : Primitive_Mesh;
}

Primitive :: struct
{
    type        : Primitive_Type;
    xform       : Transform;
    material_id : MaterialID;
    shape       : Primitive_Shape;
}

Bitmap :: Simp.Bitmap;

Texture_Format :: enum u32
{
    UNKNOWN;
    R8_UNORM;
    R8G8B8_UNORM;
    R32_FLOAT;
    R32G32B32_FLOAT;
}

Texture2D :: struct
{
    format    : Texture_Format;
    width     : u32;
    height    : u32;
    stride    : u32;
    scale     : Vector2;
    constants : [2]Vector3;
    data      : *u8;
}

Material :: struct
{
    color                : Texture2D;
    diffuse_roughness    : Texture2D;

    specular_ior         : Texture2D;
    specular_weight      : Texture2D;
    specular_roughness   : Texture2D;
    specular_anisotropic : Texture2D;
    specular_color       : Texture2D;

    transmission_weight  : Texture2D;
    transmission_color   : Texture2D;
    transmission_depth   : Texture2D;
    transmission_scatter : Texture2D;

    metallic             : Texture2D;
    reflectance          : Texture2D;
    edge_tint            : Texture2D;
    falloff              : Texture2D;

    geometry_opacity     : Texture2D;

    emission_strength    : Texture2D;
    emission_color       : Texture2D;
}

PathTracerConfig :: struct
{
    width           : int = 1280;
    height          : int = 720;
    multisamples    : u32 = 16;
    max_depth       : s32 = 5;
    flat_background := false;
}

Tone_Map_Type :: enum u32
{
    LINEAR;
    REINHARD;
}

Path_Statistics :: struct
{
    n_bounces : u32 #align 64;
    n_bvh_visits : u32;
}

Scene :: struct
{
    camera:  Camera;
    config:  PathTracerConfig;
    tonemap: Tone_Map_Type = .REINHARD;

    bitmap:  Bitmap;
    bounces_heatmap:  Bitmap;
    bvh_visits_heatmap: Bitmap;

    materials   : [..]Material;
    environment : Texture2D;
    flat_background_color := Spectrum.{0.5, 0.5, 0.5};
    exposure := 2.0; // @todo: to Camera?

    primitives : [..]Primitive;
    bboxes     : [..]Box3;

    tlas       : Acceleration_Structure;
    mapped     : [..]Primitive;

    rgbx_mem   : *void;
    rgbx       : []Vector4;

    statistics_mem : *void;
    statistics : []Path_Statistics;

    cancel_rendering := false;
}

Hit_Face :: enum u32
{
    FRONT;
    BACK;
}

Hit_Info :: struct
{
    p            : Vector3;
    t            : float;
    n            : Vector3;
    dpdu         : Vector3;
    dpdv         : Vector3;
    u            : float;
    v            : float;
    face         : Hit_Face;
    material_id  : MaterialID;
}

#scope_file

intersect_primitive :: (primitive: Primitive, world_origin: Vector3, world_dir: Vector3, tmin: float, tmax: float) -> Hit_Info
{
    origin := transform_point(primitive.xform.inverse, world_origin);
    dir    := transform_vector(primitive.xform.inverse, world_dir);

    intersect: Intersect_Info = ---;

    if #complete primitive.type ==
    {
        case .SPHERE;
            intersect = intersect_sphere(primitive.shape.sphere.radius, origin, dir, tmin, tmax);

        case .DISK;
            intersect = intersect_disk(primitive.shape.disk.radius, origin, dir, tmin, tmax);

        case .BOX;
            intersect = intersect_box(primitive.shape.box.vmin, primitive.shape.box.vmax, origin, dir, tmin, tmax);

        case .MESH;
            intersect = intersect_mesh(primitive.shape.mesh.indices, primitive.shape.mesh.vertices, primitive.shape.mesh.blas, origin, dir, tmin, tmax);
    }

    info := Hit_Info.{ t = -1 };

    if (intersect.t >= 0.0)
    {
        inverse := make_matrix4(primitive.xform.inverse);
        // @todo: May be transform the minimum hit only??
        info.p            = transform_point(primitive.xform.forward, intersect.p);
        info.n            = transform_vector(transpose(inverse), intersect.n);
        info.dpdu         = transform_vector(primitive.xform.forward, intersect.dpdu);
        info.dpdv         = transform_vector(primitive.xform.forward, intersect.dpdv);
        info.n            = normalize(info.n);
        info.dpdu         = normalize(info.dpdu); // @todo: are these necessary to normalize?
        info.dpdv         = normalize(info.dpdv);
        info.t            = intersect.t;
        info.u            = intersect.u;
        info.v            = intersect.v;
        info.face         = .FRONT;
        info.material_id  = primitive.material_id;

        if (dot(world_dir, info.n) > 0.0)
        {
            info.n    = -info.n;
            info.face = .BACK;
        }
    }

    return info;
}

#scope_export

intersect_tlas :: (nodes: []BVH_Node, primitives: []Primitive, origin: Vector3, dir: Vector3, tmin: float, tmax: float) -> Hit_Info, u32
{
    visited : u32 = 0;
    info := Hit_Info.{ t = -1 };

    if nodes.count
    {
        nodes_stack : [64]u32 = ---;

        top : u32 = 1;
        nodes_stack[0] = 0;
        inv_dir := Vector3.{1.0 / dir.x, 1.0 / dir.y, 1.0 / dir.z};

        while top > 0
        {
            top -= 1;
            node := nodes[nodes_stack[top]];

            visited += 1;

            if (hits(origin, inv_dir, node.bbox, tmin, tmax))
            {
                if (node.num_primitives)
                {
                    for 0..node.num_primitives-1
                    {
                        primitive := primitives[node.first_child_or_primitive + it];
                        current   := intersect_primitive(primitive, origin, dir, tmin, tmax);
                        if (current.t >= 0.0)
                        {
                            tmax = current.t;
                            info = current;
                        }
                    }
                }
                else
                {
                    assert(top + 2 < nodes_stack.count);
                    nodes_stack[top + 0] = node.first_child_or_primitive + 1;
                    nodes_stack[top + 1] = node.first_child_or_primitive + 0;
                    top += 2;
                }
            }
        }
    }

    return info, visited;
}

intersect_scene :: (scene: Scene, origin: Vector3, dir: Vector3, tmin: float, tmax: float) -> Hit_Info, u32
{
    hit, num_visited := intersect_tlas(scene.tlas.nodes, scene.mapped, origin, dir, tmin, tmax);
    return hit, num_visited;
}
