#load "scene.jai";

RAYTRACE_BITMAP_WIDTH  :: 1920;
RAYTRACE_BITMAP_HEIGHT :: 1080;

//RAYTRACE_BITMAP_WIDTH  :: 800;
//RAYTRACE_BITMAP_HEIGHT :: 600;

want_screenshot := false;

smoothstep :: inline (a: float, b: float, v: float) -> float
{
    dist := b - a;
    if (dist)
    {
        x := clamp((v - a) / dist, 0.0, 1.0);
        return x * x * (3 - 2 * x);
    }
    return 1;
}

quaternion_between_vectors :: (from: Vector3, to: Vector3) -> Quaternion
{
    q: Quaternion;
    w := 1.0 + dot(from, to);
    if (w)
    {
        v  := cross(from, to);
        q.x = v.x;
        q.y = v.y;
        q.z = v.z;
        q.w = w;
    }
    else
    {
        xyz := ifx abs(from.x) > abs(from.z)
                Vector3.{-from.y, from.x, 0.0}
               else
                Vector3.{0.0, -from.z, from.y};
        q = .{xyz.x, xyz.y, xyz.z, w};
    }
    return normalize(q);
}

lookat :: (from: Vector3, to: Vector3, world_forward: Vector3) -> Quaternion
{
    dir := to - from;
    return quaternion_between_vectors(world_forward, dir);
}

hsv_to_rgb :: (cx: float, cy: float, cz: float) -> (r: float, g: float, b: float) {
    p: Vector3;
    p.x = abs(fract(cx + 1)     * 6 - 3) - 1;
    p.y = abs(fract(cx + 2/3.0) * 6 - 3) - 1;
    p.z = abs(fract(cx + 1/3.0) * 6 - 3) - 1;

    Clamp(*p.x, 0, 1);
    Clamp(*p.y, 0, 1);
    Clamp(*p.z, 0, 1);

    p.x = lerp(1, p.x, cy);
    p.y = lerp(1, p.y, cy);
    p.z = lerp(1, p.z, cy);

    return cz * p.x, cz * p.y, cz * p.z;
}

sign_of :: (v: float) -> float
{
    return ((0 < v).(float) - (v < 0).(float));
}

CommandLineArgs :: struct
{
    width       := 1920;
    height      := 1080;
    scene       := Test_Scene.metal_test;
    save_first  := false;
    num_threads := 0;
}

Display_Type :: enum
{
    RENDER;
    BOUNCE_HEATMAP;
    BVH_VISIT_HEATMAP;
}


white_furnace_test_enabled   := false;
white_furnace_test_error     := 0.0;
white_furnace_test_bias      := 0.0;
white_furnace_test_max_error := 0.0;

wavefront_raytrace_entry :: (thread: *Thread) -> s64
{
    scene := thread.data.(*Scene);

    width  := scene.config.width;
    height := scene.config.height;

    screenshot_index := 0;

    if context.lane.index == 0
    {
        screenshot_index = get_first_screenshot_index("captures");
    }

    while (!should_quit)
    {
        weight := 1.0 / (frame_index.(float) + 1);

        t0 := current_time_monotonic();
        render(scene, weight, frame_index.(u32));
        t1 := current_time_monotonic();

        if context.lane.index == 0
        {
            last_frame_render_time_ms = to_milliseconds(t1 - t0);
            frame_index += 1;

            if want_screenshot || (frame_index % 12) == 0
            {
                save_screenshot(scene.bitmap, *screenshot_index);
                want_screenshot = false;
            }

            if white_furnace_test_enabled
            {
                error     := 0.0;
                max_error := 0.0;
                bias      := 0.0;
                for scene.rgbx
                {
                    e := it.x * it.x + it.y * it.y + it.z * it.z;
                    error += abs(e - 3);
                    bias  += (e - 3);
                    max_error = max(max_error, abs(e - 3));
                }
                white_furnace_test_error     = error / (scene.rgbx.count);
                white_furnace_test_bias      = bias / (scene.rgbx.count);
                white_furnace_test_max_error = max_error;
                print("White Furnace Test dE = %\%, bias = %\%, max error = %\n", white_furnace_test_error * 100, white_furnace_test_bias * 100, white_furnace_test_max_error);
            }

            // heatmap

            max_bounces := 1; // prevent division by zero
            max_bvh_visits := 1;

            for scene.statistics
            {
                max_bounces = max(max_bounces, it.n_bounces);
                max_bvh_visits = max(max_bvh_visits, it.n_bvh_visits);
            }

            for y:0..height-1
            {
                for x:0..width-1
                {
                    stats := *scene.statistics[y * width + x];
                    WriteHeatMap(scene.bounces_heatmap, x, y, stats.n_bounces.(float) / max_bounces.(float));
                    WriteHeatMap(scene.bvh_visits_heatmap, x, y, stats.n_bvh_visits.(float) / max_bvh_visits.(float));
                }
            }
        }

        lane_sync();
    }

    return 0;
}

WriteHeatMap :: (bitmap: Bitmap, x: int, y: int, alpha: float)
{
    // Visible Spectrum: https://learn.microsoft.com/en-us/bingmaps/v8-web-control/map-control-concepts/heat-map-module-examples/heat-map-color-gradients

    HEAT_COLORS :: Vector3.[.{1, 0, 1}, .{0, 0, 1}, .{0, 1, 0}, .{1, 1, 0}, .{1, 0, 0}];

    segment_count := HEAT_COLORS.count - 1;
    scaled_alpha  := clamp(alpha, 0.0, 1.0) * segment_count;
    index         := scaled_alpha.(int);
    local_t       := scaled_alpha - index;

    // @todo: fix indexing
    //  color := lerp(HEAT_COLORS[index], HEAT_COLORS[index + 1], local_t);

    //  write_color(bitmap, x, y, color, false);
}

main :: ()
{
    init();

    success, args := parse_arguments(CommandLineArgs);

    print("args = %\n", args);

    if (args.save_first)
    {
        want_screenshot = true;
    }

    MSAA :: 8;

    render_width  = args.width;
    render_height = args.height;

    wnd := create_window(render_width, render_height, "PixL", wanted_msaa = MSAA);

    init_fonts();

    scene: Scene;
    //init_scene(*scene, RAYTRACE_BITMAP_WIDTH, RAYTRACE_BITMAP_HEIGHT, multisamples=256, max_depth=15);
    init_scene(*scene, RAYTRACE_BITMAP_WIDTH, RAYTRACE_BITMAP_HEIGHT, multisamples=64, max_depth=5);
    load_test_scene(*scene, args.scene);

    prepare_for_rendering(*scene);

    wave: Thread_Wave;
    thread_wave_start(*wave, wavefront_raytrace_entry, shared = *scene, num_threads = xx args.num_threads, used_threads = 4);

    Simp.prepare_window(wnd, wanted_msaa = MSAA);

    Simp.set_render_target(wnd, .RIGHT_HANDED);

    raytrace_map : Simp.Texture;

    while !should_quit
    {
        memory_visualizer_per_frame_update();

        update_window_events();

        for get_window_resizes()
        {
            Simp.update_window(it.window);

            if it.window == wnd
            {
                should_reinit := (it.width != render_width) || (it.height != render_height);

                render_width  = it.width;
                render_height = it.height;

                if should_reinit then
                    init_fonts();
            }
        }

        for events_this_frame
        {
            if it.type == .QUIT
            {
                should_quit = true;
                scene.cancel_rendering = true;
            }

            if it.type ==
            {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE
                {
                    should_quit = true;
                }

                if it.key_pressed && it.key_code == #char "Z"
                {
                    info := type_info(Display_Type);
                    display_type = ((display_type + 1).(u32) % info.values.count).(Display_Type);
                }

                if it.key_pressed && it.key_code == #char "H"
                {
                    show_debug_bvh = !show_debug_bvh;
                }

                if it.key_pressed && it.key_code == .TAB
                {
                    show_random_test = !show_random_test;
                }


                if it.key_pressed && it.key_code == .ARROW_RIGHT
                {
                    num_samples_to_display = (num_samples_to_display + 1) % NUM_RANDOM_SAMPLES;
                }

                if it.key_pressed && it.key_code == .ARROW_LEFT
                {
                    num_samples_to_display = (num_samples_to_display - 1 + NUM_RANDOM_SAMPLES) % NUM_RANDOM_SAMPLES;
                }

                if it.key_pressed && it.key_code == #char " "
                {
                    want_screenshot = true;
                }

                if it.key_pressed && it.key_code == #char "."
                {
                    debug_bvh_depth += 1;
                    if debug_bvh_depth > 255 debug_bvh_depth = 255;
                    print("debug_bvh_depth : %\n", debug_bvh_depth);
                }

                if it.key_pressed && it.key_code == #char ","
                {
                    debug_bvh_depth -= 1;
                    if debug_bvh_depth < 0 debug_bvh_depth = 0;
                    print("debug_bvh_depth : %\n", debug_bvh_depth);
                }
            }
        }

        display_bitmap := *scene.bitmap;

        if (!white_furnace_test_enabled)
        {
            if display_type ==
            {
                case .BOUNCE_HEATMAP;
                    display_bitmap = *scene.bounces_heatmap;
                case .BVH_VISIT_HEATMAP;
                    display_bitmap = *scene.bvh_visits_heatmap;
            }
        }

        Simp.texture_load_from_bitmap(*raytrace_map, display_bitmap);
        draw_one_frame(wnd, *raytrace_map, scene, wave.threads.count);

        sleep_milliseconds(10);

        reset_temporary_storage();
    }

    thread_wave_join(*wave);
}

save_screenshot :: (bitmap: Bitmap, screenshot_index: *int)
{
    filepath := tprint("captures/screenshot_%.png", screenshot_index.*);
    print("Saving screenshot: %\n", filepath);
    if (Simp.bitmap_save(*bitmap, filepath))
        screenshot_index.* += 1;
}

draw_rect :: (center: Vector2, w: Vector2, h: Vector2, color: Vector4)
{
    p0 := center - w - h;
    p1 := center + w - h;
    p2 := center + w + h;
    p3 := center - w + h;
    Simp.immediate_quad(p0, p1, p2, p3, color, color, color, color);
}

emboss_line :: (p0: Vector2, p1: Vector2, stroke: float) -> [4]Vector2
{
    corners: [4]Vector2 = ---;
    dx := p1.x - p0.x;
    dy := p1.y - p0.y;
    normal := normalize(Vector2.{-dy, dx});
    corners[0] = p0 - stroke * normal;
    corners[1] = p0 + stroke * normal;
    corners[2] = p1 + stroke * normal;
    corners[3] = p1 - stroke * normal;
    return corners;
}

draw_line :: (a: Vector3, b: Vector3, color: Vector4, projection: Matrix4)
{
    p0 := projection * Vector4.{ a.x, a.y, a.z, 1 };
    p1 := projection * Vector4.{ b.x, b.y, b.z, 1 };

    p0 /= p0.w;
    p1 /= p1.w;

    p0.x *= MAP_RATIO;
    p0.y *= MAP_RATIO;

    p1.x *= MAP_RATIO;
    p1.y *= MAP_RATIO;

    p0 *= 0.5;
    p1 *= 0.5;

    p0 += Vector4.{ 0.5, 0.5, 0.5, 0.5 };
    p1 += Vector4.{ 0.5, 0.5, 0.5, 0.5 };

    p0.x *= (render_width - 1);
    p0.y *= (render_height - 1);
    p1.x *= (render_width - 1);
    p1.y *= (render_height - 1);

    corners := emboss_line(p0.xy, p1.xy, 1);

    Simp.immediate_quad(corners[0], corners[1], corners[2], corners[3], color, color, color, color);
}

draw_triangle :: (v0: Vertex3, v1: Vertex3, v2: Vertex3, color: Vector4, pv: Matrix4, inv_transpose: Matrix4)
{
    light_dir := Vector3.{0, -1, 1};

    light_dir = normalize(light_dir);

    strength1 := max(dot(v0.n, -light_dir), 0.0);
    strength2 := max(dot(v1.n, -light_dir), 0.0);
    strength3 := max(dot(v2.n, -light_dir), 0.0);

    color1 := strength1 * color;
    color2 := strength2 * color;
    color3 := strength3 * color;

    p0 := pv * Vector4.{ v0.p.x, v0.p.y, v0.p.z, 1 };
    p1 := pv * Vector4.{ v1.p.x, v1.p.y, v1.p.z, 1 };
    p2 := pv * Vector4.{ v2.p.x, v2.p.y, v2.p.z, 1 };

    p0 /= p0.w;
    p1 /= p1.w;
    p2 /= p2.w;

    p0.x *= MAP_RATIO;
    p0.y *= MAP_RATIO;

    p1.x *= MAP_RATIO;
    p1.y *= MAP_RATIO;

    p2.x *= MAP_RATIO;
    p2.y *= MAP_RATIO;

    p0 *= 0.5;
    p1 *= 0.5;
    p2 *= 0.5;

    p0 += Vector4.{ 0.5, 0.5, 0.5, 0.0 };
    p1 += Vector4.{ 0.5, 0.5, 0.5, 0.0 };
    p2 += Vector4.{ 0.5, 0.5, 0.5, 0.0 };

    face := cross(p1.xyz - p0.xyz, p2.xyz - p0.xyz);

    if face.z >= 0 then
        return;

    p0.x *= (render_width - 1);
    p0.y *= (render_height - 1);
    p1.x *= (render_width - 1);
    p1.y *= (render_height - 1);
    p2.x *= (render_width - 1);
    p2.y *= (render_height - 1);

    Simp.immediate_triangle(p0.xyz, p1.xyz, p2.xyz, color1, color2, color3);

    //draw_line(v0.p, v1.p, color, projection);
    //draw_line(v1.p, v2.p, color, projection);
    //draw_line(v2.p, v0.p, color, projection);
}

draw_mesh :: (mesh: Primitive_Mesh, color: Vector4, pv: Matrix4, inv_transpose: Matrix4)
{
    num_triangles := mesh.indices.count / 3;

    for 0..num_triangles-1
    {
        i0 := mesh.indices[it * 3 + 0];
        i1 := mesh.indices[it * 3 + 1];
        i2 := mesh.indices[it * 3 + 2];
        draw_triangle(mesh.vertices[i0], mesh.vertices[i1], mesh.vertices[i2], color, pv, inv_transpose);
    }
}

draw_box :: (box: Box3, color: Vector4, projection: Matrix4)
{
    diag := box.vmax - box.vmin;

    dx := Vector3.{diag.x, 0, 0};
    dy := Vector3.{0, diag.y, 0};
    dz := Vector3.{0, 0, diag.z};

    draw_line(box.vmin, box.vmin + dx, color, projection);
    draw_line(box.vmin, box.vmin + dy, color, projection);
    draw_line(box.vmin, box.vmin + dz, color, projection);
    draw_line(box.vmin + dz, box.vmin + dz + dx, color, projection);
    draw_line(box.vmin + dz, box.vmin + dz + dy, color, projection);
    draw_line(box.vmin + dx, box.vmin + dx + dz, color, projection);
    draw_line(box.vmin + dx, box.vmin + dx + dy, color, projection);
    draw_line(box.vmin + dy, box.vmin + dy + dx, color, projection);
    draw_line(box.vmin + dy, box.vmin + dy + dz, color, projection);
    draw_line(box.vmin + dx + dz, box.vmin + dx + dz + dy, color, projection);
    draw_line(box.vmin + dx + dy, box.vmin + dx + dy + dz, color, projection);
    draw_line(box.vmin + dy + dz, box.vmin + dy + dz + dx, color, projection);
}

draw_bvh :: (root: int, nodes: []BVH_Node, boxes: []Box3, indices: []u32, projection: Matrix4, depth: int)
{
    using node := nodes[root];

    if num_primitives
    {
        if depth == debug_bvh_depth || debug_bvh_depth == -1
        {
            for 0..num_primitives-1
            {
                index := indices[it + first_child_or_primitive];
                draw_box(boxes[index], Vector4.{1, 1, 1, 1}, projection);
            }
        }
    }
    else
    {
        if depth == debug_bvh_depth || debug_bvh_depth == -1
            draw_box(bbox, Vector4.{1, 1, 1, 1}, projection);

        draw_bvh(first_child_or_primitive + 0, nodes, boxes, indices, projection, depth + 1);
        draw_bvh(first_child_or_primitive + 1, nodes, boxes, indices, projection, depth + 1);
    }
}

//------------------------------------------------------------------------

SAMPLES_PER_AXIS   :: 128;
NUM_RANDOM_SAMPLES :: SAMPLES_PER_AXIS * SAMPLES_PER_AXIS;

num_samples_to_display := NUM_RANDOM_SAMPLES - 1;

pcg_random_samples:      [NUM_RANDOM_SAMPLES]Vector2;
sobol_random_samples:    [NUM_RANDOM_SAMPLES]Vector2;
sobol_ss_random_samples: [NUM_RANDOM_SAMPLES]Vector2;

initted_random_samples := false;
show_random_test := false;

InitializeRandomSamples :: ()
{
    for * pcg_random_samples
    {
        x := random_get_zero_to_one_open();
        y := random_get_zero_to_one_open();
        it.* = .{x, y};
    }

    seed : u32 = 7777;

    for * sobol_random_samples
    {
        x := sample_sobol(it_index.(u32), 0);
        y := sample_sobol(it_index.(u32), 1);
        it.* = .{x, y};
    }

    for * sobol_ss_random_samples
    {
        x   := it_index % SAMPLES_PER_AXIS;
        y   := it_index / SAMPLES_PER_AXIS;
        rng := path_state(x.(u32), y.(u32), 0, 1, seed);
        p   := sample_2D(rng, .FILTER);
        it.* = p;
    }
}

DrawRect :: (corner: Vector2, width: float, height: float, color: Vector4)
{
    w  := Vector2.{width / 2, 0};
    h  := Vector2.{0, height / 2};
    center := corner + w + h;
    p0 := center - w - h;
    p1 := center + w - h;
    p2 := center + w + h;
    p3 := center - w + h;
    Simp.immediate_quad(p0, p1, p2, p3, color, color, color, color);
}

draw_random_test :: ()
{
    if !initted_random_samples
    {
        InitializeRandomSamples();
        initted_random_samples = true;
    }

    size := 600.0;
    gap  := 50.0;

    x    := 0.5 * (render_width.(float) - size * 3 - 2 * gap);
    y    := 0.5 * (render_height.(float) - size);

    corner := Vector2.{x, y};

    DrawRect(corner, size, size, .{1, 1, 1, 1});

    for 0..num_samples_to_display
    {
        r := pcg_random_samples[it];
        p := corner + r * size;
        DrawRect(p, 2, 2, .{0, 0, 0, 1});
    }

    corner.x += size + gap;
    DrawRect(corner, size, size, .{1, 1, 1, 1});

    for 0..num_samples_to_display
    {
        r := sobol_random_samples[it];
        p := corner + r * size;
        DrawRect(p, 2, 2, .{0, 0, 0, 1});
    }

    corner.x += size + gap;
    DrawRect(corner, size, size, .{1, 1, 1, 1});

    for 0..num_samples_to_display
    {
        r := sobol_ss_random_samples[it];
        p := corner + r * size;
        DrawRect(p, 2, 2, .{0, 0, 0, 1});
    }
}

draw_one_frame :: (wnd: Window_Type, map: *Simp.Texture, scene: Scene, num_threads: int)
{
    time := seconds_since_init();

    Simp.clear_render_target(.15, .08, .08, 1);

    Simp.set_shader_for_images(map);

    {
        aspect_ratio := RAYTRACE_BITMAP_WIDTH.(float) / RAYTRACE_BITMAP_HEIGHT.(float);

        rect_height := render_height.(float) * MAP_RATIO;
        rect_width := aspect_ratio * rect_height;

        center: Vector2;
        center.x = render_width.(float) / 2;
        center.y = render_height.(float) / 2;

        w := Vector2.{rect_width / 2, 0};
        h := Vector2.{0, rect_height / 2};

        p0 := center - w - h;
        p1 := center + w - h;
        p2 := center + w + h;
        p3 := center - w + h;

        white : = Vector4.{ 1, 1, 1, 1 };

        Simp.immediate_quad(p0, p1, p2, p3, white, white, white, white);
    }

    Simp.set_shader_for_color();

    if (show_random_test)
    {
        draw_random_test();
    }

    if show_debug_bvh
    {
        //projection_view := scene.camera.xform.projection * scene.camera.xform.view * debug_mesh_xform;
        //draw_bvh(0, scene.tlas.nodes, scene.tlas.bboxes, scene.tlas.indices, projection_view, 0);
        //draw_bvh(0, debug_mesh.blas.nodes, debug_mesh.blas.bboxes, debug_mesh.blas.indices, projection_view, 0);

        //_, inv := inverse(scene.camera.xform.view * debug_mesh_xform);
        //inv_transpose := transpose(inv);

        //draw_mesh(debug_mesh, .{1, 1, 1, 1}, projection_view, inv_transpose);
    }

    secs  := time.(int);
    mins  := secs / 60;
    secs   = secs % 60;
    hours := mins / 60;
    mins   = mins % 60;

    total_runtime := tprint("%:%:%",
                            formatInt(hours, minimum_digits=2),
                            formatInt(mins, minimum_digits=2),
                            formatInt(secs, minimum_digits=2));

    if (white_furnace_test_enabled)
    {
        text := tprint("Frame: %; Last frame render time: %ms; Threads: %; Runtime: %; White Furnace Test dE = %\%, bias = %\%, max error = %",
                       frame_index, last_frame_render_time_ms, num_threads, total_runtime,
                       white_furnace_test_error * 100, white_furnace_test_bias * 100, white_furnace_test_max_error);
        Simp.draw_text(debug_font, 10, 10, text);
    }
    else
    {
        text := tprint("Frame: %; Last frame render time: %ms; Threads: %; Runtime: %; Bitmap: %",
                       frame_index, last_frame_render_time_ms, num_threads, total_runtime, display_type);
        Simp.draw_text(debug_font, 10, 10, text);
    }

    Simp.swap_buffers(wnd);
}

MAP_RATIO :: 0.9;

debug_bvh_depth := -1;
show_debug_bvh := false;
should_quit := false;
render_width := 0;
render_height := 0;

frame_index := 0;
last_frame_render_time_ms := 0;
display_type := Display_Type.RENDER;

debug_font: *Simp.Dynamic_Font;

init_fonts :: ()
{
    if render_height <= 0 then return;

    pixel_height := render_height / 54;

    debug_font = Simp.get_font_at_size("data/fonts/KodeMono", "KodeMono-Medium.ttf", pixel_height);
    assert(debug_font != null);
}

find_next_screenshot_index :: (info: *File_Visit_Info, user_data: *void)
{
    screenshot_index := user_data.(*int);
    prefix := "screenshot_";

    if (starts_with(info.short_name, prefix))
    {
        postfix := slice(info.short_name, prefix.count, info.short_name.count - prefix.count);

        postfix_number, success, _ := to_integer(postfix);
        if success && postfix_number > screenshot_index.* then
            screenshot_index.* = postfix_number;
    }
}

get_first_screenshot_index :: (path: string) -> int
{
    screenshot_index := 0;
    make_directory_if_it_does_not_exist(path);
    visit_files(path, false, (*screenshot_index).(*void), find_next_screenshot_index);
    return screenshot_index + 1;
}

init :: ()
{
    #if OS == .WINDOWS
    {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }
}

#import "Window_Creation";
#import "Input";

#import "Raddbg"()(ENABLED=ENABLE_RAD_DEBUGGER);
