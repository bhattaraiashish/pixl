#scope_export

Spectrum :: #type,isa Vector3;

Spectrum_One  :: Spectrum.{1, 1, 1};
Spectrum_Zero :: Spectrum.{0, 0, 0};

Surface :: struct
{
    // Diffuse
    color                : Spectrum;
    diffuse_roughness    : float;

    // Dielectrics
    specular_ior         : float;
    specular_weight      : float;
    transmission_weight  : float;

    // Glossy/Specular
    specular_roughness   : float;
    specular_anisotropic : float;

    // Metals
    metallic             : float;
    reflectance          : Spectrum;
    edge_tint            : Spectrum;
    falloff              : Spectrum;

    // Ambient Medium
    geometry_opacity     : float;

    // TODO: Include these into the BRDF
    absorption       : Spectrum;
    emission         : Spectrum;
}

Diffuse_Shading_Info :: struct
{
    albedo                              : Spectrum;
    roughness                           : float;
    specular_eta_t_over_eta_i           : float;
    specular_microfacet_alpha           : float;
    specular_energy_complement_wo_dot_n : float;
    specular_avg_energy_complement      : float;
}

Glossy_Specular_Shading_Info :: struct
{
    microfacet_alpha                      : Vector2;

    transparent_dielectric_reflect_scale  : float;
    transparent_dielectric_transmit_scale : float;
    opaque_dielectric_reflect_scale       : float;
    eta_t_over_eta_i_transparent          : float;
    eta_t_over_eta_i_opaque               : float;

    metal_scale                           : float;
    reflectance                           : Spectrum;
    edge_tint                             : Spectrum;
    falloff                               : Spectrum;
}

Multi_Scatter_Dielectric_Shading_Info :: struct
{
    microfacet_alpha           : float;
    eta_t_over_eta_i           : float;
    energy_complement_wo_dot_n : float;
    reflection_ratio           : float;
    reflect_scale              : Spectrum;
    transmit_scale             : Spectrum;
}

Multi_Scatter_Metal_Shading_Info :: struct
{
    microfacet_alpha           : float;
    average_energy_complement  : float;
    energy_complement_wo_dot_n : float;
    scale                      : Spectrum;
}

Shading_Info :: struct
{
    diffuse                  : Diffuse_Shading_Info;
    glossy_specular          : Glossy_Specular_Shading_Info;
    multi_scatter_dielectric : Multi_Scatter_Dielectric_Shading_Info;
    multi_scatter_metal      : Multi_Scatter_Metal_Shading_Info;
    geometry_opacity         : float;
}

Shading_Context :: struct
{
    using info   : Shading_Info;
    wo           : Vector3;
    weights      : Lobe_Weights;
}

Lobe_Weights :: [LOBE_COUNT]float;

Transport :: enum u32
{
    RADIANCE;
    IMPORTANCE;
}

Lobe_Type :: enum_flags u32
{
    NONE         :: 0;
    REFLECTION   :: 0x1;
    TRANSMISSION :: 0x2;
    DIFFUSE      :: 0x4;
    GLOSSY       :: 0x8;
    SPECULAR     :: 0x10;
}

Sample :: struct
{
    weight    : Spectrum;
    pdf       : float;
    wi        : Vector3;
    lobe_type : Lobe_Type;
}

make_spectrum :: inline (x: float, y: float, z: float) -> Spectrum
{
    return .{x, y, z};
}

make_spectrum :: inline (x: float) -> Spectrum
{
    return make_spectrum(x, x, x);
}

make_sample :: inline (weight: Spectrum, pdf: float, wi: Vector3, lobe_type: Lobe_Type) -> Sample
{
    return .{
        weight    = weight,
        pdf       = pdf,
        wi        = wi,
        lobe_type = lobe_type
    };
}

make_zero_sample :: inline () -> Sample
{
    return .{
        weight    = Spectrum_Zero,
        pdf       = 0.0,
        wi        = .{0, 0, 0},
        lobe_type = 0
    };
}

//------------------------------------------------------------------------
// Sampling

#scope_export

sample_uniform_hemisphere :: (u1: float, u2: float) -> Vector3
{
    r   := sqrt(1.0 - u1 * u1);
    phi := 2.0 * PI * u2;
    L   : Vector3 = ---;
    L.x  = r * cos(phi);
    L.y  = r * sin(phi);
    L.z  = u1;
    return L;
}

pdf_uniform_hemisphere :: () -> float
{
    return 1.0 / (2.0 * PI);
}

sample_uniform_sphere :: (u1: float, u2: float) -> Vector3
{
    z   := 1.0 - 2.0 * u1;
    r   := sqrt(1.0 - z * z);
    phi := 2 * PI * u2;
    L   : Vector3 = ---;
    L.x  = r * cos(phi);
    L.y  = r * sin(phi);
    L.z  = z;
    return L;
}

pdf_uniform_sphere :: () -> float
{
    return 0.25 * RCP_PI;
}

sample_cosine :: (u1: float, u2: float) -> Vector3
{
    ct  := sqrt(u1);
    st  := sqrt(1.0 - u1);
    phi := 2.0 * PI * u2;
    x   := st * cos(phi);
    y   := st * sin(phi);
    z   := ct;
    return .{x, y, z};
}

pdf_cosine :: (wi: Vector3) -> float
{
    return wi.z * RCP_PI;
}

//------------------------------------------------------------------------
// Utils

max_spectrum :: inline (s: Spectrum) -> float
{
    return max(s.x, s.y, s.z);
}

reflect :: inline (I: Vector3, N: Vector3) -> Vector3
{
    return normalize(I - 2.0 * dot(N, I) * N);
}

refract :: inline (I: Vector3, N: Vector3, eta_t_over_eta_i: float) -> Vector3, bool
{
    eta_i_over_eta_t := 1.0 / eta_t_over_eta_i;

    cos_i  := -dot(N, I);
    sin2_t := max(0.0, 1.0 - cos_i * cos_i) * eta_i_over_eta_t * eta_i_over_eta_t;
    if (sin2_t < 1.0)
    {
        cos_t := sqrt(1.0 - sin2_t);
        R     := I * eta_i_over_eta_t + (cos_i * eta_i_over_eta_t - cos_t) * N;
        return normalize(R), true;
    }
    return .{}, false;
}

#scope_module

RCP_PI :: 1.0 / PI;
