
build_program :: (outpath: string, name: string, src: string)
{
    w := compiler_create_workspace(name);

    options := get_build_options();
    options.output_executable_name = name;
    options.output_path = outpath;

    set_build_options(options, w);

    compiler_begin_intercept(w);

    // TODO: Include these only for required workspaces
    add_build_string("ENABLE_RAD_DEBUGGER :: true;", w);
    add_build_string("DEBUG :: true;", w);

    add_build_file(src, w);

    message_loop();

    compiler_end_intercept(w);
}

build :: ()
{
    // TODO: This doesn't work? Email?
    //cuda_lib_path := path_join(to_string(getenv("CUDA_PATH")), "lib", "x64");
    //compiler_add_library_search_directory(cuda_lib_path);

    output_path := "bin";
    make_directory_if_it_does_not_exist(output_path);

    build_program(output_path, "PixL", "source/main.jai");
    build_program(output_path, "PixL_bsdf_energy_compensation_lut_generation", "tools/bsdf_energy_compensation_lut_generation/main.jai");
    //build_program(output_path, "PixL_bsdf_ms_gen_tables", "modules/BxDF/ms_gen_tables.jai");
    //build_program(output_path, "PixL_bsdf_tests", "modules/BxDF/tests.jai");
    //build_program(output_path, "PixL_test_renders", "source/test_renders.jai");

    set_build_options_dc(.{do_output=false});
}

message_loop :: ()
{
    while true
    {
        message := compiler_wait_for_message();
        if message.kind ==
        {
          case .COMPLETE;
              break;
        }
    }
}

#run build();

#if OS == .WINDOWS
{
    Windows :: #import "Windows";
    getenv :: Windows.getenv;
}
else
{
    Posix :: #import "Posix";
    getenv :: Posix.getenv;
}

#import "Basic";
#import "Compiler";
#import "File";
#import "String";
