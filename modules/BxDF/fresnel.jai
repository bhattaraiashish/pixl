#scope_export

// Artist Friendly - Schlick inspired
// Based on: https://blog.selfshadow.com/publications/s2017-shading-course/imageworks/s2017_pbs_imageworks_slides_v2.pdf

fresnel_metal :: (reflectance: Spectrum, edge_tint: Spectrum, falloff: Spectrum, wo_dot_wh: float) -> Spectrum
{
    t   := 1.0 - wo_dot_wh;
    x   := pow(t, 1.0 / max(falloff.x, 1.0e-6));
    y   := pow(t, 1.0 / max(falloff.y, 1.0e-6));
    z   := pow(t, 1.0 / max(falloff.z, 1.0e-6));
    f   := reflectance + (edge_tint - reflectance) * Spectrum.{x, y, z};
    return f;
}

fresnel_average_metal :: (reflectance: Spectrum, edge_tint: Spectrum, falloff: Spectrum) -> Spectrum
{
    psq2  := 2 * falloff * falloff;
    p3    := 3 * falloff;
    num   := edge_tint * psq2 + reflectance + p3 * reflectance;
    den   := Spectrum_One + p3 + psq2;
    f_avg := num / den;
    return f_avg;
}

fresnel_dielectric_unpolarized :: (eta_t_over_eta_i: float, mu: float) -> float
{
    if (eta_t_over_eta_i == 1.0)
        return 0.0;
    u  := abs(clamp(mu, -1.0, 1.0));
    g2 := eta_t_over_eta_i * eta_t_over_eta_i + u * u - 1.0;
    if g2 <= 0.0 return 1.0; // TIR
    g  := sqrt(g2);
    n1 := g - u;
    d1 := g + u;
    t1 := n1 / d1;
    n2 := u * d1 - 1.0;
    d2 := u * n1 + 1.0;
    if d2 <= 0.0 return 1.0;
    t2 := n2 / d2;
    fresnel := 0.5 * t1 * t1 * (1.0 + t2 * t2);
    return fresnel;
}

fresnel_dielectric :: (eta_t_over_eta_i: float, mu: float) -> Spectrum
{
    fresnel := fresnel_dielectric_unpolarized(eta_t_over_eta_i, mu);
    return make_spectrum(fresnel);
}

ior_inverse_parametrization :: (ior: float) -> float
{
    assert(ior >= 1.0);
    t := sqrt((ior - 1.0) / (ior + 1.0));
    return t;
}

ior_parametrization :: (t: float) -> float
{
    p   := clamp(t, 0.0, 0.999999);
    p2  := p * p;
    ior := (1.0 + p2) / (1.0 - p2);
    return ior;
}
