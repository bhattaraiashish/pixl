#scope_export

prepare_surface :: (surface: Surface, wo: Vector3) -> Shading_Context
{
    if (wo.z <= 0.0)
    {
        return .{};
    }

    //------------------------------------------------------------------------
    // Lobe contribution
    metallic                := surface.metallic;
    dielectric              := 1.0 - metallic;
    opaque                  := 1.0 - surface.transmission_weight;
    opaque_dielectric       := opaque * dielectric;
    transparent_dielectric  := surface.transmission_weight * dielectric;

    //------------------------------------------------------------------------
    // Glossy Specular Params

    eta_t_over_eta_i_transparent := surface.specular_ior;
    if (eta_t_over_eta_i_transparent >= 1.0)
    {
        eta_t_over_eta_i_transparent = max(eta_t_over_eta_i_transparent, MIN_REASONABLE_IOR);
    }
    else
    {
        eta_t_over_eta_i_transparent = min(eta_t_over_eta_i_transparent, 1.0 / MIN_REASONABLE_IOR);
    }

    eta_t_over_eta_i_opaque := calculate_specular_ior_for_dielectric_opaque(surface.specular_weight, eta_t_over_eta_i_transparent);
    isotropic_alpha         := microfacet_isotropic_alpha(surface.specular_roughness, true);
    anisotropic_alpha       := microfacet_anisotropic_alpha(surface.specular_roughness, surface.specular_anisotropic, true);

    ctx: Shading_Context;

    ctx.diffuse.albedo                              = surface.color * opaque_dielectric;
    ctx.diffuse.roughness                           = surface.diffuse_roughness;
    ctx.diffuse.specular_eta_t_over_eta_i           = eta_t_over_eta_i_opaque;
    ctx.diffuse.specular_microfacet_alpha           = isotropic_alpha;
    ctx.diffuse.specular_energy_complement_wo_dot_n = read_dielectric_opaque_energy_complement(isotropic_alpha, wo.z, eta_t_over_eta_i_opaque);
    ctx.diffuse.specular_avg_energy_complement      = read_dielectric_opaque_average_energy_complement(isotropic_alpha, eta_t_over_eta_i_opaque);

    ctx.glossy_specular.microfacet_alpha                      = anisotropic_alpha;
    ctx.glossy_specular.transparent_dielectric_reflect_scale  = transparent_dielectric * surface.specular_color;
    ctx.glossy_specular.transparent_dielectric_transmit_scale = transparent_dielectric * Spectrum_One;
    ctx.glossy_specular.opaque_dielectric_reflect_scale       = opaque_dielectric * surface.specular_color;
    ctx.glossy_specular.eta_t_over_eta_i_transparent          = eta_t_over_eta_i_transparent;
    ctx.glossy_specular.eta_t_over_eta_i_opaque               = eta_t_over_eta_i_opaque;

    ctx.glossy_specular.metal_scale                           = metallic;
    ctx.glossy_specular.reflectance                           = surface.reflectance;
    ctx.glossy_specular.falloff                               = surface.falloff;

    ctx.multi_scatter_dielectric.microfacet_alpha             = isotropic_alpha;
    ctx.multi_scatter_dielectric.eta_t_over_eta_i             = eta_t_over_eta_i_transparent;
    ctx.multi_scatter_dielectric.energy_complement_wo_dot_n   = read_dielectric_transparent_energy_complement(isotropic_alpha, wo.z, eta_t_over_eta_i_transparent);
    ctx.multi_scatter_dielectric.reflection_ratio             = read_dielectric_reflection_ratio(isotropic_alpha, eta_t_over_eta_i_transparent);
    ctx.multi_scatter_dielectric.reflect_scale                = transparent_dielectric * surface.specular_color;
    ctx.multi_scatter_dielectric.transmit_scale               = transparent_dielectric * Spectrum_One;

    ctx.multi_scatter_metal.microfacet_alpha           = isotropic_alpha;
    ctx.multi_scatter_metal.average_energy_complement  = 0.0;
    ctx.multi_scatter_metal.energy_complement_wo_dot_n = 0.0;
    ctx.multi_scatter_metal.scale                      = Spectrum_Zero;

    if has_visible_energy_loss(ctx.multi_scatter_metal)
    {
        ctx.multi_scatter_metal.average_energy_complement  = read_metal_average_energy_complement(ctx.multi_scatter_metal.microfacet_alpha);
        ctx.multi_scatter_metal.energy_complement_wo_dot_n = read_metal_energy_complement(ctx.multi_scatter_metal.microfacet_alpha, wo.z);

        // Fresnel adjustment is done based on the following blog:
        // https://blog.selfshadow.com/2018/06/04/multi-faceted-part-2/
        avg_energy                    := 1.0 - ctx.multi_scatter_metal.average_energy_complement;
        avg_fresnel                   := fresnel_average_metal(surface.reflectance, surface.edge_tint, surface.falloff);
        scale_num                     := metallic * avg_fresnel * avg_fresnel * avg_energy;
        scale_den                     := Spectrum_One - avg_fresnel * ctx.multi_scatter_metal.average_energy_complement;
        ctx.multi_scatter_metal.scale  = scale_num / max(scale_den, make_spectrum(1.0e-6));
    }

    ctx.ambient.alpha = surface.geometry_opacity;
    ctx.volume        = prepare_volume(surface);
    ctx.wo            = wo;

    //------------------------------------------------------------------------
    // Lobe PDF Weights

    for 0..BASE_LOBE_COUNT-1
    {
        ctx.weights[it] = estimate_base_lobe(ctx.base, wo, it.(Base_Lobe_Index));
    }

    return ctx;
}

sample_surface :: (using ctx: Shading_Context, u_sample: Vector3) -> Sample
{
    ux     := clamp_random_number(u_sample.x);
    uy     := clamp_random_number(u_sample.y);
    p      := clamp_random_number(u_sample.z);

    if (p > ambient.alpha)
    {
        return make_sample(Spectrum_One, 1.0, -wo, .TRANSMISSION | .SPECULAR);
    }

    p       = p / ambient.alpha;
    sample := sample_base_surface(base, wo, .{ux, uy, p});
    return sample;
}

//------------------------------------------------------------------------
// Base Surface

evaluate_base_surface :: (using info: Base_Shading_Info, wo: Vector3, wi: Vector3) -> Spectrum
{
    weight := Spectrum_Zero;
    for 0..BASE_LOBE_COUNT-1
    {
        weight += evaluate_base_lobe(info, wo, wi, it.(Base_Lobe_Index));
    }
    return weight;
}

pdf_base_surface :: (using info: Base_Shading_Info, wo: Vector3, wi: Vector3) -> float
{
    pdf := 0.0;
    for 0..BASE_LOBE_COUNT-1
    {
        pdf += weights[it] * pdf_base_lobe(info, wo, wi, it.(Base_Lobe_Index));
    }
    return pdf;
}

sample_base_surface :: (using info: Base_Shading_Info, wo: Vector3, u: Vector3) -> Sample
{
    total_weight := 0.0;
    for weights
    {
        total_weight += it;
    }

    index, p := pick_base_lobe(weights, u.z * total_weight);
    sample   := sample_base_lobe(info, wo, .{u.x, u.y, p}, index);

    if !sample.lobe_type return make_zero_sample();

    if !(sample.lobe_type & .SPECULAR)
    {
        radiance := sample.weight * sample.pdf;
        pdf      := sample.pdf * weights[index];
        
        for 0..BASE_LOBE_COUNT-1
        {
            other := it.(Base_Lobe_Index);
            if (other != index)
            {
                radiance += evaluate_base_lobe(info, wo, sample.wi, other);
                pdf      += weights[other] * pdf_base_lobe(info, wo, sample.wi, other);
            }
        }

        sample.pdf = pdf / total_weight;
        sample.weight = radiance / sample.pdf;
    }
    else
    {
        sample.weight *= total_weight / weights[index];
    }

    return sample;
}

#scope_module

prepare_volume :: (surface: Surface) -> Volume_Info
{
    MIN_TRANSMISSION_DEPTH :: 1.0e-3;
    MIN_TRANSMISSION_COLOR :: 1.0e-3;

    volume: Volume_Info;

    if (surface.transmission_depth <= 0.0)
    {
        return volume;
    }

    depth          := max(surface.transmission_depth, MIN_TRANSMISSION_DEPTH);
    color          := max(surface.transmission_color, make_spectrum(MIN_TRANSMISSION_COLOR));
    rcp_depth      := 1.0 / depth;
    extinction     := -log(color) * rcp_depth;
    scattering     := color * rcp_depth;
    absorption     := extinction - scattering;

    min_absorption := min(absorption.x, absorption.y, absorption.z);
    if min_absorption < 0.0
    {
        absorption -= make_spectrum(min_absorption);
    }

    volume.extinction = absorption + scattering;
    volume.albedo.x   = ifx volume.extinction.x > 0.0 scattering.x / volume.extinction.x;
    volume.albedo.y   = ifx volume.extinction.y > 0.0 scattering.y / volume.extinction.y;
    volume.albedo.z   = ifx volume.extinction.z > 0.0 scattering.z / volume.extinction.z;

    return volume;
}

Base_Lobe_Index :: enum u32
{
    DIFFUSE                  :: 0;
    GLOSSY_SPECULAR          :: 1;
    MULTI_SCATTER_DIELECTRIC :: 2;
    MULTI_SCATTER_METAL      :: 3;
}

BASE_LOBE_COUNT :: #run type_info(Base_Lobe_Index).values.count;

calculate_specular_ior_for_dielectric_opaque :: (specular_weight: float, eta_t_over_eta_i: float) -> float
{
    sgn :: x => ((0.0 < x).(float) - (x < 0.0).(float));
    f_sqrt    := (1.0 - eta_t_over_eta_i) / (1.0 + eta_t_over_eta_i);
    e         := sgn(eta_t_over_eta_i - 1.0) * sqrt(specular_weight * f_sqrt * f_sqrt);
    effective := (1.0 + e) / (1 - e);
    return effective;
}

pick_base_lobe :: (weights: Base_Lobe_Weights, p: float) -> index: Base_Lobe_Index, remapped_p: float
{
    weights_so_far := 0.0;
    for 0..BASE_LOBE_COUNT-2
    {
        it_lobe_weight := weights[it];
        if (p < weights_so_far + it_lobe_weight)
        {
            remapped_p := clamp_random_number((p - weights_so_far) / it_lobe_weight);
            return it.(Base_Lobe_Index), remapped_p;
        }
        weights_so_far += it_lobe_weight;
    }
    last        := BASE_LOBE_COUNT - 1;
    last_weight := weights[last];
    remapped_p  := clamp_random_number((p - weights_so_far) / last_weight);
    return last.(Base_Lobe_Index), FLOAT32_ONE_MINUS_EPSILON;
}

evaluate_base_lobe :: (info: Base_Shading_Info, wo: Vector3, wi: Vector3, index: Base_Lobe_Index) -> Spectrum
{
    if #complete index ==
    {
        case .DIFFUSE;
            return evaluate_diffuse(info.diffuse, wo, wi);
        case .GLOSSY_SPECULAR;
            return evaluate_glossy_specular(info.glossy_specular, wo, wi);
        case .MULTI_SCATTER_DIELECTRIC;
            return evaluate_multi_scatter_dielectric(info.multi_scatter_dielectric, wo, wi);
        case .MULTI_SCATTER_METAL;
            return evaluate_multi_scatter_metal(info.multi_scatter_metal, wo, wi);
    }
    return Spectrum_Zero;
}

pdf_base_lobe :: (info: Base_Shading_Info, wo: Vector3, wi: Vector3, index: Base_Lobe_Index) -> float
{
    if #complete index ==
    {
        case .DIFFUSE;
            return pdf_diffuse(info.diffuse, wo, wi);
        case .GLOSSY_SPECULAR;
            return pdf_glossy_specular(info.glossy_specular, wo, wi);
        case .MULTI_SCATTER_DIELECTRIC;
            return pdf_multi_scatter_dielectric(info.multi_scatter_dielectric, wo, wi);
        case .MULTI_SCATTER_METAL;
            return pdf_multi_scatter_metal(info.multi_scatter_metal, wo, wi);
    }
    return 0.0;
}

sample_base_lobe :: (info: Base_Shading_Info, wo: Vector3, u: Vector3, index: Base_Lobe_Index) -> Sample
{
    if #complete index ==
    {
        case .DIFFUSE;
            return sample_diffuse(info.diffuse, wo, u);
        case .GLOSSY_SPECULAR;
            return sample_glossy_specular(info.glossy_specular, wo, u);
        case .MULTI_SCATTER_DIELECTRIC;
            return sample_multi_scatter_dielectric(info.multi_scatter_dielectric, wo, u);
        case .MULTI_SCATTER_METAL;
            return sample_multi_scatter_metal(info.multi_scatter_metal, wo, u);
    }
    return .{};
}

estimate_base_lobe :: (info: Base_Shading_Info, wo: Vector3, index: Base_Lobe_Index) -> float
{
    if #complete index ==
    {
        case .DIFFUSE;
            return estimate_diffuse(info.diffuse, wo);
        case .GLOSSY_SPECULAR;
            return estimate_glossy_specular(info.glossy_specular, wo);
        case .MULTI_SCATTER_DIELECTRIC;
            return estimate_multi_scatter_dielectric(info.multi_scatter_dielectric, wo);
        case .MULTI_SCATTER_METAL;
            return estimate_multi_scatter_metal(info.multi_scatter_metal, wo);
    }
    return 0.0;
}

//------------------------------------------------------------------------
// Diffuse EON BxDF

// EON: A practical energy-preserving rough diffuse BRDF
// https://arxiv.org/pdf/2410.18026

#scope_module

evaluate_diffuse :: (using info: Diffuse_Shading_Info, wo: Vector3, wi: Vector3) -> Spectrum
{
    if wi.z > 0.0
    {
        wh        := normalize(wo + wi);
        scale     := calculate_diffuse_contribution_scale(info, wi);
        f         := diffuse_eon_spectrum(wo, wi, albedo, roughness);
        weight    := scale * f * wi.z;
        return weight;
    }
    return Spectrum_Zero;
}

pdf_diffuse :: (using info: Diffuse_Shading_Info, wo: Vector3, wi: Vector3) -> float
{
    if wo.z > 0.0
    {
        wo_dot_n := wo.z;
        p_u      := pow(roughness, 0.1) * (0.162925 + wo_dot_n * (-0.372058 + (0.538233 - 0.290822 * wo_dot_n) * wo_dot_n));
        p_c      := 1.0 - p_u;
        pdf_c    := pdf_cltc(wo, wi, roughness);
        pdf_u    := pdf_uniform_hemisphere();
        pdf      := p_u * pdf_u + p_c * pdf_c;
        return pdf;
    }
    return 0.0;
}

sample_diffuse :: (using info: Diffuse_Shading_Info, wo: Vector3, u: Vector3) -> Sample
{
    wo_dot_n  := wo.z;
    p_u       := pow(roughness, 0.1) * (0.162925 + wo_dot_n * (-0.372058 + (0.538233 - 0.290822 * wo_dot_n) * wo_dot_n));
    p_c       := 1.0 - p_u; // probability of CLTC sample

    wi        : Vector3 = ---;
    pdf_c     : float   = ---;
    p         := u.z;

    if (p < p_u)
    {
        wi    = sample_uniform_hemisphere(u.x, u.y); // sample wi from uniform lobe
        pdf_c = pdf_cltc(wo, wi, roughness); // evaluate CLTC PDF at wi
    }
    else
    {
        wi, pdf_c = sample_cltc(wo, roughness, u.x, u.y); // sample wi from CLTC lobe
    }

    if wi.z > 0.0
    {
        wh     := normalize(wo + wi);
        scale  := calculate_diffuse_contribution_scale(info, wi);
        f      := diffuse_eon_spectrum(wo, wi, albedo, roughness);
        pdf_u  := pdf_uniform_hemisphere();
        pdf    := p_u * pdf_u + p_c * pdf_c; // MIS PDF of wi
        weight := scale * f * wi.z / pdf;
        return make_sample(weight, pdf, wi, .REFLECTION | .DIFFUSE);
    }

    return make_zero_sample();
}

estimate_diffuse :: (using info: Diffuse_Shading_Info, wo: Vector3) -> float
{
    estimate := specular_energy_complement_wo_dot_n / specular_avg_energy_complement * max_spectrum(albedo);
    return estimate;
}

#scope_file

calculate_diffuse_contribution_scale :: (using info: Diffuse_Shading_Info, wi: Vector3) -> float
{
    if (specular_avg_energy_complement > 0.0)
    {
        specular_energy_complement_wi_dot_n := read_dielectric_opaque_energy_complement(specular_microfacet_alpha, wi.z, specular_eta_t_over_eta_i);
        scale                               := specular_energy_complement_wo_dot_n * specular_energy_complement_wi_dot_n / specular_avg_energy_complement;
        return scale;
    }
    return 0.0;
}

FON1 :: 0.5 - 2.0 / (3.0 * PI);
FON2 :: 2.0 / 3.0 - 28.0 / (15.0 * PI);

e_fon_approx :: (mu: float, roughness: float) -> float
{
    G1      :: 0.057108529;
    G2      :: 0.49188187;
    G3      :: -0.33218144;
    G4      :: 0.07144299;
    mucomp  := 1.0 - mu;
    goverpi := mucomp * (G1 + mucomp * (G2 + mucomp * (G3 + mucomp * G4)));
    return (1.0 + roughness * goverpi) / (1.0 + FON1 * roughness);
}

ltc_coeffs :: (mu: float, roughness: float) -> float, float, float, float
{
    r := roughness;
    a := 1.0 + r * (0.303392 + (-0.518982 + 0.111709 * mu) * mu + (-0.276266 + 0.335918 * mu) * r);
    b := sdiv(r * (-1.16407 + 1.15859 * mu + (0.150815 - 0.150105 * mu) * r), (mu * mu * mu - 1.43545));
    c := 1.0 + (0.20013 + (-0.506373 + 0.261777 * mu) * mu) * r;
    d := sdiv(((0.540852 + (-1.01625 + 0.475392 * mu) * mu) * r), (-1.0743 + mu * (0.0725628 + mu)));
    return a, b, c, d;
}

ltc_orthonormal_basis :: (w: Vector3) -> Matrix3
{
    lensq := dot(w.xy, w.xy);
    X     := ifx (lensq > 0.0) then (Vector3.{w.x, w.y, 0.0} / sqrt(lensq)) else Vector3.{1, 0, 0};
    Y     := Vector3.{-X.y, X.x, 0.0}; // cross(Z, X)
    Z     := Vector3.{0, 0, 1};

    LTC : Matrix3 = ---;
    LTC.v[0] = Vector3.{X.x, Y.x, Z.x};
    LTC.v[1] = Vector3.{X.y, Y.y, Z.y};
    LTC.v[2] = Vector3.{X.z, Y.z, Z.z};
    return LTC;
}

sample_cltc :: (w: Vector3, roughness: float, u1: float, u2: float) -> Vector3, float
{
    a, b, c, d := ltc_coeffs(w.z, roughness);         // coeffs of LTC M
    radius     := sqrt(u1);                           // CLTC sampling
    phi        := 2.0 * PI * u2;                      // CLTC sampling
    x          := radius * cos(phi);                  // CLTC sampling factors
    y          := radius * sin(phi);                  // CLTC sampling factors
    vz         := 1.0 / sqrt(d * d + 1.0);            // CLTC sampling factors
    s          := 0.5 * (1.0 + vz);                   // CLTC sampling factors
    x           = -lerp(sqrt(1.0 - y * y), x, s);     // CLTC sampling
    wh         := Vector3.{x, y, sqrt(max(1.0 - (x * x + y * y), 0.0))}; // H sample via CLTC
    pdf_h      := wh.z / (PI * s);                    // PDF of H sample
    wi         := Vector3.{a * wh.x + b * wh.z, c * wh.y, d * wh.x + wh.z}; // M H (unnormalized)
    len        := length(wi);                         // ∥M H∥=1/∥inv(M) H∥
    det        := c * (a - b * d);                    // |M|
    pdf_wi     := pdf_h * len * len * len / det;      // wi sample PDF
    from_LTC   := ltc_orthonormal_basis(w);           // wi -> local space
    wi          = normalize(from_LTC * wi);           // wi -> local space
    return wi, pdf_wi;
}

pdf_cltc :: (wo_local: Vector3, wi_local: Vector3, roughness: float) -> float
{
    to_LTC     := transpose(ltc_orthonormal_basis(wo_local)); // wo -> LTC space
    L          := to_LTC * wi_local;                          // wi -> LTC space
    a, b, c, d := ltc_coeffs(abs(wo_local.z), roughness);     // coeffs of LTC M
    det        := c * (a - b * d);                            // |M|
    wh         := Vector3.{c * (L.x - b * L.z), (a - b * d) * L.y, -c * (d * L.x - a * L.z)}; // adj(M)L
    lensq      := dot(wh, wh);                                // |M|∥inv(M) H∥
    vz         := 1.0 / sqrt(d * d + 1.0);                    // CLTC sampling factors
    s          := 0.5 * (1.0 + vz);                           // CLTC sampling factors
    pdf        := sdiv(det * det * max(wh.z, 0.0), lensq * lensq * PI * s);
    return pdf;
}

diffuse_eon_spectrum :: (wo: Vector3, wi: Vector3, albedo: Spectrum, roughness: float) -> Spectrum
{
    assert(wi.z > 0.0);
    wo_dot_n  := wo.z;
    wi_dot_n  := wi.z;
    wo_dot_wi := dot(wo, wi);
    s         := wo_dot_wi - wi_dot_n * wo_dot_n;
    s_over_t  := ifx (s > 0.0) then (s / max(max(wi_dot_n, wo_dot_n), 1.0e-4)) else s; // FON s/t
    af        := 1.0 / (1.0 + FON1 * roughness);                             // FON A coeff
    f_ss      := (albedo * RCP_PI) * af * (1.0 + roughness * s_over_t);          // single-scatter
    efo       := e_fon_approx(wo_dot_n, roughness);                          // FON V albedo
    efi       := e_fon_approx(wi_dot_n, roughness);                          // FON L albedo
    avg_ef    := af * (1.0 + FON2 * roughness);                              // average albedo
    rho_ms    := (albedo * albedo) * avg_ef / (Vector3.{1, 1, 1} - albedo * (1.0 - avg_ef));
    eps       := 1.0e-6;
    f_ms      := (rho_ms * RCP_PI) * max(eps, 1.0 - efo) * max(eps, 1.0 - efi) / max(eps, 1.0 - avg_ef); // multi-scatterlobe
    f         := f_ss + f_ms;
    return f;
}

//------------------------------------------------------------------------
// Glossy Specular BSDF

#scope_module

evaluate_glossy_specular :: (using info: Glossy_Specular_Shading_Info, wo: Vector3, wi: Vector3) -> Spectrum
{
    if is_delta_surface(info) return Spectrum_Zero;

    wo_dot_n := wo.z;
    wi_dot_n := wi.z;

    if wi_dot_n > 0.0
    {
        wh           := normalize(wo + wi);
        wo_dot_wh    := dot(wo, wh);
        dist         := microfacet_ggx_distribution(wh, microfacet_alpha);
        mask_shadow  := microfacet_ggx_mask_shadow(wo, wi, microfacet_alpha);
        coefficients := calculate_glossy_specular_coefficients(info, abs(wo_dot_wh));
        factor       := 1.0 / (4 * wo_dot_n);
        weight       := dist * mask_shadow * coefficients.reflect * factor;
        return weight;
    }
    else if wi_dot_n < 0.0
    {
        wh, ok := refracted_half_vector(wo, wi, eta_t_over_eta_i_transparent);
        if !ok return Spectrum_Zero;
        wi_dot_wh        := dot(wi, wh);
        wo_dot_wh        := dot(wo, wh);
        wo_dot_wi_dot_wh := wi_dot_wh * wo_dot_wh;
        if (wo_dot_wi_dot_wh < 0.0)
        {
            wo_dot_wh    := dot(wo, wh);
            dist         := microfacet_ggx_distribution(wh, microfacet_alpha);
            mask_shadow  := microfacet_ggx_mask_shadow(wo, wi, microfacet_alpha);
            coefficients := calculate_glossy_specular_coefficients(info, abs(wo_dot_wh));
            dwi          := square(wo_dot_wh + wi_dot_wh * eta_t_over_eta_i_transparent);
            factor       := square(eta_t_over_eta_i_transparent) * (-wo_dot_wi_dot_wh) / (dwi * wo_dot_n);
            weight       := dist * mask_shadow * coefficients.transmit * factor;
            return weight;
        }
    }

    return Spectrum_Zero;
}

pdf_glossy_specular :: (using info: Glossy_Specular_Shading_Info, wo: Vector3, wi: Vector3) -> float
{
    if is_delta_surface(info) return 0.0;

    wo_dot_n := wo.z;
    wi_dot_n := wi.z;

    if wi_dot_n > 0.0
    {
        wh            := normalize(wo + wi);
        wo_dot_wh     := dot(wo, wh);
        wi_dot_wh     := dot(wi, wh);
        if wo_dot_wh * wi_dot_wh > 0.0
        {
            dist          := microfacet_ggx_distribution(wh, microfacet_alpha);
            mask          := microfacet_ggx_mask(wo, microfacet_alpha);
            probabilities := calculate_glossy_specular_probabilities(info, abs(wo_dot_wh));
            factor        := wo_dot_wh / (4 * wi_dot_wh * wo_dot_n);
            pdf           := dist * mask * probabilities.reflect * factor;
            return pdf;
        }
    }
    else if wi_dot_n < 0.0
    {
        wh, ok := refracted_half_vector(wo, wi, eta_t_over_eta_i_transparent);
        if !ok return 0.0;
        wo_dot_wh        := dot(wo, wh);
        wi_dot_wh        := dot(wi, wh);
        wo_dot_wi_dot_wh := wi_dot_wh * wo_dot_wh;
        if (wo_dot_wi_dot_wh < 0.0)
        {
            dist          := microfacet_ggx_distribution(wh, microfacet_alpha);
            mask          := microfacet_ggx_mask(wo, microfacet_alpha);
            probabilities := calculate_glossy_specular_probabilities(info, abs(wo_dot_wh));
            dwi           := square(wo_dot_wh + wi_dot_wh * eta_t_over_eta_i_transparent);
            factor        := square(eta_t_over_eta_i_transparent) * (-wo_dot_wi_dot_wh) / (dwi * wo_dot_n);
            pdf           := dist * mask * probabilities.transmit * factor;
            return pdf;
        }
    }

    return 0.0;
}

sample_glossy_specular :: (using info: Glossy_Specular_Shading_Info, wo: Vector3, u: Vector3) -> Sample
{
    if !is_delta_surface(info)
    {
        wh        := microfacet_ggx_sample_vndf(wo, microfacet_alpha, u.x, u.y);
        wo_dot_wh := dot(wo, wh);
        if wo_dot_wh < 0.0
        {
            return make_zero_sample();
        }

        coefficients, probabilities := calculate_glossy_specular_coefficients_and_probabilities(info, wo_dot_wh);

        if (probabilities.total == 0.0)
            return make_zero_sample();

        if (u.z < probabilities.reflect)
        {
            wi := reflect(-wo, wh);
            if wi.z > 0.0
            {
                wo_dot_n    := wo.z;
                wi_dot_n    := wi.z;
                wi_dot_wh   := dot(wi, wh);
                dist        := microfacet_ggx_distribution(wh, microfacet_alpha);
                mask_shadow := microfacet_ggx_mask_shadow(wo, wi, microfacet_alpha);
                mask        := microfacet_ggx_mask(wo, microfacet_alpha);
                shadow      := mask_shadow / mask;
                weight      := coefficients.reflect * shadow / probabilities.reflect;
                factor      := wo_dot_wh / (4 * wi_dot_wh * wo_dot_n);
                pdf         := dist * mask * probabilities.reflect * factor;
                return make_sample(weight, pdf, wi, .REFLECTION | .GLOSSY);
            }
        }
        else
        {
            wi, refracted := refract(-wo, wh, eta_t_over_eta_i_transparent);
            if (refracted && wi.z < 0.0)
            {
                wo_dot_n    := wo.z;
                wo_dot_wh   := dot(wo, wh);
                wi_dot_wh   := dot(wi, wh);
                dist        := microfacet_ggx_distribution(wh, microfacet_alpha);
                mask_shadow := microfacet_ggx_mask_shadow(wo, wi, microfacet_alpha);
                mask        := microfacet_ggx_mask(wo, microfacet_alpha);
                shadow      := mask_shadow / mask;
                weight      := coefficients.transmit * shadow / probabilities.transmit;
                dwi         := square(wo_dot_wh + wi_dot_wh * eta_t_over_eta_i_transparent);
                factor      := square(eta_t_over_eta_i_transparent) * abs(wo_dot_wh * wi_dot_wh) / (dwi * wo_dot_n);
                pdf         := dist * mask * probabilities.transmit * factor;
                return make_sample(weight, pdf, wi, .TRANSMISSION | .GLOSSY);
            }
        }
    }
    else
    {
        wh                          := Vector3.{0, 0, 1};
        wo_dot_wh                   := dot(wo, wh);
        coefficients, probabilities := calculate_glossy_specular_coefficients_and_probabilities(info, wo_dot_wh);

        if (probabilities.total == 0.0)
            return make_zero_sample();

        if (u.z < probabilities.reflect)
        {
            wi     := reflect(-wo, wh);
            if wi.z > 0.0
            {
                weight := coefficients.reflect / probabilities.reflect;
                return make_sample(weight, 1.0, wi, .REFLECTION | .SPECULAR);
            }
        }
        else
        {
            wi, refracted := refract(-wo, wh, eta_t_over_eta_i_transparent);
            if (refracted && wi.z < 0.0)
            {
                weight := coefficients.transmit / probabilities.transmit;
                return make_sample(weight, 1.0, wi, .TRANSMISSION | .SPECULAR);
            }
        }
    }

    return make_zero_sample();
}

estimate_glossy_specular :: (using info: Glossy_Specular_Shading_Info, wo: Vector3) -> float
{
    coefficients := calculate_glossy_specular_coefficients(info, wo.z);
    estimate     := max_spectrum(coefficients.reflect + coefficients.transmit);
    return estimate;
}

#scope_file

refracted_half_vector :: (wo: Vector3, wi: Vector3, eta_t_over_eta_i: float) -> Vector3, bool
{
    wh := -normalize(wo + eta_t_over_eta_i * wi);
    ok := (eta_t_over_eta_i >= 1.0 && wh.z > 0.0) || (eta_t_over_eta_i < 1.0 && wh.z < 0.0);
    return wh, ok;
}

Glossy_Specular_Coefficient :: struct
{
    reflect  : Spectrum;
    transmit : Spectrum;
}

Glossy_Specular_Probability :: struct
{
    reflect  : float;
    transmit : float;
    total    : float;
}

calculate_glossy_specular_coefficients :: (using info: Glossy_Specular_Shading_Info, wo_dot_wh: float) -> Glossy_Specular_Coefficient
{
    coefficients: Glossy_Specular_Coefficient;
    transparent_fresnel   := fresnel_dielectric(eta_t_over_eta_i_transparent, wo_dot_wh);
    coefficients.reflect  += transparent_dielectric_reflect_scale * transparent_fresnel;
    coefficients.transmit += transparent_dielectric_transmit_scale * (Spectrum_One - transparent_fresnel);
    coefficients.reflect  += opaque_dielectric_reflect_scale * fresnel_dielectric(eta_t_over_eta_i_opaque, wo_dot_wh);
    coefficients.reflect  += metal_scale * fresnel_metal(reflectance, edge_tint, falloff, wo_dot_wh);
    return coefficients;
}

calculate_glossy_specular_probabilities :: (coefficients: Glossy_Specular_Coefficient) -> Glossy_Specular_Probability
{
    probabilities: Glossy_Specular_Probability;
    probabilities.reflect   = max_spectrum(coefficients.reflect);
    probabilities.transmit  = max_spectrum(coefficients.transmit);
    total_probability      := probabilities.reflect + probabilities.transmit;
    if (total_probability > FLOAT32_EPSILON)
    {
        probabilities.reflect  /= total_probability;
        probabilities.transmit /= total_probability;
        probabilities.total     = 1.0;
    }
    else
    {
        probabilities.reflect  = 0.0;
        probabilities.transmit = 0.0;
        probabilities.total    = 0.0;
    }
    return probabilities;
}

calculate_glossy_specular_coefficients_and_probabilities :: (using info: Glossy_Specular_Shading_Info, wo_dot_wh: float) -> Glossy_Specular_Coefficient, Glossy_Specular_Probability
{
    coefficients  := calculate_glossy_specular_coefficients(info, wo_dot_wh);
    probabilities := calculate_glossy_specular_probabilities(coefficients);
    return coefficients, probabilities;
}

calculate_glossy_specular_probabilities :: (using info: Glossy_Specular_Shading_Info, wo_dot_wh: float) -> Glossy_Specular_Probability
{
    coefficients, probabilities := calculate_glossy_specular_coefficients_and_probabilities(info, wo_dot_wh);
    return probabilities;
}

//------------------------------------------------------------------------
// Multi Scatter Dielectric BSDF

#scope_export

evaluate_multi_scatter_dielectric :: (using info: Multi_Scatter_Dielectric_Shading_Info, wo: Vector3, wi: Vector3) -> Spectrum
{
    if has_visible_energy_loss(info)
    {
        clamped_weight := calculate_multi_scatter_dielectric_energy(info, wi, true);
        if wi.z > 0.0
        {
            weight := reflect_scale * clamped_weight * wi.z * RCP_PI;
            return weight;
        }
        else if wi.z < 0.0
        {
            weight := transmit_scale * clamped_weight * (-wi.z) * RCP_PI;
            return weight;
        }
    }
    return Spectrum_Zero;
}

pdf_multi_scatter_dielectric :: (using info: Multi_Scatter_Dielectric_Shading_Info, wo: Vector3, wi: Vector3) -> float
{
    if has_visible_energy_loss(info)
    {
        if wi.z > 0.0
        {
            pdf := reflection_ratio * pdf_cosine(wi);
            return pdf;
        }
        else if wi.z < 0.0
        {
            pdf := (1.0 - reflection_ratio) * pdf_cosine(.{wi.x, wi.y, -wi.z});
            return pdf;
        }
    }
    return 0.0;
}

sample_multi_scatter_dielectric :: (using info: Multi_Scatter_Dielectric_Shading_Info, wo: Vector3, u: Vector3) -> Sample
{
    if has_visible_energy_loss(info)
    {
        wi := sample_cosine(u.x, u.y);
        if wi.z != 0.0
        {
            pdf := pdf_cosine(wi);
            if (u.z < reflection_ratio)
            {
                clamped_weight := calculate_multi_scatter_dielectric_energy(info, wi, false);
                weight         := reflect_scale * clamped_weight * wi.z * RCP_PI / pdf;
                return make_sample(weight, reflection_ratio * pdf, wi, .REFLECTION | .GLOSSY);
            }
            else
            {
                wi.z            = -wi.z;
                clamped_weight := calculate_multi_scatter_dielectric_energy(info, wi, false);
                weight         := transmit_scale * clamped_weight * (-wi.z) * RCP_PI / pdf;
                return make_sample(weight, (1.0 - reflection_ratio) * pdf, wi, .TRANSMISSION | .GLOSSY);
            }
        }
    }
    return make_zero_sample();
}

estimate_multi_scatter_dielectric :: (using info: Multi_Scatter_Dielectric_Shading_Info, wo: Vector3) -> float
{
    if has_visible_energy_loss(info)
    {
        weight   := reflect_scale * reflection_ratio + transmit_scale * (1.0 - reflection_ratio);
        estimate := max_spectrum(weight) * energy_complement_wo_dot_n;
        return estimate;
    }
    return 0.0;
}

#scope_file

calculate_multi_scatter_dielectric_energy :: (using info: Multi_Scatter_Dielectric_Shading_Info, wi: Vector3, $apply_ratio: bool) -> float
{
    // Based on: https://blog.selfshadow.com/publications/s2017-shading-course/imageworks/s2017_pbs_imageworks_slides_v2.pdf
    // ratio * (1 - E(wi)) * (1 - E(wo)) / (PI * (1 - E_avg))

    effective_ior, effective_ratio: float;
    wi_dot_n := wi.z;

    if wi_dot_n > 0.0
    {
        effective_ior   = eta_t_over_eta_i;
        effective_ratio = reflection_ratio;
    }
    else
    {
        wi_dot_n = -wi_dot_n;
        effective_ior   = 1.0 / eta_t_over_eta_i;
        effective_ratio = 1.0 - reflection_ratio;
    }

    energy_complement_wi_dot_n := read_dielectric_transparent_energy_complement(microfacet_alpha, wi_dot_n, effective_ior);
    average_energy_complement  := read_dielectric_transparent_average_energy_complement(microfacet_alpha, effective_ior);
    unscaled_weight            := energy_complement_wo_dot_n * energy_complement_wi_dot_n / max(average_energy_complement, 1.0e-6);

    #if apply_ratio
    {
        unscaled_weight *= effective_ratio;
    }

    clamped_weight := min(unscaled_weight, sdiv(1.0, wi_dot_n));
    return clamped_weight;
}

//------------------------------------------------------------------------
// Multi Scatter Metal BRDF

#scope_module

evaluate_multi_scatter_metal :: (using info: Multi_Scatter_Metal_Shading_Info, wo: Vector3, wi: Vector3) -> Spectrum
{
    if has_visible_energy_loss(info) && wi.z > 0.0
    {
        clamped_weight := calculate_multi_scatter_metal_energy(info, wi);
        weight         := scale * clamped_weight * wi.z * RCP_PI;
        return weight;
    }
    return Spectrum_Zero;
}

pdf_multi_scatter_metal :: (using info: Multi_Scatter_Metal_Shading_Info, wo: Vector3, wi: Vector3) -> float
{
    if has_visible_energy_loss(info)
    {
        pdf := pdf_cosine(wi);
        return pdf;
    }
    return 0.0;
}

sample_multi_scatter_metal :: (using info: Multi_Scatter_Metal_Shading_Info, wo: Vector3, u: Vector3) -> Sample
{
    if has_visible_energy_loss(info)
    {
        wi := sample_cosine(u.x, u.y);
        if (wi.z > 0.0)
        {
            pdf            := pdf_cosine(wi);
            clamped_weight := calculate_multi_scatter_metal_energy(info, wi);
            weight         := scale * clamped_weight * wi.z * RCP_PI / pdf;
            return make_sample(weight, pdf, wi, .REFLECTION | .GLOSSY);
        }
    }
    return make_zero_sample();
}

estimate_multi_scatter_metal :: (using info: Multi_Scatter_Metal_Shading_Info, wo: Vector3) -> float
{
    if has_visible_energy_loss(info)
    {
        estimate := max_spectrum(scale) * energy_complement_wo_dot_n;
        return estimate;
    }
    return 0.0;
}

#scope_file

calculate_multi_scatter_metal_energy :: (using info: Multi_Scatter_Metal_Shading_Info, wi: Vector3) -> float
{
    // Based on: https://blog.selfshadow.com/publications/s2017-shading-course/imageworks/s2017_pbs_imageworks_slides_v2.pdf
    // (1 - E(wi)) * (1 - E(wo)) / (PI * (1 - E_avg))
    energy_complement_wi_dot_n := read_metal_energy_complement(microfacet_alpha, wi.z);
    unscaled_weight            := energy_complement_wi_dot_n * energy_complement_wo_dot_n / max(average_energy_complement, 1.0e-6);
    // Prevent weights from getting out of control near grazing angles at low roughnesses
    clamped_weight             := min(unscaled_weight, sdiv(1.0, wi.z));
    return clamped_weight;
}

#scope_file

MIN_REASONABLE_IOR                     :: 1.001;
PASS_THROUGH_IOR_EPSILON               :: 1.0e-2;
MIN_ROUGHNESS_WITH_VISIBLE_ENERGY_LOSS :: 0.04; // From Adobe's OpenPBR BSDF
MIN_ALPHA_WITH_VISIBLE_ENERGY_LOSS     :: MIN_ROUGHNESS_WITH_VISIBLE_ENERGY_LOSS * MIN_ROUGHNESS_WITH_VISIBLE_ENERGY_LOSS;

has_visible_energy_loss :: (using info: Multi_Scatter_Dielectric_Shading_Info) -> bool
{
    pass_through := is_pass_through_medium(eta_t_over_eta_i);
    smooth       := is_smooth_surface(microfacet_alpha);
    energy_loss  := !(pass_through || smooth);
    return energy_loss;
}

has_visible_energy_loss :: (using info: Multi_Scatter_Metal_Shading_Info) -> bool
{
    metallic    := max_spectrum(scale) > 0.0;
    smooth      := is_smooth_surface(microfacet_alpha);
    energy_loss := metallic && !smooth;
    return energy_loss;
}

is_delta_surface :: (using info: Glossy_Specular_Shading_Info) -> bool
{
    smooth       := is_smooth_surface(max(microfacet_alpha.x, microfacet_alpha.y));
    pass_through := (metal_scale == 0.0 && is_pass_through_medium(eta_t_over_eta_i_transparent));
    delta        := smooth || pass_through;
    return delta;
}

is_smooth_surface :: (alpha: float) -> bool
{
    return alpha < MIN_ALPHA_WITH_VISIBLE_ENERGY_LOSS;
}

is_pass_through_medium :: (eta_t_over_eta_i: float) -> bool
{
    return abs(eta_t_over_eta_i - 1.0) <= PASS_THROUGH_IOR_EPSILON;
}

//------------------------------------------------------------------------

square :: inline (x: $T) -> T
{
    return x * x;
}

sdiv :: inline (x: $T, y: T) -> T
{
    if (y != 0)
    {
        return x/y;
    }
    return 0;
}

FLOAT32_EPSILON :: 0h34000000;
FLOAT32_ONE_MINUS_EPSILON :: 0h3F7FFFFF;

clamp_random_number :: inline (p: float) -> float
{
    return min(p, FLOAT32_ONE_MINUS_EPSILON);
}

#import "Math";
#import "Basic";
