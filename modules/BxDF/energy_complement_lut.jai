
read_metal_average_energy_complement :: (alpha: float) -> float
{
    alpha_index           := calculate_alpha_index(alpha);
    avg_energy_complement := read_table_1D(.METAL_AVERAGE, alpha_index);
    return avg_energy_complement;
}

read_metal_energy_complement :: (alpha: float, cosine: float) -> float
{
    alpha_index       := calculate_alpha_index(alpha);
    cosine_index      := calculate_cosine_index(cosine);
    energy_complement := read_table_2D(.METAL, alpha_index, cosine_index);
    return energy_complement;
}

read_dielectric_opaque_average_energy_complement :: (alpha: float, eta_t_over_eta_i: float) -> float
{
    alpha_index           := calculate_alpha_index(alpha);
    ior_index             := calculate_ior_index(eta_t_over_eta_i);
    avg_energy_complement := read_table_2D(.DIELECTRIC_OPAQUE_AVERAGE, alpha_index, ior_index);
    return avg_energy_complement;
}

read_dielectric_opaque_energy_complement :: (alpha: float, cosine: float, eta_t_over_eta_i: float) -> float
{
    alpha_index       := calculate_alpha_index(alpha);
    cosine_index      := calculate_cosine_index(cosine);
    ior_index         := calculate_ior_index(eta_t_over_eta_i);
    energy_complement := read_table_3D(.DIELECTRIC_OPAQUE, alpha_index, cosine_index, ior_index);
    return energy_complement;
}

read_dielectric_transparent_average_energy_complement :: (alpha: float, eta_t_over_eta_i: float) -> float
{
    alpha_index           := calculate_alpha_index(alpha);
    ior_index             := calculate_ior_index(eta_t_over_eta_i);
    avg_energy_complement := read_table_2D(.DIELECTRIC_TRANSPARENT_AVERAGE, alpha_index, ior_index);
    return avg_energy_complement;
}

read_dielectric_transparent_energy_complement :: (alpha: float, cosine: float, eta_t_over_eta_i: float) -> float
{
    alpha_index       := calculate_alpha_index(alpha);
    cosine_index      := calculate_cosine_index(cosine);
    ior_index         := calculate_ior_index(eta_t_over_eta_i);
    energy_complement := read_table_3D(.DIELECTRIC_TRANSPARENT, alpha_index, cosine_index, ior_index);
    return energy_complement;
}

read_dielectric_reflection_ratio :: (alpha: float, eta_t_over_eta_i: float) -> float
{
    alpha_index := calculate_alpha_index(alpha);
    ior_index   := calculate_ior_index(eta_t_over_eta_i);
    ratio       := read_table_2D(.DIELECTRIC_REFLECTION_RATIO, alpha_index, ior_index);
    return ratio;
}

#scope_file

calculate_alpha_index :: inline (alpha: float) -> float
{
    index := alpha * (LUT_SIZE - 1).(float);
    return index;
}

calculate_cosine_index :: inline (cosine: float) -> float
{
    index := cosine * (LUT_SIZE - 1).(float);
    return index;
}

calculate_ior_index :: inline (eta_t_over_eta_i: float) -> float
{
    if (eta_t_over_eta_i < 1.0)
    {
        eta_i_over_eta_t := 1.0 / eta_t_over_eta_i;
        param            := ior_inverse_parametrization(eta_i_over_eta_t);
        index            := (LUT_HALF_SIZE - 1).(float) - param * (LUT_HALF_SIZE - 1).(float);
        return index;
    }
    else
    {
        param := ior_inverse_parametrization(eta_t_over_eta_i);
        index := LUT_HALF_SIZE.(float) + param * (LUT_HALF_SIZE - 1).(float);
        return index;
    }
}

Energy_Complement_LUT :: enum u32
{
    METAL;
    METAL_AVERAGE;
    DIELECTRIC_OPAQUE;
    DIELECTRIC_OPAQUE_AVERAGE;
    DIELECTRIC_TRANSPARENT;
    DIELECTRIC_TRANSPARENT_AVERAGE;
    DIELECTRIC_REFLECTION_RATIO;
}

#assert LUT_SIZE % 2 == 0;

LUT_HALF_SIZE  :: LUT_SIZE / 2;
LUT_SLICE      :: LUT_SIZE * LUT_SIZE;

read_lut :: ($lut: Energy_Complement_LUT, index: s32) -> float
{
    quantized : u16 = 0;
    #if #complete lut ==
    {
        case .METAL;                           quantized = METAL_ENERGY_COMPLEMENT_LUT[index];
        case .METAL_AVERAGE;                   quantized = METAL_AVG_ENERGY_COMPLEMENT_LUT[index];
        case .DIELECTRIC_OPAQUE;               quantized = DIELECTRIC_OPAQUE_ENERGY_COMPLEMENT_LUT[index];
        case .DIELECTRIC_OPAQUE_AVERAGE;       quantized = DIELECTRIC_OPAQUE_AVG_ENERGY_COMPLEMENT_LUT[index];
        case .DIELECTRIC_TRANSPARENT;          quantized = DIELECTRIC_TRANSPARENT_ENERGY_COMPLEMENT_LUT[index];
        case .DIELECTRIC_TRANSPARENT_AVERAGE;  quantized = DIELECTRIC_TRANSPARENT_AVG_ENERGY_COMPLEMENT_LUT[index];
        case .DIELECTRIC_REFLECTION_RATIO;     quantized = DIELECTRIC_REFLECTION_RATIO_LUT[index];
    }

    INVERSE_U16 :: 1.0 / U16_MAX.(float);
    r := quantized.(float) * INVERSE_U16;
    return r;
}

flatten_index :: inline (x: s32, y: s32) -> s32
{
    index := y * LUT_SIZE + x;
    return index;
}

flatten_index :: inline (x: s32, y: s32, z: s32) -> s32
{
    index := z * LUT_SLICE + y * LUT_SIZE + x;
    return index;
}

mix :: inline (x: float, y: float, t: float) -> float
{
    return x * (1.0 - t) + y * t;
}

sampler_1D :: inline (u: float) -> s32, s32, float
{
    i0 := u.(s32);
    i1 := min(i0 + 1, LUT_SIZE - 1);
    uf := u - i0.(float);
    return i0, i1, uf;
}

read_table_1D :: ($lut: Energy_Complement_LUT, x_index: float) -> float
{
    x_quant_0, x_quant_1, x_frac := sampler_1D(x_index);

    v0 := read_lut(lut, x_quant_0);
    v1 := read_lut(lut, x_quant_1);

    v  := mix(v0, v1, x_frac);

    return v;
}

read_table_2D :: ($lut: Energy_Complement_LUT, x_index: float, y_index: float) -> float
{
    x_quant_0, x_quant_1, x_frac := sampler_1D(x_index);
    y_quant_0, y_quant_1, y_frac := sampler_1D(y_index);

    v00 := read_lut(lut, flatten_index(x_quant_0, y_quant_0));
    v01 := read_lut(lut, flatten_index(x_quant_0, y_quant_1));
    v10 := read_lut(lut, flatten_index(x_quant_1, y_quant_0));
    v11 := read_lut(lut, flatten_index(x_quant_1, y_quant_1));

    v0  := mix(v00, v10, x_frac);
    v1  := mix(v01, v11, x_frac);
    v   := mix(v0, v1, y_frac);

    return v;
}

read_table_3D :: ($lut: Energy_Complement_LUT, x_index: float, y_index: float, z_index: float) -> float
{
    x_quant_0, x_quant_1, x_frac := sampler_1D(x_index);
    y_quant_0, y_quant_1, y_frac := sampler_1D(y_index);
    z_quant_0, z_quant_1, z_frac := sampler_1D(z_index);

    v000 := read_lut(lut, flatten_index(x_quant_0, y_quant_0, z_quant_0));
    v001 := read_lut(lut, flatten_index(x_quant_0, y_quant_0, z_quant_1));
    v010 := read_lut(lut, flatten_index(x_quant_0, y_quant_1, z_quant_0));
    v011 := read_lut(lut, flatten_index(x_quant_0, y_quant_1, z_quant_1));
    v100 := read_lut(lut, flatten_index(x_quant_1, y_quant_0, z_quant_0));
    v101 := read_lut(lut, flatten_index(x_quant_1, y_quant_0, z_quant_1));
    v110 := read_lut(lut, flatten_index(x_quant_1, y_quant_1, z_quant_0));
    v111 := read_lut(lut, flatten_index(x_quant_1, y_quant_1, z_quant_1));

    v00  := mix(v000, v100, x_frac);
    v01  := mix(v001, v101, x_frac);
    v10  := mix(v010, v110, x_frac);
    v11  := mix(v011, v111, x_frac);
    v0   := mix(v00, v10, y_frac);
    v1   := mix(v01, v11, y_frac);
    v    := mix(v0, v1, z_frac);

    return v;
}


#load "bsdf_energy_compensation_quantized_lut.jai";
