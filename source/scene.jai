#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Atomics";
#import "File";
#import "File_Utilities";
#import "Math";
#import "String";
#import "Thread";
#import "System";
#import "Srgb";
#import "Hash_Table";
#import "Hash";
#import "Command_Line";
#import "stb_image";
#import "Random";
#import "Arena";

#import "BxDF";
#import "PathNoise";

#load "common.jai";
#load "intersect.jai";
#load "primitives.jai";
#load "async.jai";

load_bunny :: () -> Primitive_Mesh, Matrix4
{
    theta := 20.0 / 360.0 * 2 * PI;

    rot: Quaternion;

    set_from_axis_and_angle(*rot, 0, 1, 0, theta);

    scale := 300.0;

    bunny := load_obj_model("data/bunny/bunny.obj");
    xform := make_translation_matrix4(.{270, 90, 270}) * rotation_matrix(Matrix4, rot) * make_scale_matrix4(.{scale, scale, scale});

    return bunny, xform;
}

load_monkey :: () -> Primitive_Mesh, Matrix4
{
    theta := 30.0 / 360.0 * 2 * PI;

    rot: Quaternion;

    set_from_axis_and_angle(*rot, 0, 1, 0, theta);

    scale := 200.0;

    monkey := load_obj_model("data/spot/spot_triangulated.obj");
    xform  := make_translation_matrix4(.{270, 140, 270}) * rotation_matrix(Matrix4, rot) * make_scale_matrix4(.{scale, scale, scale});

    return monkey, xform;
}

load_dragon :: () -> Primitive_Mesh, Matrix4
{
    theta := 90.0 / 360.0 * 2 * PI;

    rot: Quaternion;

    set_from_axis_and_angle(*rot, 0, 1, 0, theta);

    scale := 500.0;

    dragon := load_obj_model("data/dragon/dragon.obj");
    xform  := make_translation_matrix4(.{270, 140, 270}) * rotation_matrix(Matrix4, rot) * make_scale_matrix4(.{scale, scale, scale});

    return dragon, xform;
}

load_backdrop :: () -> Primitive_Mesh, Matrix4
{
    scale := 2.0;
    position := Vector3.{0, 0, -10.1};
    backdrop := load_obj_model("data/backdrop/Backdrop.obj");
    xform    := make_translation_matrix4(position) * make_scale_matrix4(.{scale, scale, scale});
    return backdrop, xform;
}

load_shaderball :: () -> Primitive_Mesh, Primitive_Mesh, Matrix4
{
    scale := 0.5;
    position := Vector3.{0, 0, 0};

    internals := load_obj_model("data/shaderball/shader_ball_bmps_inner.obj");
    externals := load_obj_model("data/shaderball/shader_ball_bmps_outer.obj");

    theta := -30.0 / 360.0 * 2 * PI;

    orientation: Quaternion;
    set_from_axis_and_angle(*orientation, 0, 1, 0, theta);

    xform    := make_translation_matrix4(position) * rotation_matrix(Matrix4, orientation) * make_scale_matrix4(.{scale, scale, scale});
    return internals, externals, xform;
}

Test_Scene :: enum
{
    cornell_box;
    cornell_dragon;
    cornell_monkey;
    white_furnace_test;
    shaderball_test;

    metal_test;
    diffuse_test;
    specular_test_1;
    specular_test_2;
    glossy_diffuse_test;
    glass_test_1;
    glass_test_2;
    envmap_test;
}

TEST_SPHERES_WIDTH  :: 10;
TEST_SPHERES_HEIGHT :: 6;

test_scene :: (using scene: *Scene, $parameterize_material : #type(m: *Material, x: int, y: int, xp: float, yp: float))
{
    camera.fov         = 45.0 / 360.0;
    camera.position    = .{0, 0, -1};
    camera.orientation = .{};
    camera.type        = .ORTHOGRAPHIC;
    environment        = load_texture_from_file("data/envmap/golden_gate_hills_2k.hdr");
    exposure           = 2;

    radius            := 0.25;
    spacing           := 2 * radius + 0.1;
    start_x           := -2.8;
    start_y           :=  1.6;

    checkerboard_texture  := create_checkerboard_texture(Vector3.{1, 1, 1}, .{0.9, 0.1, 0.1}, .{40, 40});
    checkerboard_material := create_lambertian_material(scene, checkerboard_texture);

    add_box(scene, Matrix4_Identity, .{-6, -6, 0.5}, .{6, 6, 0.6}, checkerboard_material);

    for y:0..TEST_SPHERES_HEIGHT-1
    {
        center  := Vector3.{start_x, start_y, 0.0};
        start_y -= spacing;

        for x:0..TEST_SPHERES_WIDTH-1
        {
            parameter_1 := x.(float) / (TEST_SPHERES_WIDTH - 1).(float);
            parameter_2 := y.(float) / (TEST_SPHERES_HEIGHT - 1).(float);

            material_id, material := create_material(scene);
            parameterize_material(material, x, y, parameter_1, parameter_2);

            add_sphere(scene, center, radius, material_id);
            center.x += spacing;
        }
    }
}

load_test_scene :: (using scene: *Scene, type: Test_Scene)
{
    envimg := "data/envmap/citrus_orchard_road_puresky_2k.hdr";
    envtex := load_texture_from_file(envimg);

    setup_cornell_background :: () #expand
    {
        camera.fov      = 40.0 / 360.0;
        camera.position = .{278, 278, -800};
        environment     = create_constant_texture(.{0, 0, 0});

        red   := create_lambertian_material(scene, create_constant_texture(.{0.65, 0.05, 0.05}));
        white := create_lambertian_material(scene, create_constant_texture(.{0.73, 0.73, 0.73}));
        green := create_lambertian_material(scene, create_constant_texture(.{0.12, 0.45, 0.15}));
        light := create_emission_material(scene, create_constant_texture(.{15, 15, 15}));

        add_box(scene, Matrix4_Identity, .{213, 554, 227}, .{343, 554.01, 332}, light); // top
        add_box(scene, Matrix4_Identity, .{0, 0, 0}, .{0.01, 555, 555}, green);         // left
        add_box(scene, Matrix4_Identity, .{555, 0, 0}, .{555.01, 555, 555}, red);       // right
        add_box(scene, Matrix4_Identity, .{0, 0, 0}, .{555, 0.01, 555}, white);         // bottom
        add_box(scene, Matrix4_Identity, .{0, 0, 555}, .{555, 555, 555.01}, white);     // back
        add_box(scene, Matrix4_Identity, .{0, 555, 0}, .{555, 555.01, 555}, white);     // top
    }

    if #complete type ==
    {
        case .cornell_box;
            setup_cornell_background();

            theta1 := 18.0 / 360.0 * 2 * PI;
            theta2 := -15.0 / 360.0 * 2 * PI;

            rot1, rot2: Quaternion;

            set_from_axis_and_angle(*rot1, 0, 1, 0, theta1);
            set_from_axis_and_angle(*rot2, 0, 1, 0, theta2);

            xform1 := rotation_matrix(Matrix4, rot1);
            xform2 := rotation_matrix(Matrix4, rot2);

            white := create_lambertian_material(scene, create_constant_texture(.{0.73, 0.73, 0.73}));
            metal := create_metal_material(scene, roughness=0.3, edge_tint=.{1.000, 0.735, 0.353}, reflectance=.{0.993, 1.000, 1.000});

            add_translated_box(scene, xform1, .{260, 0,  65}, .{425, 165, 225}, white);
            add_translated_box(scene, xform2, .{130, 0, 295}, .{290, 330, 455}, metal);

        case .cornell_dragon;
            setup_cornell_background();

            dragon_material := create_plastic_material(scene, create_constant_texture(.{0.3, 0.8, 0.7}));
            dragon, xform   := load_dragon();

            add_mesh(scene, xform, dragon, dragon_material);

        case .cornell_monkey;
            setup_cornell_background();

            monkey, xform := load_monkey();
            white := create_lambertian_material(scene, create_constant_texture(.{0.73, 0.73, 0.73}));

            add_mesh(scene, xform, monkey, white);

        case .white_furnace_test;
            camera.fov         = 45.0 / 360.0;
            camera.position    = .{0, 0, -5};
            camera.orientation = .{};
            environment        = create_constant_texture(.{1, 1, 1});
            exposure           = 1.0;

            center  := Vector3.{0.0, 0.0, 0.0};
            radius  := 1.0;

            id, material        := create_material(scene);
            material.color       = create_constant_texture(.{1, 1, 1});
            material.metallic   = create_constant_texture(0.0);
            material.diffuse_roughness    = create_constant_texture(0.0);
            material.specular_ior         = create_constant_texture(1.0);
            material.edge_tint        = create_constant_texture(.{1, 1, 1});
            material.specular_roughness   = create_constant_texture(0.8);
            material.specular_anisotropic = create_constant_texture(0.0);

            add_sphere(scene, center, radius, id);

        case .shaderball_test;
            camera.fov           = 40.0 / 360.0;
            camera.position      = .{0, 10, -10};
            set_from_axis_and_angle(*camera.orientation, Vector3.{1, 0, 0}, turns_to_radians(0.1));

            light := create_emission_material(scene, create_constant_texture(.{40, 40, 40}));

            environment = envtex;
            exposure    = 1;

            id, material        := create_material(scene);
            //material.color       = create_constant_texture(.{0.827, 0.686, 0.216});
            material.color       = create_constant_texture(.{0.699, 0.704, 0.671}); // Cobalt
            //material.color       = create_constant_texture(.{1, 1, 1});
            //material.color       = create_constant_texture(.{1.000, 0.735, 0.353}); // Gold
            material.metallic   = create_constant_texture(0.0);
            material.diffuse_roughness    = create_constant_texture(1.0);
            material.edge_tint        = create_constant_texture(.{0.34, 0.51, 0.36});
            //material.specular_color       = create_constant_texture(.{0.993, 1.000, 1.000}); // Gold
            //material.specular_tint        = create_constant_texture(.{0.727, 0.772, 0.823}); // Cobalt
            material.specular_roughness   = create_constant_texture(0.25);
            material.specular_anisotropic = create_constant_texture(0.0);
            //material.specular_ior         = create_constant_texture(0.1);
            material.transmission_weight         = create_constant_texture(0.0);
            material.absorption           = create_constant_texture(.{0.7, 0.3, 0.7});
            material.absorption_strength  = create_constant_texture(1.0);

            white      := create_lambertian_material(scene, create_constant_texture(.{1, 1, 1}));
            red        := create_lambertian_material(scene, create_constant_texture(.{0.65, 0.05, 0.05}));
            black, mat := create_lambertian_material(scene, create_constant_texture(.{0.01, 0.01, 0.01}));
            checker    := create_lambertian_material(scene, create_checkerboard_texture(Vector3.{0.9, 0.9, 0.9}, .{0.1, 0.1, 0.1}, .{40, 40}));

            earth      := load_texture_from_file("data/misc/earth.png", 3);
            textured   := create_lambertian_material(scene, earth);

            backdrop, backdrop_xform     := load_backdrop();
            internals, externals, shaderball_xform := load_shaderball();

            //add_box(scene, Matrix4_Identity, .{ -5, 10, -15 }, .{ -1, 10.01, -11 }, light);
            //add_box(scene, Matrix4_Identity, .{  1, 10, -15 }, .{  5, 10.01, -11 }, light);

            //add_sphere(scene, Vector3.{0, 2, 0}, 2, textured);

            add_mesh(scene, backdrop_xform, backdrop, checker);
            //add_sphere(scene, Vector3.{0, 2, 0}, 2, id);
            add_mesh(scene, shaderball_xform, internals, black);
            add_mesh(scene, shaderball_xform, externals, id);

        case .metal_test;
            metallic_parameter :: (material: *Material, x: int, y: int, paramx: float, paramy: float)
            {
                roughness   := paramx;
                anisotropic := 0.0;
                if (y < TEST_SPHERES_HEIGHT / 2)
                {
                    material.reflectance = create_constant_texture(.{1.000, 0.735, 0.353}); // Gold
                    material.edge_tint   = create_constant_texture(.{0.993, 1.000, 1.000}); // Gold
                    anisotropic          = saturate(paramy * 2.0);
                }
                else
                {
                    material.reflectance = create_constant_texture(.{0.617, 0.576, 0.540}); // Titanium
                    material.edge_tint   = create_constant_texture(.{0.695, 0.726, 0.770}); // Titanium
                    anisotropic          = saturate((paramy - 0.5) * 2.0);
                }
                material.metallic             = create_constant_texture(1.0);
                material.specular_roughness   = create_constant_texture(roughness);
                material.specular_anisotropic = create_constant_texture(anisotropic);
            }
            test_scene(scene, metallic_parameter);

        case .diffuse_test;
            ambient_parameter :: (material: *Material, x: int, y: int, roughness: float, alpha: float)
            {
                color                      := Vector3.{0, 0.7, 1.0};
                material.color              = create_constant_texture(color);
                material.specular_roughness = create_constant_texture(roughness);
                material.geometry_opacity   = create_constant_texture(alpha);
            }
            test_scene(scene, ambient_parameter);

        case .specular_test_1;
            glossy_diffuse_parameter :: (material: *Material, x: int, y: int, roughness: float, anisotropic: float)
            {
                color                        := Vector3.{0.18, 0.33, 0.77};
                material.color                = create_constant_texture(color);
                material.specular_roughness   = create_constant_texture(roughness);
                material.specular_anisotropic = create_constant_texture(anisotropic);
                material.specular_weight      = create_constant_texture(1.0);
            }
            test_scene(scene, glossy_diffuse_parameter);

        case .specular_test_2;
            glossy_diffuse_parameter :: (material: *Material, x: int, y: int, specular_t: float, roughness: float)
            {
                color                        := Vector3.{0.18, 0.33, 0.77};
                specular_ior                 := lerp(1.0, 3.0, specular_t);
                material.color                = create_constant_texture(color);
                material.specular_ior         = create_constant_texture(specular_ior);
                material.specular_roughness   = create_constant_texture(roughness);
                material.specular_anisotropic = create_constant_texture(0.0);
                material.specular_weight      = create_constant_texture(1.0);
            }
            test_scene(scene, glossy_diffuse_parameter);

        case .glossy_diffuse_test;
            glossy_diffuse_parameter :: (material: *Material, x: int, y: int, roughness: float, weight: float)
            {
                color                        := Vector3.{0.18, 0.33, 0.77};
                material.color                = create_constant_texture(color);
                material.specular_roughness   = create_constant_texture(roughness);
                material.specular_weight      = create_constant_texture(weight);
            }
            test_scene(scene, glossy_diffuse_parameter);

        case .glass_test_1;
            specular_reflection_parameter :: (material: *Material, x: int, y: int, specular_t: float, roughness: float)
            {
                specular_ior                 := lerp(1.0, 3.0, specular_t);
                material.specular_ior        = create_constant_texture(specular_ior);
                material.specular_roughness  = create_constant_texture(roughness);
                material.transmission_weight = create_constant_texture(1.0);
            }
            test_scene(scene, specular_reflection_parameter);

        case .glass_test_2;
            specular_transmission_parameter :: (material: *Material, x: int, y: int, roughness: float, anisotropic: float)
            {
                material.specular_roughness   = create_constant_texture(roughness);
                material.specular_anisotropic = create_constant_texture(anisotropic);
                material.specular_ior         = create_constant_texture(1.5);
                material.transmission_weight  = create_constant_texture(1.0);
            }
            test_scene(scene, specular_transmission_parameter);

        case .envmap_test;
            camera.fov         = 45.0 / 360.0;
            camera.position    = .{0, 0, -5};
            camera.orientation = .{};
            environment        = envtex;
    }
}

add_primitive :: (scene: *Scene, type: Primitive_Type) -> *Primitive
{
    primitive := array_add(*scene.primitives);
    primitive.type = type;
    return primitive;
}

add_sphere :: (scene: *Scene, xform: Matrix4, radius: float, material_id: MaterialID)
{
    if radius <= 0.0 then
        radius = 1;

    center := transform_point(xform, Vector3.{0, 0, 0});
    _, inv := inverse(xform);

    primitive := add_primitive(scene, .SPHERE);
    primitive.shape.sphere.radius = radius;
    primitive.xform.forward = make_matrix4x3(xform);
    primitive.xform.inverse = make_matrix4x3(inv);
    primitive.material_id = material_id;
}

add_sphere :: (scene: *Scene, center: Vector3, radius: float, material_id: MaterialID)
{
    xform := make_translation_matrix4(center);
    add_sphere(scene, xform, radius, material_id);
}

add_disk :: (scene: *Scene, p: Vector3, radius: float, material_id: MaterialID)
{
    if radius <= 0.0 then
        radius = 1;

    primitive := add_primitive(scene, .DISK);
    primitive.shape.disk.radius = radius;
    primitive.xform.forward = make_matrix4x3(make_translation_matrix4(p));
    primitive.xform.inverse = make_matrix4x3(make_translation_matrix4(-p));
    primitive.material_id = material_id;
}

add_box :: (scene: *Scene, xform: Matrix4, min: Vector3, max: Vector3, material_id: MaterialID)
{
    _, inv := inverse(xform);
    primitive := add_primitive(scene, .BOX);
    primitive.shape.box.vmin = min;
    primitive.shape.box.vmax = max;
    primitive.xform.forward = make_matrix4x3(xform);
    primitive.xform.inverse = make_matrix4x3(inv);
    primitive.material_id = material_id;
}

add_box :: (scene: *Scene, xform: Matrix4, material_id: MaterialID)
{
    add_box(scene, xform, Vector3.{-0.5, -0.5, -0.5}, Vector3.{0.5, 0.5, 0.5}, material_id);
}

add_translated_box :: (scene: *Scene, xform: Matrix4, p: Vector3, q: Vector3, material_id: MaterialID)
{
    pmin := min(p, q);
    pmax := max(p, q);

    dx := Vector3.{pmax.x - pmin.x, 0, 0};
    dy := Vector3.{0, pmax.y - pmin.y, 0};
    dz := Vector3.{0, 0, pmax.z - pmin.z};

    h := 0.5 * (pmin + pmax);
    d := 0.5 * (pmax - pmin);

    add_box(scene, make_translation_matrix4(h) * xform, -d, d, material_id);
}

add_mesh :: (scene: *Scene, xform: Matrix4, mesh: Primitive_Mesh, material_id: MaterialID)
{
    primitive := add_primitive(scene, .MESH);

    primitive.shape.mesh = mesh;

    _, inv := inverse(xform);

    primitive.xform.forward = make_matrix4x3(xform);
    primitive.xform.inverse = make_matrix4x3(inv);
    primitive.material_id = material_id;
}

create_material :: (scene: *Scene) -> MaterialID, *Material
{
    id       := scene.materials.count.(MaterialID);
    material := array_add(*scene.materials);

    material.color = create_constant_texture(Vector3.{0.8, 0.8, 0.8});
    material.diffuse_roughness = create_constant_texture(0.0);
    material.specular_ior = create_constant_texture(1.5);
    material.specular_weight = create_constant_texture(1.0);
    material.transmission_weight = create_constant_texture(0.0);

    material.specular_roughness = create_constant_texture(0.0);
    material.specular_anisotropic = create_constant_texture(0.0);

    material.metallic = create_constant_texture(0.0);
    material.reflectance = create_constant_texture(Vector3.{0.8, 0.8, 0.8});
    material.edge_tint = create_constant_texture(Vector3.{1.0, 1.0, 1.0});
    material.falloff = create_constant_texture(Vector3.{0, 0, 0});

    material.geometry_opacity = create_constant_texture(1.0);

    material.absorption_strength = create_constant_texture(0.0);
    material.absorption = create_constant_texture(.{1.0, 1.0, 1.0});
    material.emission_strength = create_constant_texture(0.0);
    material.emission_color = create_constant_texture(.{1.0, 1.0, 1.0});

    return id, material;
}

create_lambertian_material :: (scene: *Scene, color: Texture2D, roughness := 0.0) -> MaterialID, *Material
{
    id, material := create_material(scene);
    material.color             = color;
    material.diffuse_roughness = create_constant_texture(roughness);
    material.specular_ior      = create_constant_texture(1.5);
    material.specular_weight   = create_constant_texture(1.0);
    return id, material;
}

create_plastic_material :: (scene: *Scene, color: Texture2D, specular_weight := 1.0, ior := 1.5, roughness := 0.3) -> MaterialID, *Material
{
    id, material := create_material(scene);
    material.color = color;
    material.specular_weight = create_constant_texture(specular_weight);
    material.specular_ior = create_constant_texture(ior);
    material.specular_roughness = create_constant_texture(roughness);
    return id, material;
}

create_metal_material :: (scene: *Scene, roughness := 0.0, edge_tint := Vector3.{1, 1, 1}, reflectance := Vector3.{0.8, 0.8, 0.8}, falloff := Vector3.{0, 0, 0}) -> MaterialID
{
    id, material := create_material(scene);
    material.metallic = create_constant_texture(1.0);
    material.specular_roughness = create_constant_texture(roughness);
    material.reflectance = create_constant_texture(reflectance);
    material.edge_tint = create_constant_texture(edge_tint);
    material.falloff = create_constant_texture(falloff);
    return id;
}

create_emission_material :: (scene: *Scene, color: Texture2D, strength := 1.0) -> MaterialID
{
    id, material := create_material(scene);
    material.emission_color = color;
    material.emission_strength = create_constant_texture(strength);
    return id;
}

create_constant_texture :: (color: Vector3) -> Texture2D
{
    texture: Texture2D;
    texture.scale     = Vector2.{1, 1};
    texture.constants = .[color, color];
    return texture;
}

create_constant_texture :: (alpha: float) -> Texture2D
{
    return create_constant_texture(Vector3.{alpha, alpha, alpha});
}

create_checkerboard_texture :: (color_0: Vector3, color_1: Vector3, scale := Vector2.{1, 1}) -> Texture2D
{
    texture: Texture2D;
    texture.scale = scale;
    texture.constants = .[color_0, color_1];
    return texture;
}

create_checkerboard_texture :: (alpha_0: float, alpha_1: float, scale := Vector2.{1, 1}) -> Texture2D
{
    return create_checkerboard_texture(Vector3.{alpha_0, alpha_0, alpha_0}, Vector3.{alpha_1, alpha_1, alpha_1}, scale);
}

load_texture_from_file :: (path: string, desired_num_channels := 0) -> Texture2D
{
    w, h, channels: s32;

    if (ends_with(path, ".hdr"))
    {
        data := stbi_loadf(temp_c_string(path), *w, *h, *channels, 0);
        assert(channels == 1 || channels == 3, "Unsupported image format");

        if (!data)
        {
            print("Failed to load texture: %. Reason: %\n", path, stbi_failure_reason());
            return .{};
        }

        texture := create_constant_texture(.{1, 1, 1});
        texture.format = ifx channels == 1 then .R32_FLOAT else .R32G32B32_FLOAT;
        texture.width  = w.(u32);
        texture.height = h.(u32);
        texture.stride = w.(u32) * channels.(u32) * size_of(float);
        texture.data   = data.(*u8);
        return texture;
    }
    else
    {
        data    := stbi_load(temp_c_string(path), *w, *h, *channels, 0);
        assert(channels == 1 || channels == 3, "Unsupported image format");

        if (!data)
        {
            print("Failed to load texture: %. Reason: %\n", path, stbi_failure_reason());
            return .{};
        }

        texture := create_constant_texture(.{1, 1, 1});
        texture.format = ifx channels == 1 then .R8_UNORM else .R8G8B8_UNORM;
        texture.width  = w.(u32);
        texture.height = h.(u32);
        texture.stride = w.(u32) * channels.(u32) * size_of(u8);
        texture.data   = data;
        return texture;
    }
}

init_scene :: (scene: *Scene, width: s32, height: s32, multisamples: u32 = 16, max_depth: s32 = 5, filter := Filter.{})
{
    create_lambertian_material(scene, create_constant_texture(.{0, 0, 0}));
    Simp.bitmap_alloc(*scene.bitmap, width, height, .RGBA8);
    Simp.bitmap_alloc(*scene.bounces_heatmap, width, height, .RGBA8);
    Simp.bitmap_alloc(*scene.bvh_visits_heatmap, width, height, .RGBA8);
    //scene.bitmap.flags |= .IS_SRGB; // @todo: fix this flag!!!

    scene.config.width        = width.(u32);
    scene.config.height       = height.(u32);
    scene.config.multisamples = multisamples;
    scene.config.max_depth    = max_depth;

    CACHE_LINE_SIZE :: 64; // mac?

    scene.rgbx, scene.rgbx_mem = NewArray(scene.config.width * scene.config.height, Vector4, alignment=CACHE_LINE_SIZE);
    scene.statistics, scene.statistics_mem = NewArray(scene.config.width * scene.config.height, Path_Statistics, alignment=CACHE_LINE_SIZE);
}

prepare_for_rendering :: (scene: *Scene)
{
    scene.camera.aspect_ratio = scene.config.width.(float) / scene.config.height.(float);
    UpdateCameraParams(*scene.camera);
    build_bvh(scene);
}

build_bvh :: (scene: *Scene)
{
    if scene.primitives.count
    {
        array_resize(*scene.bboxes, scene.primitives.count, initialize=false);
        array_resize(*scene.tlas.indices, scene.primitives.count, initialize=false);
        array_resize(*scene.tlas.nodes, 2 * scene.primitives.count - 1);

        array_resize(*scene.mapped, scene.primitives.count, initialize=false);

        for scene.primitives
        {
            bbox: Box3 = ---;

            if #complete it.type ==
            {
                case .SPHERE;
                    radius    := it.shape.sphere.radius;
                    center    := transform_point(it.xform.forward, Vector3.{0, 0, 0});
                    bbox.vmin  = center - Vector3.{radius, radius, radius};
                    bbox.vmax  = center + Vector3.{radius, radius, radius};

                case .DISK;
                    radius := it.shape.disk.radius;
                    center := transform_point(it.xform.forward, Vector3.{0, 0, 0});
                    bbox    = bounding_box_from_points(center - Vector3.{radius, radius, 0}, center + Vector3.{radius, radius, 0});
                    bbox    = pad_to_minimus(bbox, 0.0001);

                case .BOX;
                    bbox = transform_box(it.xform.forward, Box3.{it.shape.box.vmin, it.shape.box.vmax});

                case .MESH;
                    bbox = Box3_Empty;
                    for v: it.shape.mesh.vertices
                    {
                        p := transform_point(it.xform.forward, v.p);
                        bbox = box_union(bbox, p);
                    }
            }

            scene.bboxes[it_index] = bbox;
        }

        for *scene.tlas.indices
        {
            it.* = it_index.(u32);
        }

        build_bvh_binned_sah(scene.tlas.nodes, scene.tlas.indices, scene.bboxes);

        for scene.tlas.indices
        {
            scene.mapped[it_index] = scene.primitives[it];
        }
    }
}

half_area :: (b: Box3) -> float
{
    d := b.vmax - b.vmin;
    res := (d.x * d.y + d.x * d.z + d.y * d.z);
    return res;
}

UpdateCameraParams :: (camera: *Camera)
{
    rotation := Matrix4_Identity;
    set_rotation(*rotation, camera.orientation);
    camera.xform = make_translation_matrix4(camera.position) * rotation;
    h           := tan(camera.fov * PI);
    camera.dxdu  = .{h * camera.aspect_ratio, 0, 0};
    camera.dydv  = .{0, h, 0};

    // generate filter
    width := camera.filter.width;
    if camera.filter.type == .BLACKMAN_HARRIS
    {
        width *= 2.0;
    }

    cdf: [FILTER_SIZE + 1]float;
    EvaluateFilterCDF(cdf, 0.0, width * 0.5, camera.filter.type, width);
    InvertCDF(camera.filter_lut, cdf, 0.0, width * 0.5);
}

generate_ray :: (pixel: Vector2, camera: Camera, lens_uv: Vector2) -> Ray
{
    origin := Vector3.{0, 0, 0};
    target := Vector3.{0, 0, 1};

    if #complete camera.type ==
    {
        case .PERSPECTIVE;
            origin = Vector3.{0, 0, 0};
            target = pixel.x * camera.dxdu + pixel.y * camera.dydv + Vector3.{0, 0, 1};

        case .ORTHOGRAPHIC;
            origin = pixel.x * camera.dxdu + pixel.y * camera.dydv;
            origin = origin * max(camera.focus_distance, 1.0);
            target = origin + Vector3.{0, 0, 1};
    }

    if camera.lens_radius > 0.0 && camera.type == .PERSPECTIVE
    {
        origin.xy = camera.lens_radius * sample_uniform_disk_polar(lens_uv);
        dir   := normalize(target - origin);
        ft    := camera.focus_distance / dir.z;
        focus := ft * dir;
        target = origin + focus;
    }

    origin = transform_point(camera.xform, origin);
    target = transform_point(camera.xform, target);

    ray: Ray = ---;

    ray.origin = origin;
    ray.dir    = normalize(target - origin);

    return ray;
}

sample_stratified_square :: (x: float, y: float, inv_size: float) -> Vector2
{
    px := x + random_get_zero_to_one_open();
    py := y + random_get_zero_to_one_open();

    px *= inv_size;
    py *= inv_size;

    return .{px, py};
}

bounding_box_from_points :: (a : Vector3, b: Vector3) -> Box3
{
    minp := min(a, b);
    maxp := max(a, b);
    return Box3.{minp, maxp};
}

pad_to_minimus :: (b: Box3, padding: float) -> Box3
{
    r := b;
    if (r.vmax.x - r.vmin.x < padding)
    {
        r.vmin.x -= padding;
        r.vmax.x += padding;
    }
    if (r.vmax.y - r.vmin.y < padding)
    {
        r.vmin.y -= padding;
        r.vmax.y += padding;
    }
    if (r.vmax.z - r.vmin.z < padding)
    {
        r.vmin.z -= padding;
        r.vmax.z += padding;
    }
    return r;
}

// @todo: Multithread
radix_sort :: (K: []u32, K_temp: []u32, V: []$T, V_temp: []T, n: s64)
{
    prefix: [256]u32;

    for 0..3
    {
        memset(prefix.data, 0, size_of(type_of(prefix)));

        shift := it * 8;
        for 0..n-1
        {
            bin_index := ((K[it] >> shift) & 0xFF);
            assert(bin_index < prefix.count);
            prefix[bin_index] += 1;
        }

        prev_sum : u32 = 0;

        for 0..prefix.count-1
        {
            sum := prefix[it] + prev_sum;
            prefix[it] = prev_sum;
            prev_sum = sum;
        }

        for 0..n-1
        {
            bin_index := ((K[it] >> shift) & 0xFF);
            offset := prefix[bin_index];
            K_temp[offset] = K[it];
            V_temp[offset] = V[it];
            prefix[bin_index] += 1;
        }

        Swap(*K, *K_temp);
        Swap(*V, *V_temp);
    }
}

triangle_bbox :: (p: Vector3, q: Vector3, r: Vector3) -> Box3
{
    bbox := Box3_Empty;
    bbox = box_union(bbox, p);
    bbox = box_union(bbox, q);
    bbox = box_union(bbox, r);
    return bbox;
}

// https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/

split3 :: (x: u32) -> u32
{
    x &= 0x000003ff;
    x = (x ^ (x << 16)) & 0xFF0000FF;
    x = (x ^ (x <<  8)) & 0x0300F00F;
    x = (x ^ (x <<  4)) & 0x030C30C3;
    x = (x ^ (x <<  2)) & 0x09249249;
    return x;
}

encode_morton3 :: (x: u32, y: u32, z: u32) -> u32
{
    x_split := split3(x);
    y_split := split3(y);
    z_split := split3(z);
    code    := (z_split << 2) | (y_split << 1) | x_split;
    return code;
}

SAHBuilder :: struct
{
    nodes     : []BVH_Node;
    next_node : u32;
}

build_bvh_sah_binned_recursive :: (builder: *SAHBuilder, root: u32, lo: s64, hi: s64, indices: []u32, bboxes: []Box3, centriods: []Vector3)
{
    assert(hi >= lo);

    node := *builder.nodes[root];

    if (hi == lo)
    {
        node.bbox                     = bboxes[indices[lo]];
        node.first_child_or_primitive = lo.(u32);
        node.num_primitives           = 1;
        return;
    }

    node_bbox     := Box3_Empty;
    centriod_bbox := Box3_Empty;

    for lo..hi
    {
        node_bbox     = box_union(node_bbox, bboxes[indices[it]]);
        centriod_bbox = box_union(centriod_bbox, centriods[indices[it]]);
    }

    split_axis := 0;
    max_delta  := centriod_bbox.vmax.component[0] - centriod_bbox.vmin.component[0];

    for 1..2
    {
        delta := centriod_bbox.vmax.component[it] - centriod_bbox.vmin.component[it];
        if delta > max_delta
        {
            max_delta = delta;
            split_axis = it;
        }
    }

    EPS :: 1.0e-6;

    if max_delta <= EPS || half_area(node_bbox) <= EPS
    {
        node.bbox                     = node_bbox;
        node.first_child_or_primitive = lo.(u32);
        node.num_primitives           = (hi - lo + 1).(u32);
        return;
    }

    BIN_COUNT   :: 16;
    SPLIT_COUNT :: BIN_COUNT - 1;

    Bin :: struct
    {
        count: s64;
        bbox : Box3;
    }

    bins: [BIN_COUNT]Bin;

    for *bins
    {
        it.count = 0;
        it.bbox = Box3_Empty;
    }

    idelta := 1.0 / max_delta;
    offset := centriod_bbox.vmin.component[split_axis];

    find_bin_index :: (centriod: Vector3) -> int #expand
    {
        bin_index := (BIN_COUNT * (centriod.component[split_axis] - offset) * idelta).(s64);
        if bin_index >= BIN_COUNT then
            bin_index = BIN_COUNT - 1;
        return bin_index;
    }

    for lo..hi
    {
        bin_index := find_bin_index(centriods[indices[it]]);
        bins[bin_index].count += 1;
        bins[bin_index].bbox = box_union(bins[bin_index].bbox, bboxes[indices[it]]);
    }

    split_costs: [SPLIT_COUNT]float;

    prev_count := 0;
    prev_box   := Box3_Empty;

    for 0..SPLIT_COUNT-1
    {
        prev_box = box_union(prev_box, bins[it].bbox);
        prev_count += bins[it].count;
        split_costs[it] += prev_count * half_area(prev_box);
    }

    prev_count = 0;
    prev_box   = Box3_Empty;

    for < 1..SPLIT_COUNT
    {
        prev_box = box_union(prev_box, bins[it].bbox);
        prev_count += bins[it].count;
        split_costs[it - 1] += prev_count * half_area(prev_box);
    }

    min_split_cost := split_costs[0];
    min_split_cost_index := 0;

    for 1..SPLIT_COUNT-1
    {
        if (split_costs[it] < min_split_cost)
        {
            min_split_cost = split_costs[it];
            min_split_cost_index = it;
        }
    }

    split_cost  := 0.5 + min_split_cost / half_area(node_bbox);
    leaves_cost := (hi - lo + 1).(float);

    if (split_cost > leaves_cost)
    {
        node.bbox                     = node_bbox;
        node.first_child_or_primitive = lo.(u32);
        node.num_primitives           = (hi - lo + 1).(u32);
        return;
    }

    // partition
    mid := -1;

    {
        i := lo - 1;
        j := hi + 1;

        while 1
        {
            i += 1;

            while i <= hi
            {
                bin_index := find_bin_index(centriods[indices[i]]);
                if bin_index > min_split_cost_index
                    break;
                i += 1;
            }

            j -= 1;

            while j >= lo
            {
                bin_index := find_bin_index(centriods[indices[j]]);
                if bin_index <= min_split_cost_index
                    break;
                j -= 1;
            }

            if i >= j
            {
                mid = j;
                break;
            }

            swap(*indices[j], *indices[i]);
        }
    }

    assert(mid >= lo && mid < hi);

    next := builder.next_node;
    builder.next_node += 2;

    build_bvh_sah_binned_recursive(builder, next + 0, lo, mid, indices, bboxes, centriods);
    build_bvh_sah_binned_recursive(builder, next + 1, mid + 1, hi, indices, bboxes, centriods);

    node.bbox                     = box_union(builder.nodes[next + 0].bbox, builder.nodes[next + 1].bbox);
    node.first_child_or_primitive = next;
    node.num_primitives           = 0;
}

build_bvh_binned_sah :: (nodes: []BVH_Node, indices: []u32, bboxes: []Box3)
{
    assert(nodes.count == bboxes.count * 2 - 1 && indices.count == bboxes.count);

    auto_release_temp();

    centriods := NewArray(bboxes.count, Vector3, initialized=false,, temp);

    for bboxes
    {
        centriods[it_index] = 0.5 * (it.vmin + it.vmax);
    }

    builder := SAHBuilder.{nodes, 1};
    build_bvh_sah_binned_recursive(*builder, 0, 0, indices.count - 1, indices, bboxes, centriods);
}

build_blas :: (mesh: *Primitive_Mesh)
{
    num_triangles := mesh.indices.count / 3;

    // @todo: cleanup
    bboxes: []Box3;
    defer array_free(bboxes);

    array_resize(*bboxes, num_triangles, initialize=false);
    array_resize(*mesh.blas.indices, num_triangles, initialize=false);
    array_resize(*mesh.blas.nodes, 2 * num_triangles - 1, initialize=false);

    for 0..num_triangles-1
    {
        i0 := mesh.indices[it * 3 + 0];
        i1 := mesh.indices[it * 3 + 1];
        i2 := mesh.indices[it * 3 + 2];

        v0 := mesh.vertices[i0].p;
        v1 := mesh.vertices[i1].p;
        v2 := mesh.vertices[i2].p;

        bboxes[it]  = triangle_bbox(v0, v1, v2);
        mesh.blas.indices[it] = it.(u32);
    }

    // @todo: map indices or may be not worth it??
    build_bvh_binned_sah(mesh.blas.nodes, mesh.blas.indices, bboxes);
}


GetPixel :: (x: int, y: int, stride: int, data: *u8, $type: Type, $n: int) -> Vector3
#modify
{
    if (n != 1 && n != 3)
    {
        return false, "Channel must be either 1 or 3";
    }
    if (type != u8 && type != float)
    {
        return false, "Data must be either u8 or float";
    }
    return true;
}
{
    index := y * stride + x * n * size_of(type);
    ptr   := (data + index).(*type);

    r     := ptr[0];
    #if (n == 1)
    {
        g := r;
        b := r;
    }
    else
    {
        g := ptr[1];
        b := ptr[2];
    }

    #if (type == u8)
    {
        rf := saturate(r.(float) / 255.0);
        gf := saturate(g.(float) / 255.0);
        bf := saturate(b.(float) / 255.0);
    }
    else
    {
        rf := r;
        gf := g;
        bf := b;
    }

    return Vector3.{rf, gf, bf};
}

SampleTexture :: (texture: Texture2D, u: float, v: float) -> Vector3
{
    u *= texture.scale.x;
    v *= texture.scale.y;

    // @todo: antialiasing
    // this can be done after we have differentials with du and dv
    // check pbrt for reference

    t := ((u.(int) + v.(int)) & 1).(float);
    c := lerp(texture.constants[0], texture.constants[1], t);

    if (texture.data)
    {
        xp := u * texture.width.(float) - 0.5;
        yp := v * texture.height.(float) - 0.5;

        // Wrap Repeat
        x0 := xp.(int) % texture.width;
        y0 := yp.(int) % texture.height;
        x1 := (x0 + 1) % texture.width;
        y1 := (y0 + 1) % texture.height;

        xf := fract(xp);
        yf := fract(yp);

        samples : [4]Vector3 = ---;

        if #complete texture.format ==
        {
            case .UNKNOWN;
                samples[0] = Vector3.{1, 1, 1};
                samples[1] = Vector3.{1, 1, 1};
                samples[2] = Vector3.{1, 1, 1};
                samples[3] = Vector3.{1, 1, 1};

            case .R8_UNORM;
                samples[0] = GetPixel(x0, y0, texture.stride, texture.data, u8, 1);
                samples[1] = GetPixel(x1, y0, texture.stride, texture.data, u8, 1);
                samples[2] = GetPixel(x0, y1, texture.stride, texture.data, u8, 1);
                samples[3] = GetPixel(x1, y1, texture.stride, texture.data, u8, 1);

            case .R8G8B8_UNORM;
                samples[0] = GetPixel(x0, y0, texture.stride, texture.data, u8, 3);
                samples[1] = GetPixel(x1, y0, texture.stride, texture.data, u8, 3);
                samples[2] = GetPixel(x0, y1, texture.stride, texture.data, u8, 3);
                samples[3] = GetPixel(x1, y1, texture.stride, texture.data, u8, 3);

            case .R32_FLOAT;
                samples[0] = GetPixel(x0, y0, texture.stride, texture.data, float, 1);
                samples[1] = GetPixel(x1, y0, texture.stride, texture.data, float, 1);
                samples[2] = GetPixel(x0, y1, texture.stride, texture.data, float, 1);
                samples[3] = GetPixel(x1, y1, texture.stride, texture.data, float, 1);

            case .R32G32B32_FLOAT;
                samples[0] = GetPixel(x0, y0, texture.stride, texture.data, float, 3);
                samples[1] = GetPixel(x1, y0, texture.stride, texture.data, float, 3);
                samples[2] = GetPixel(x0, y1, texture.stride, texture.data, float, 3);
                samples[3] = GetPixel(x1, y1, texture.stride, texture.data, float, 3);
        }

        avg_x1 := lerp(samples[0], samples[1], xf);
        avg_x2 := lerp(samples[2], samples[3], xf);
        avg    := lerp(avg_x1, avg_x2, yf);

        // @todo: fix this??
        avg.x = clamp(avg.x, 0.0, 1.0);
        avg.y = clamp(avg.y, 0.0, 1.0);
        avg.z = clamp(avg.z, 0.0, 1.0);

        c *= avg;
    }

    return c;
}

SampleAlpha :: (texture: Texture2D, u: float, v: float) -> float
{
    color := SampleTexture(texture, u, v);
    return color.x;
}

sample_uniform_disk_polar :: (u: Vector2) -> Vector2
{
    r := sqrt(u.x);
    theta := 2 * PI * u.y;
    sample: Vector2 = ---;
    sample.x = r * cos(theta);
    sample.y = r * sin(theta);
    return sample;
}

SampleTextureSpectrum :: (texture: Texture2D, u: float, v: float) -> Spectrum
{
    color := SampleTexture(texture, u, v);
    return Spectrum.{color.x, color.y, color.z};
}

material_surface :: (material: Material, hit: Hit_Info) -> Surface
{
    absorption_strength  := SampleAlpha(material.absorption_strength, hit.u, hit.v);
    absorption           := SampleTextureSpectrum(material.absorption, hit.u, hit.v);
    emission_strength    := SampleAlpha(material.emission_strength, hit.u, hit.v);
    emission_color       := SampleTextureSpectrum(material.emission_color, hit.u, hit.v);

    surface: Surface;

    surface.color                = SampleTextureSpectrum(material.color, hit.u, hit.v);
    surface.diffuse_roughness    = SampleAlpha(material.diffuse_roughness, hit.u, hit.v);
    surface.specular_ior         = SampleAlpha(material.specular_ior, hit.u, hit.v);
    surface.specular_weight      = SampleAlpha(material.specular_weight, hit.u, hit.v);
    surface.transmission_weight  = SampleAlpha(material.transmission_weight, hit.u, hit.v);

    surface.specular_roughness   = SampleAlpha(material.specular_roughness, hit.u, hit.v);
    surface.specular_anisotropic = SampleAlpha(material.specular_anisotropic, hit.u, hit.v);

    surface.metallic             = SampleAlpha(material.metallic, hit.u, hit.v);
    surface.reflectance          = SampleTextureSpectrum(material.reflectance, hit.u, hit.v);
    surface.edge_tint            = SampleTextureSpectrum(material.edge_tint, hit.u, hit.v);
    surface.falloff              = SampleTextureSpectrum(material.falloff, hit.u, hit.v);
    
    surface.geometry_opacity     = SampleAlpha(material.geometry_opacity, hit.u, hit.v);
    surface.absorption           = absorption_strength * absorption;
    surface.emission             = emission_strength * emission_color;

    // TODO: Do this in prepare_surface
    if (hit.face == .BACK)
    {
        surface.specular_ior = 1.0 / surface.specular_ior;
    }

    return surface;
}

EncodeSphericalUV :: (n: Vector3) -> Vector2
{
    phi := atan2(n.z, n.x);
    if (phi < 0)
    {
        phi += 2 * PI;
    }
    cos_theta := clamp(n.y, -1.0, 1.0);
    sin_theta := sqrt(1 - cos_theta * cos_theta);
    theta     := acos(cos_theta);
    u         := phi / (2 * PI);
    v         := theta / PI;
    return .{u, v};
}

Ray_Type :: enum
{
    PRIMARY;
    SECONDARY;
}

forward_transform :: (xform: Matrix3, p: Vector3) -> Vector3
{
    r: Vector3 = ---;
    r.x = xform._11 * p.x + xform._12 * p.y + xform._13 * p.z;
    r.y = xform._21 * p.x + xform._22 * p.y + xform._23 * p.z;
    r.z = xform._31 * p.x + xform._32 * p.y + xform._33 * p.z;
    return r;
}

inverse_transform :: (xform: Matrix3, p: Vector3) -> Vector3
{
    r: Vector3 = ---;
    r.x = xform._11 * p.x + xform._21 * p.y + xform._31 * p.z;
    r.y = xform._12 * p.x + xform._22 * p.y + xform._32 * p.z;
    r.z = xform._13 * p.x + xform._23 * p.y + xform._33 * p.z;
    return r;
}

is_valid_spectrum :: inline (s: Spectrum) -> bool
{
    nan_x, inf_x := is_nan_is_inf(s.x);
    nan_y, inf_y := is_nan_is_inf(s.y);
    nan_z, inf_z := is_nan_is_inf(s.z);
    return !nan_x && !inf_x && !nan_y && !inf_y && !nan_z && !inf_z;
}

trace_path :: (scene: Scene, primary: Ray, depth: s32, rng: *Path_State, stats: *Path_Statistics) -> Vector3
{
    radiance   := Spectrum.{0, 0, 0};
    throughput := Spectrum.{1, 1, 1};

    origin     := primary.origin;
    dir        := primary.dir;
    type       := Ray_Type.PRIMARY;
    tmin       := 0.0;
    tmax       := FLOAT32_INFINITY;

    for 0..depth-1
    {
        hit         := Hit_Info.{ t = -1 };
        num_visited : u32 = 0;

        if (!scene.config.flat_background || type == .PRIMARY)
        {
            hit, num_visited = intersect_scene(scene, origin, dir, tmin, tmax);
        }

        stats.n_bvh_visits += num_visited;

        if hit.t >= 0.0
        {
            //------------------------------------------------------------------------
            // TBN
            N := hit.n;
            T := normalize(hit.dpdu - hit.n * dot(hit.dpdu, hit.n));
            B := cross(N, T);
            handedness := ifx (dot(B, hit.dpdv) < 0.0) then -1.0 else 1.0;
            B *= handedness;

            inv_TBN : Matrix3 = ---;
            inv_TBN.v[0] = T;
            inv_TBN.v[1] = B;
            inv_TBN.v[2] = N;

            //------------------------------------------------------------------------
            // Sample
            material := scene.materials[hit.material_id];
            surface  := material_surface(material, hit);

            next_bounce(rng);
            stats.n_bounces += 1;

            p      := sample_1D(rng, .LOBE);
            u      := sample_2D(rng, .BxDF);

            V      := forward_transform(inv_TBN, -dir);

            shading_context := prepare_surface(surface, V);

            sample := sample_surface(shading_context, .{u.x, u.y, p});

  //          max_acceptable_radiance := 100.0;
  //          if max_spectrum(sample.weight) > max_acceptable_radiance || !is_valid_spectrum(sample.weight)
  //          {
  //              new_context := context;
  //              push_context new_context
  //              {
  //                  context.print_style.default_format_struct.use_long_form_if_more_than_this_many_members = -1;
  //                  context.print_style.default_format_struct.use_newlines_if_long_form = true;
  //                  print("sample exceeds % [ sample = % ]\n", max_acceptable_radiance, sample);
  //                  print("    shading_context : %\n", shading_context);
  //              }
  //          }

            if (hit.face == .BACK)
            {
                throughput *= exp(-hit.t * surface.absorption);
            }

            // todo: clamping before adding??
            contrib := throughput * surface.emission;
            radiance += contrib;

            if !sample.lobe_type
            {
                break;
            }

            //          if (isnan(sample.bxdf.f.x) || isnan(sample.bxdf.f.y) || isnan(sample.bxdf.f.z))
            //          {
            //              print("nan/inf: %\n", sample.bxdf);
            //          }

            // TODO: Store them separately
            throughput *= sample.weight;
            //cosine := abs(sample.wi.z);
            //throughput *= cosine * sample.f / sample.pdf;

            // TODO: add checks properly
            //if (isnan(throughput.x) || isnan(throughput.y) || isnan(throughput.z))
            //{
            //    print("nan/inf: %\n", throughput.x);
            //}

            //------------------------------------------------------------------------
            // Next ray
            origin = hit.p;
            dir    = inverse_transform(inv_TBN, sample.wi);
            tmin   = 1.0e-3;
            tmax   = FLOAT32_MAX;
            type   = .SECONDARY;
        }
        else
        {
            if (!scene.config.flat_background || type == .SECONDARY)
            {
                uv  := EncodeSphericalUV(dir);
                env := SampleTexture(scene.environment, uv.x, uv.y);

                // @todo: is this where exposure goes??
                env *= scene.exposure;

                //              // @todo: fix this??
                //              env.x = clamp(env.x, 0.0, 1.0);
                //              env.y = clamp(env.y, 0.0, 1.0);
                //              env.z = clamp(env.z, 0.0, 1.0);

                radiance += throughput * env;
            }
            else
            {
                radiance = scene.flat_background_color;
            }
            break;
        }
    }

    return radiance;
}


BlackmanHarris :: (k: float, N: float) -> float
{
    A0 :: 0.35875;
    A1 :: 0.48829;
    A2 :: 0.14128;
    A3 :: 0.01168;

    x := k / N;
    y := 2 * PI * x;
    w := A0 - A1 * cos(y) + A2 * cos(2 * y) - A3 * cos(3 * y);
    return w;
}

EvaluateFilter :: (type: Filter_Type, k: float, N: float) -> float
{
    if #complete type ==
    {
        case .BOX;
            return 1.0;

        case .BLACKMAN_HARRIS;
            return BlackmanHarris(k, N);
    }
}

EvaluateFilterCDF :: (CDF: []float, a: float, b: float, type: Filter_Type, N: float)
{
    n_samples := CDF.count - 1;
    scale     := 1.0 / n_samples.(float);
    x_range   := b - a;
    dx        := x_range * scale;

    CDF[0] = 0.0;
    for 0..n_samples-1
    {
        x := a + (it + 0.5) * dx;
        y := EvaluateFilter(type, x, N);
        CDF[it + 1] = abs(y) * dx + CDF[it];
    }

    // Normalize
    inv_sum := 0.0;
    if (CDF[n_samples] > 0.0)
    {
        inv_sum = 1.0 / CDF[n_samples];
    }
    for * CDF
    {
        it.* *= inv_sum;
    }
    CDF[n_samples] = 1.0;
}

UpperBound :: (arr: []$T, target: T) -> int
{
    lo := 0;
    hi := arr.count - 1;
    ub := arr.count;
    while (lo <= hi)
    {
        mid := lo + (hi - lo) / 2;

        if (arr[mid] > target)
        {
            ub = mid;
            hi = mid - 1;
        }
        else
        {
            lo = mid + 1;
        }
    }
    return ub;
}

InvertCDF :: (inv_CDF: []float, CDF: []float, a: float, b: float)
{
    assert(inv_CDF.count + 1 == CDF.count);
    assert(CDF.count >= 2 && CDF[0] == 0.0 && CDF[CDF.count - 1] == 1.0);

    x_range   := b - a;
    n_samples := inv_CDF.count;
    scale     := 1.0 / n_samples.(float);

    for 0..n_samples-1
    {
        p     := (it + 0.5) * scale;
        bin   := UpperBound(CDF, p) - 1;
        t     := 0.0;

        if (bin < CDF.count - 1)
        {
            denom := max(CDF[bin + 1] - CDF[bin], 1.0e-6);
            t = (p - CDF[bin]) / denom;
        }

        inv_CDF[it] = a + x_range * (bin + t) * scale;
    }
}

SampleCameraFilter :: inline (camera: Camera, u: Vector2) -> Vector2
{
    x := read_lookup_table_1D(camera.filter_lut, FILTER_SIZE, u.x);
    y := read_lookup_table_1D(camera.filter_lut, FILTER_SIZE, u.y);
    return .{x, y};
}

// @todo: remove this
HashTemp :: (x: u32, seed: u32) -> u32
{
    // Mix seed with x via rotate left
    x ^= (seed << 23) | (seed >> 9);

    // Finalizer from murmurhash3
    x ^= x >> 16;
    x *= 0x85ebca6b;
    x ^= x >> 13;
    x *= 0xc2b2ae35;
    x ^= x >> 16;
    return x;
}

IsPower2 :: (v: u32) -> bool
{
    return v && !(v & (v - 1));
}

NextPowerOf2 :: (n: u32) -> u32
{
    if (IsPower2(n))
        return n;
    count : u32 = 0;
    while (n != 0)
    {
        n >>= 1;
        count += 1;
    }
    return (1 << count).(u32);
}

RenderPixel :: (scene: Scene, x: u32, y: u32, frame: u32, stats: *Path_Statistics) -> Vector3
{
    origin     := Vector2.{x.(float), y.(float)};
    width      := scene.config.width;
    height     := scene.config.height;

    scale      := Vector2.{ 2.0 / (width - 1).(float), 2.0 / (height - 1).(float) };
    shift      := Vector2.{ -1.0, -1.0 };

    radiance   := Vector3.{0, 0, 0};

    spp        := NextPowerOf2(scene.config.multisamples);

    seed       := HashTemp(frame, 7);

    for 0..spp-1
    {
        rng        := path_state(x, y, it.(u32), spp, seed);

        filter_uv  := sample_2D(rng, .FILTER);
        subpixel   := SampleCameraFilter(scene.camera, filter_uv);
        sample     := origin + subpixel;

        // To NDC
        pixel      := sample * scale + shift;

        lens_uv    := sample_2D(rng, .LENS);
        ray        := generate_ray(pixel, scene.camera, lens_uv);
        radiance   += trace_path(scene, ray, scene.config.max_depth, *rng, stats);
    }

    radiance /= spp.(float);
    return radiance;
}

RAY_TRACE_TILE_SIZE : s32 : 16;

Render_Shared :: struct
{
    tile_id: int;
}

ApplyToneMapping :: (func: Tone_Map_Type, v: Vector3) -> Vector3
{
    if #complete func ==
    {
        case .LINEAR;
            return Vector3.{saturate(v.x), saturate(v.y), saturate(v.z)};
        case .REINHARD;
            return v / (Vector3.{1, 1, 1} + v);
    }
}

SpiralCoordinates :: (n: int) -> (x: int, y: int)
{
    if (n == 0)
    {
        return 0, 0;
    }

    k := ceil((sqrt(n.(float) + 1) - 1) / 2).(int);
    l := 2 * k + 1;
    t := l - 1;
    m := l * l;

    if (n >= m - t)
    {
        x := k - (m - n);
        y := -k;
        return x, y;
    }

    m -= t;
    if (n >= m - t)
    {
        x := -k;
        y := -k + (m - n);
        return x, y;
    }

    m -= t;
    if (n >= m - t)
    {
        x := -k + (m - n);
        y := k;
        return x, y;
    }

    x := k;
    y := k - (m - n - t);

    return x, y;
}

// @todo: cleanup this global variable
render_shared: Render_Shared;

render :: (scene: *Scene, weight: float, frame: u32)
{
    width  := scene.config.width;
    height := scene.config.height;

    // @todo: cleanup RAY_TRACE_TILE_SIZE
    //  assert(width % RAY_TRACE_TILE_SIZE == 0);
    //  assert(height % RAY_TRACE_TILE_SIZE == 0);

    num_tile_w := width / RAY_TRACE_TILE_SIZE;
    num_tile_h := height / RAY_TRACE_TILE_SIZE;

    if context.lane.index == 0
    {
        atomic_write(*render_shared.tile_id, 0);
    }

    lane_sync();

    max_tile_d := max(num_tile_w, num_tile_h);
    num_tiles  := max_tile_d * max_tile_d;
    offset_x   := (num_tile_w - 1) / 2;
    offset_y   := (num_tile_h - 1) / 2;

    while !scene.cancel_rendering
    {
        captured_tile_id := atomic_add(*render_shared.tile_id, 1);

        if captured_tile_id >= num_tiles then break;

        tile_x, tile_y := SpiralCoordinates(captured_tile_id);
        tile_x += offset_x;
        tile_y += offset_y;

        if (tile_x < 0 || tile_x >= num_tile_w || tile_y < 0 || tile_y >= num_tile_h)
            continue;

        y0 := tile_y * RAY_TRACE_TILE_SIZE;
        y1 := y0 + RAY_TRACE_TILE_SIZE - 1;

        x0 := tile_x * RAY_TRACE_TILE_SIZE;
        x1 := x0 + RAY_TRACE_TILE_SIZE - 1;

        if x1 >= width  then x1 = width - 1;
        if y1 >= height then y1 = height - 1;

        //offset := captured_tile_id * RAY_TRACE_TILE_SIZE * RAY_TRACE_TILE_SIZE;

        for y:y0..y1
        {
            for x:x0..x1
            {
                stats := *scene.statistics[y * width + x];
                color := RenderPixel(scene, x.(u32), y.(u32), frame, stats);

                //color := trace_pixel(scene, x.(s32), y.(s32), num_samples);

                index := y * width + x;
                //index := offset;
                //offset += 1;

                //color *= inv_samples;
                prev_color := scene.rgbx[index].xyz;

                render := lerp(prev_color, color, weight);

                scene.rgbx[index].xyz = render;

                // @todo: proper Tone Mapping + Gamma correction
                // https://64.github.io/tonemapping/
                // @todo: use exposure!!
                render = ApplyToneMapping(scene.tonemap, render);

                Clamp(*render.x, 0.0, 1.0);
                Clamp(*render.y, 0.0, 1.0);
                Clamp(*render.z, 0.0, 1.0);

                write_color(scene.bitmap, x, y, render);
            }
        }
    }

    lane_sync();
}

write_color :: (bitmap: Bitmap, x: int, y: int, linear: Vector3, $srgb: bool = true)
{
    index := (bitmap.height - y - 1) * bitmap.stride + x * 4;

    #if srgb
    {
        color := linear_to_srgb(linear);
    }
    else
    {
        color := linear;
    }

    r := (color.x * 255).(u8);
    g := (color.y * 255).(u8);
    b := (color.z * 255).(u8);

    bitmap.data[index + 0] = r;
    bitmap.data[index + 1] = g;
    bitmap.data[index + 2] = b;
    bitmap.data[index + 3] = 0xFF;
}

load_obj_model :: (path: string) -> Primitive_Mesh
{
    auto_release_temp();

    content := read_entire_file(path,,temp);

    vertices  : [..]Vector3;
    normals   : [..]Vector3;
    texcoords : [..]Vector2;

    vertex_indices   : [..]u32;
    normal_indices   : [..]u32;
    texcoord_indices : [..]u32;

    // @todo @cleanup
    // Use Xar or temporary memory/arena
    defer
    {
        array_free(vertices);
        array_free(normals);
        array_free(texcoords);
        array_free(vertex_indices);
        array_free(normal_indices);
        array_free(texcoord_indices);
    }

    while content
    {
        found:, line:, content = split_from_left(content, #char "\n");
        if !found break;

        if starts_with(line, "v ")
        {
            v: Vector3;
            scan2(line, "v % % %", *v.x, *v.y, *v.z);
            array_add(*vertices, v);
        }
        else if starts_with(line, "vt ")
        {
            uv: Vector2;
            scan2(line, "vt % %", *uv.x, *uv.y);
            array_add(*texcoords, uv);
        }
        else if starts_with(line, "vn ")
        {
            n: Vector3;
            scan2(line, "vn % % %", *n.x, *n.y, *n.z);
            array_add(*normals, n);
        }
        else if starts_with(line, "f ")
        {
            parse_face :: (line: string) #expand
            {
                number, success, face := string_to_int(line, T=s32);
                index := ifx number > 0 then (number - 1).(u32) else (vertices.count + number).(u32);
                array_add(*vertex_indices, index);

                if !face return;
                face = slice(face, 1, face.count - 1);

                number, success, face = string_to_int(face, T=s32);
                if success
                {
                    index = ifx number > 0 then (number - 1).(u32) else (texcoords.count + number).(u32);
                    array_add(*texcoord_indices, index);
                }

                if !face return;
                face = slice(face, 1, face.count - 1);

                number, success, face = string_to_int(face, T=s32);
                if success
                {
                    index = ifx number > 0 then (number - 1).(u32) else (normals.count + number).(u32);
                    array_add(*normal_indices, index);
                }
            }

            face1, face2, face3 : string;
            found, line, face3 = split_from_right(line, #char " ");
            found, line, face2 = split_from_right(line, #char " ");
            found, line, face1 = split_from_right(line, #char " ");

            parse_face(face1);
            parse_face(face2);
            parse_face(face3);
        }
    }

    AttrIndex :: struct
    {
        vertex_index   : u32;
        normal_index   : u32;
        texcoord_index : u32;
    }

    hash_attr_index :: (a: AttrIndex) -> u32
    {
        return sdbm_hash((*a).(*void), size_of(AttrIndex));
    }

    compare_attr_index :: (a: AttrIndex, b: AttrIndex) -> bool
    {
        return a.vertex_index == b.vertex_index && a.normal_index == b.normal_index && a.texcoord_index == b.texcoord_index;
    }

    map   : Table(AttrIndex, u32, given_hash_function=hash_attr_index, given_compare_function=compare_attr_index, REFILL_REMOVED=false);
    attrs := NewArray(vertex_indices.count, Vertex3 ,,temp);

    defer deinit(*map); // @todo: Use temporary memory

    indices := NewArray(vertex_indices.count, u32);

    num_attrs := 0;

    for 0..vertex_indices.count-1
    {
        index: AttrIndex;
        index.vertex_index   = vertex_indices[it];
        index.texcoord_index = ifx texcoord_indices texcoord_indices[it] else 0;
        index.normal_index   = ifx normal_indices normal_indices[it] else 0;

        entry, added := find_or_add(*map, index);

        if added
        {
            entry.* = num_attrs.(u32);
            attrs[num_attrs].p  = vertices[index.vertex_index];
            if texcoords
                attrs[num_attrs].uv = texcoords[index.texcoord_index];
            if normals
                attrs[num_attrs].n  = normals[index.normal_index];
            attrs[num_attrs].t = Vector3.{0, 0, 0};
            attrs[num_attrs].b = Vector3.{0, 0, 0};
            num_attrs += 1;
        }

        indices[it] = entry.*;
    }

    mesh: Primitive_Mesh;

    mesh.vertices = array_copy(array_view(attrs, 0, num_attrs));
    mesh.indices  = indices;

    num_triangles := indices.count / 3;

    if !normals
    {
        for 0..num_triangles-1
        {
            v0 := *mesh.vertices[indices[it * 3 + 0]];
            v1 := *mesh.vertices[indices[it * 3 + 1]];
            v2 := *mesh.vertices[indices[it * 3 + 2]];

            e1 := v1.p - v0.p;
            e2 := v2.p - v0.p;

            n  := cross_product(e1, e2);
            n   = normalize(n);

            v0.n = n;
            v1.n = n;
            v2.n = n;
        }
    }

    num_triangles_included := NewArray(num_attrs, u32,,temp);

    for 0..num_triangles-1
    {
        i0 := indices[it * 3 + 0];
        i1 := indices[it * 3 + 1];
        i2 := indices[it * 3 + 2];

        v0 := *mesh.vertices[i0];
        v1 := *mesh.vertices[i1];
        v2 := *mesh.vertices[i2];

        delta_uv1 := v1.uv - v0.uv;
        delta_uv2 := v2.uv - v0.uv;
        det       := delta_uv1.x * delta_uv2.y - delta_uv1.y * delta_uv2.x;
        degen     := abs(det) == 0.0;

        tangent, bitangent : Vector3;

        if (!degen)
        {
            inv_det  := 1.0 / det;
            delta_p1 := v1.p - v0.p;
            delta_p2 := v2.p - v0.p;
            tangent = (delta_p1 * delta_uv2.y - delta_p2 * delta_uv1.y) * inv_det;
            bitangent = (delta_p2 * delta_uv1.x - delta_p1 * delta_uv2.x) * inv_det;
        }

        if (degen || length_squared(cross(tangent, bitangent)) == 0.0)
        {
            normal := normalize((v0.n + v1.n + v2.n) / 3);
            tangent, bitangent = orthonormal_basis(normal);
        }

        v0.t += tangent;
        v1.t += tangent;
        v2.t += tangent;

        v0.b += bitangent;
        v1.b += bitangent;
        v2.b += bitangent;

        num_triangles_included[i0] += 1;
        num_triangles_included[i1] += 1;
        num_triangles_included[i2] += 1;
    }

    for 0..mesh.vertices.count-1
    {
        v := *mesh.vertices[it];

        v.t /= num_triangles_included[it].(float);
        v.b /= num_triangles_included[it].(float);

        v.t = normalize(v.t - v.n * dot(v.t, v.n));
        handedness := ifx (dot(cross(v.n, v.t), v.b) < 0.0) then -1.0 else 1.0;
        v.b = cross(v.n, v.t) * handedness;
    }

    build_blas(*mesh);

    return mesh;
}

make_matrix4x3 :: (m: Matrix4) -> Matrix4x3
{
    r: Matrix4x3 = ---;
    r._11 = m._11; r._12 = m._12; r._13 = m._13; r._14 = m._14;
    r._21 = m._21; r._22 = m._22; r._23 = m._23; r._24 = m._24;
    r._31 = m._31; r._32 = m._32; r._33 = m._33; r._34 = m._34;
    return r;
}

orthonormal_basis :: (x_axis: Vector3) -> (y_axis: Vector3, z_axis: Vector3)
{
    cross := Vector3.{1, 1, 1};
    if x_axis.x > x_axis.y
    {
        if x_axis.x > x_axis.z
        {
            cross.x = 0;
        }
        else
        {
            cross.z = 0;
        }
    }
    else
    {
        if x_axis.y > x_axis.z
        {
            cross.y = 0;
        }
        else
        {
            cross.z = 0;
        }
    }

    y_axis := cross_product(cross, x_axis);
    normalize(*y_axis, fallback=.{z=1});

    z_axis := cross_product(x_axis, y_axis);
    normalize(*z_axis, fallback=.{z=1});

    return y_axis, z_axis;
}

turns_to_radians :: (turns: float) -> float
{
    return turns * 2.0 * PI;
}
