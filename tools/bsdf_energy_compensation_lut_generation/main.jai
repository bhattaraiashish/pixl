//------------------------------------------------------------------------
// From integration.cu

Integrate_Method :: enum s32
{
    DIRECTIONAL_ALBEDO;
    HEMISPHERICAL_ALBEDO;
}

Glossy_Specular_Type :: enum s32
{
    METAL;
    DIELECTRIC_OPAQUE;
    DIELECTRIC_TRANSPARENT;
}

Kernel_Result :: struct
{
    name      : string;
    devptr    : CUdeviceptr;
    n_x       : s32;
    n_y       : s32;
    n_z       : s32;
    count     : int;
    stream    : CUstream;
}

KERNEL_DEFAULT_ARGUMENTS :: 4;
KERNEL_MAX_ARGUMENTS     :: 12;

execute_kernel :: (func: CUfunction, name: string, xn: s32, yn: s32, zn: s32, args: ..Any) -> Kernel_Result
{
    print("Executing: %...\n", name);

    BLOCK_SIZE :: 8;

    if (xn > 1 && xn % BLOCK_SIZE != 0)
    {
        print("WARNING: xn=% is not divisible by %\n", xn, BLOCK_SIZE);
    }

    if (yn > 1 && yn % BLOCK_SIZE != 0)
    {
        print("WARNING: yn=% is not divisible by %\n", yn, BLOCK_SIZE);
    }

    if (zn > 1 && zn % BLOCK_SIZE != 0)
    {
        print("WARNING: zn=% is not divisible by %\n", zn, BLOCK_SIZE);
    }

    result: Kernel_Result;
    result.name      = name;
    result.n_x       = xn;
    result.n_y       = yn;
    result.n_z       = zn;
    result.count     = xn * yn * zn;

    status := cuMemAlloc(*result.devptr, result.count.(u64) * size_of(float));
    cu_handle_error(status, "Failed to allocate memory");

    status = cuStreamCreate(*result.stream, xx CUstream_flags_enum.CU_STREAM_DEFAULT);
    cu_handle_error(status, "Failed to create stream");

    config: CUlaunchConfig;

    config.blockDimX = xx ifx xn == 1 then 1 else BLOCK_SIZE;
    config.blockDimY = xx ifx yn == 1 then 1 else BLOCK_SIZE;
    config.blockDimZ = xx ifx zn == 1 then 1 else BLOCK_SIZE;
    config.gridDimX  = xx xn / config.blockDimX;
    config.gridDimY  = xx yn / config.blockDimY;
    config.gridDimZ  = xx zn / config.blockDimZ;
    config.hStream   = result.stream;

    num_args := KERNEL_DEFAULT_ARGUMENTS + args.count;

    if (num_args > KERNEL_MAX_ARGUMENTS)
    {
        print("ERROR: Number of arguments to kernel is larger than expected. Arguments Count = %, Max Expected = %\n", num_args, KERNEL_MAX_ARGUMENTS);
        exit(1);
    }

    kargs: [KERNEL_MAX_ARGUMENTS]*void;
    kargs[0] = *result.devptr;
    kargs[1] = *result.n_x;
    kargs[2] = *result.n_y;
    kargs[3] = *result.n_z;

    for args
    {
        kargs[KERNEL_DEFAULT_ARGUMENTS + it_index] = it.value_pointer;
    }

    status = cuLaunchKernelEx(*config, func, kargs.data, null);
    cu_handle_error(status, "Failed to launch kernel");

    return result;
}

execute_integrate :: (func: CUfunction, xn: s32, yn: s32, zn: s32, n_samples: s64, type: Glossy_Specular_Type, method: Integrate_Method) -> Kernel_Result
{
    name := tprint("%_%", type, ifx method == .DIRECTIONAL_ALBEDO then "ENERGY" else "AVG_ENERGY");
    return execute_kernel(func, name, xn, yn, zn, n_samples, type, method);
}

Output_Options :: struct
{
    quantize   := false;
    complement := false;
}

main :: ()
{
    success, options := parse_arguments(Output_Options);
    if !success return;

    status : CUresult;

    status = cuInit(0);
    cu_handle_error(status, "Failed to initialize");

    dev : CUdevice;
    ctx : CUcontext;
    mod : CUmodule;

    status = cuDeviceGet(*dev, 0);
    cu_handle_error(status, "Failed to get device");

    status = cuCtxCreate(*ctx, null, 0, dev);
    cu_handle_error(status, "Failed to create context");

    status = cuModuleLoadFatBinary(*mod, INTEGRATION_FATCUBIN.data.(*void));
    cu_handle_error(status, "Failed to load fat binary");

    KERNEL_NAMES :: string.["integrate_glossy_specular\0", "calculate_dielectric_reflection_ratio\0"];
    kernels: [2]CUfunction;

    for * kernels
    {
        status = cuModuleGetFunction(it, mod, KERNEL_NAMES[it_index].data);
        cu_handle_error(status, "Failed to get kernel function");
    }

    N :: 32;

    results: [7]Kernel_Result;

    results[0] = execute_integrate(kernels[0], N, 1, 1, 16 * 1024 * 1024, .METAL, .HEMISPHERICAL_ALBEDO);
    results[1] = execute_integrate(kernels[0], N, N, 1,  8 * 1024 * 1024, .METAL, .DIRECTIONAL_ALBEDO);
  
    results[2] = execute_integrate(kernels[0], N, 1, N, 16 * 1024 * 1024, .DIELECTRIC_OPAQUE, .HEMISPHERICAL_ALBEDO);
    results[3] = execute_integrate(kernels[0], N, N, N,  8 * 1024 * 1024, .DIELECTRIC_OPAQUE, .DIRECTIONAL_ALBEDO);

    results[4] = execute_integrate(kernels[0], N, 1, N, 16 * 1024 * 1024, .DIELECTRIC_TRANSPARENT, .HEMISPHERICAL_ALBEDO);
    results[5] = execute_integrate(kernels[0], N, N, N,  8 * 1024 * 1024, .DIELECTRIC_TRANSPARENT, .DIRECTIONAL_ALBEDO);

    for 0..5
    {
        print("Waiting for %...\n", results[it].name);
        status = cuStreamSynchronize(results[it].stream);
        cu_handle_error(status, "Failed to synchronize stream");
    }

    results[6] = execute_kernel(kernels[1], "DIELECTRIC_REFLECTION_RATIO", N, 1, N, results[4].devptr);

    status = cuStreamSynchronize(results[6].stream);
    cu_handle_error(status, "Failed to synchronize stream");

    //------------------------------------------------------------------------

    builder: String_Builder;

    now   := current_time_consensus();
    local := to_calendar(now, .LOCAL);
    date  := calendar_to_string(local);

    print(*builder, "//\n");
    print(*builder, "// Generated at % by bsdf_energy_compensation_lut_generation using the following command:\n", date);
    {
        print(*builder, "//\n// bsdf_energy_compensation_lut_generation ");
        args := get_command_line_arguments();
        for 1..args.count-1
        {
            print(*builder, "% ", args[it]);
        }
        print(*builder, "\n//\n");
    }

    max_count := 0;
    for results
    {
        max_count = max(max_count, it.count);
    }

    values := NewArray(max_count, float, initialized=false);

    print(*builder, "LUT_SIZE : s32 : %;\n", N);

    for results
    {
        print("Writing %...\n", it.name);

        status = cuMemcpyDtoH_v2(values.data, it.devptr, it.count.(u64) * size_of(float));
        cu_handle_error(status, "Failed to synchronize stream");

        complement := options.complement;
        // Don't complement dielectric reflection ratio
        if it_index == 6 complement = false;

        write_lut(*builder, it.name, values, it.n_x, it.n_y, it.n_z, options.quantize, complement);
    }

    output := "bsdf_energy_compensation_lut.jai";
    if options.quantize
    {
        output = "bsdf_energy_compensation_quantized_lut.jai";
    }
    write_entire_file(output, *builder);
}

write_lut :: (builder: *String_Builder, name: string, values: []float, n_x: int, n_y: int, n_z: int, quantize: bool, complement: bool)
{
    type    := ifx quantize then "u16" else "float";
    postfix := ifx complement then "_COMPLEMENT" else "";

    print(builder, "%%_LUT  : [%]% : .[\n", name, postfix, n_x * n_y * n_z, type);

    for z:0..n_z-1
    {
        for y:0..n_y-1
        {
            for x:0..n_x-1
            {
                index := z * n_y * n_x + y * n_x + x;
                value := values[index];

                if complement
                {
                    value = 1.0 - value;
                }

                if quantize
                {
                    quantized  := clamp(value * U16_MAX.(float), 0.0, U16_MAX.(float)).(u16);
                    print(builder, "0x%,", FormatInt.{value=quantized, base=16, minimum_digits=4});
                }
                else
                {
                    print(builder, "%,", FormatFloat.{value=value, width=8, zero_removal=.NO});
                }
            }
            if n_y > 1 print(builder, "\n");
        }
        if n_z > 1 print(builder, "\n");
    }

    print(builder, "];\n\n");
}

cu_handle_error :: (status: CUresult, msg: string)
{
    if (status != .CUDA_SUCCESS)
    {
        cerr: *u8;
        cuGetErrorString(status, *cerr);
        print("ERROR: %. Reason: %\n", msg, to_string(cerr));
        exit(1);
    }
}

INTEGRATION_FATCUBIN :: #run -> []u8
{
    print("Building cuda kernels...\n");

    fatbin := path_join(#filepath, "integration.fatbin");

    pr := run_command(
        "nvcc", "--fatbin",
        "--output-file", fatbin,
        "-O3", "--std", "c++17",
        "--machine", "64",
        "-gencode", "arch=compute_89,code=sm_89",
        "-gencode", "arch=compute_89,code=compute_89",
        path_join(#filepath, "integration.cu")
    );

    if pr.exit_code != 0
    {
        exit(pr.exit_code);
    }

    data := read_entire_file(fatbin);
    return data.([]u8);
}

#import "Compiler";
#import "Cuda";
#import "File";
#import "Basic";
#import "Process";
#import "String";
#import "Math";
#import "Command_Line";
