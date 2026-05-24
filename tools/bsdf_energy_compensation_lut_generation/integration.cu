
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "helper_math.h"

#include <stdio.h>
#include <math.h>
#include <float.h>
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>

//------------------------------------------------------------------------
// Copy-pasted from PathNoise.jai

constexpr float SOBOL_INV_RESOLUTION = 0x1p-32f;
constexpr uint32_t SOBOL_MATRIX_DIMENSION = 4;
constexpr uint32_t SOBOL_MATRIX_SIZE = 32;

__device__ uint32_t SobolDirectionLUT[SOBOL_MATRIX_DIMENSION * SOBOL_MATRIX_SIZE] = {
    0x80000000, 0x40000000, 0x20000000, 0x10000000,
    0x08000000, 0x04000000, 0x02000000, 0x01000000,
    0x00800000, 0x00400000, 0x00200000, 0x00100000,
    0x00080000, 0x00040000, 0x00020000, 0x00010000,
    0x00008000, 0x00004000, 0x00002000, 0x00001000,
    0x00000800, 0x00000400, 0x00000200, 0x00000100,
    0x00000080, 0x00000040, 0x00000020, 0x00000010,
    0x00000008, 0x00000004, 0x00000002, 0x00000001,

    0x80000000, 0xc0000000, 0xa0000000, 0xf0000000,
    0x88000000, 0xcc000000, 0xaa000000, 0xff000000,
    0x80800000, 0xc0c00000, 0xa0a00000, 0xf0f00000,
    0x88880000, 0xcccc0000, 0xaaaa0000, 0xffff0000,
    0x80008000, 0xc000c000, 0xa000a000, 0xf000f000,
    0x88008800, 0xcc00cc00, 0xaa00aa00, 0xff00ff00,
    0x80808080, 0xc0c0c0c0, 0xa0a0a0a0, 0xf0f0f0f0,
    0x88888888, 0xcccccccc, 0xaaaaaaaa, 0xffffffff,

    0x80000000, 0xc0000000, 0x60000000, 0x90000000,
    0xe8000000, 0x5c000000, 0x8e000000, 0xc5000000,
    0x68800000, 0x9cc00000, 0xee600000, 0x55900000,
    0x80680000, 0xc09c0000, 0x60ee0000, 0x90550000,
    0xe8808000, 0x5cc0c000, 0x8e606000, 0xc5909000,
    0x6868e800, 0x9c9c5c00, 0xeeee8e00, 0x5555c500,
    0x8000e880, 0xc0005cc0, 0x60008e60, 0x9000c590,
    0xe8006868, 0x5c009c9c, 0x8e00eeee, 0xc5005555,

    0x80000000, 0xc0000000, 0x20000000, 0x50000000,
    0xf8000000, 0x74000000, 0xa2000000, 0x93000000,
    0xd8800000, 0x25400000, 0x59e00000, 0xe6d00000,
    0x78080000, 0xb40c0000, 0x82020000, 0xc3050000,
    0x208f8000, 0x51474000, 0xfbea2000, 0x75d93000,
    0xa0858800, 0x914e5400, 0xdbe79e00, 0x25db6d00,
    0x58800080, 0xe54000c0, 0x79e00020, 0xb6d00050,
    0x800800f8, 0xc00c0074, 0x200200a2, 0x50050093,
};

__device__ uint32_t sobol(uint32_t index, uint32_t dim)
{
    uint32_t v = 0;
    uint32_t i = dim * SOBOL_MATRIX_SIZE;
    while (index != 0)
    {
        if (index & 1)
        {
            v ^= SobolDirectionLUT[i];
        }
        i += 1;
        index >>= 1;
    }
    return v;
}

__device__ uint32_t murmur_finalize32(uint32_t x)
{
    x ^= x >> 16;
    x *= 0x85ebca6b;
    x ^= x >> 13;
    x *= 0xc2b2ae35;
    x ^= x >> 16;
    return x;
}

__device__ uint32_t hash_combine(uint32_t seed, uint32_t v)
{
    return seed ^ (v + (seed << 6) + (seed >> 2));
}

__device__ uint32_t reverse_bits(uint32_t x)
{
    x = (((x & 0xaaaaaaaa) >> 1) | ((x & 0x55555555) << 1));
    x = (((x & 0xcccccccc) >> 2) | ((x & 0x33333333) << 2));
    x = (((x & 0xf0f0f0f0) >> 4) | ((x & 0x0f0f0f0f) << 4));
    x = (((x & 0xff00ff00) >> 8) | ((x & 0x00ff00ff) << 8));
    return ((x >> 16) | (x << 16));
}

__device__ uint32_t fast_owen_scramble2(uint32_t v, uint32_t seed)
{
    v = reverse_bits(v);
    v ^= v * 0x3d20adea;
    v += seed;
    v *= (seed >> 16) | 1;
    v ^= v * 0x05526c56;
    v ^= v * 0x53a22864;
    return reverse_bits(v);
}

__device__ uint32_t scrambled_sobol(uint32_t index, uint32_t seed, uint32_t dim)
{
    index      = fast_owen_scramble2(index, seed ^ 0x79c68e4a);
    uint32_t v = sobol(index, dim);
    v          = fast_owen_scramble2(v, hash_combine(seed, dim));
    return v;
}

__device__ float sample_scrambled_sobol(uint32_t index, uint32_t seed, uint32_t dim)
{
    uint32_t v = scrambled_sobol(index, seed, dim);
    float    r = (float)v * SOBOL_INV_RESOLUTION;
    return r;
}

__device__ float clamp_random_number(float p)
{
    if (p < 1.0) return p;
    return 1.0 - FLT_EPSILON;
}

__device__ float4 sample_random_4D(uint32_t index, uint32_t seed)
{
    float  u1 = sample_scrambled_sobol(index, seed, 0);
    float  u2 = sample_scrambled_sobol(index, seed, 1);
    float  u3 = sample_scrambled_sobol(index, seed, 2);
    float  u4 = sample_scrambled_sobol(index, seed, 3);
    float4 u  = make_float4(clamp_random_number(u1), clamp_random_number(u2), clamp_random_number(u3), clamp_random_number(u4));
    return u;
}

//------------------------------------------------------------------------
// Copy-pasted from microfacet.jai

using Vector3  = float3;
using Vector2  = float2;
using Spectrum = float3;


__device__ uint32_t hash(int x, int y)
{
    uint32_t xh = murmur_finalize32((uint32_t)x);
    uint32_t yh = murmur_finalize32((uint32_t)y);
    return hash_combine(xh, yh);
}

template <typename T>
__device__ T max(T a, T b)
{
    return (a > b) ? a : b;
}

__device__ float max_spectrum(Spectrum s)
{
    return max(s.x, max(s.y, s.z));
}

constexpr float PI = 3.1415927f;

__device__ float microfacet_ggx_distribution(Vector3 wh, Vector2 alpha)
{
    Vector3 whs    = wh / Vector3{ alpha.x, alpha.y, 1.0 };
    float lensq    = dot(whs, whs); // length_squared
    float inv_dist = PI * alpha.x * alpha.y * lensq * lensq;
    float dist     = 1.0 / max(inv_dist, 1.0e-6f);
    return dist;
}

__device__ float microfacet_ggx_lambda(Vector3 w, Vector2 alpha)
{
    float alpha_x      = alpha.x * w.x;
    float alpha_y      = alpha.y * w.y;
    float cos_theta_sq = max(w.z * w.z, 1.0e-6f);
    float tan_alpha_sq = (alpha_x * alpha_x + alpha_y * alpha_y) / cos_theta_sq;
    float lambda       = 0.5f * (sqrt(1.0f + tan_alpha_sq) - 1.0f);
    return lambda;
}

__device__ float microfacet_ggx_mask(Vector3 w, Vector2 alpha)
{
    float lambda = microfacet_ggx_lambda(w, alpha);
    float mask   = 1.0 / (1.0 + lambda);
    return mask;
}

__device__ float microfacet_ggx_mask_shadow(Vector3 wo, Vector3 wi, Vector2 alpha)
{
    float lambda_wo   = microfacet_ggx_lambda(wo, alpha);
    float lambda_wi   = microfacet_ggx_lambda(wi, alpha);
    float mask_shadow = 1.0 / (1.0 + lambda_wo + lambda_wi);
    return mask_shadow;
}

// GGX VNDF importance sampling
// https://jcgt.org/published/0007/04/01/
__device__ Vector3 microfacet_ggx_sample_vndf(Vector3 wo, Vector2 alpha, float u1, float u2)
{
    Vector3 basis_n = normalize(Vector3{ alpha.x * wo.x, alpha.y * wo.y, wo.z });
    float lensq     = basis_n.x * basis_n.x + basis_n.y * basis_n.y;

    Vector3 basis_x = make_float3(1.0, 0.0, 0.0);

    if (lensq > 0.0)
    {
        float inv_len = 1.0 / sqrt(lensq);
        basis_x       = make_float3(-basis_n.y * inv_len, basis_n.x * inv_len, 0.0);
    }

    Vector3 basis_y = cross(basis_n, basis_x);

    float r   = sqrt(u1);
    float phi = 2.0 * PI * u2;
    float x   = r * cos(phi);
    float y   = r * sin(phi);
    float s   = 0.5 * (1.0 + basis_n.z);
    y         = (1.0 - s) * sqrt(1.0 - x * x) + s * y;

    Vector3 wh = x * basis_x + y * basis_y + sqrt(max(0.0, 1.0 - x * x - y * y)) * basis_n;
    wh.x *= alpha.x;
    wh.y *= alpha.y;
    wh.z = max(0.0, wh.z);
    wh   = normalize(wh);
    return wh;
}

__device__ bool is_microfacet_alpha_delta(Vector2 microfacet_alpha)
{
    bool delta = max(microfacet_alpha.x, microfacet_alpha.y) < 1.0e-3f;
    return delta;
}

__device__ bool refract(Vector3 I, Vector3 N, float eta_t_over_eta_i, Vector3* R)
{
    float eta_i_over_eta_t = 1.0 / eta_t_over_eta_i;
    float cos_i            = -dot(N, I);
    float sin2_t           = max(0.0, 1.0 - cos_i * cos_i) * eta_i_over_eta_t * eta_i_over_eta_t;
    if (sin2_t < 1.0)
    {
        float cos_t = sqrt(1.0 - sin2_t);
        *R          = normalize(I * eta_i_over_eta_t + (cos_i * eta_i_over_eta_t - cos_t) * N);
        return true;
    }
    return false;
}

__device__ float fresnel_dielectric_unpolarized(float eta_t_over_eta_i, float mu)
{
    if (eta_t_over_eta_i == 1.0)
        return 0.0;
    float u  = fabs(clamp(mu, -1.0, 1.0));
    float g2 = eta_t_over_eta_i * eta_t_over_eta_i + u * u - 1.0;
    if (g2 <= 0.0) return 1.0; // TIR
    float g  = sqrt(g2);
    float n1 = g - u;
    float d1 = g + u;
    float t1 = n1 / d1;
    float n2 = u * d1 - 1.0;
    float d2 = u * n1 + 1.0;
    if (d2 <= 0.0) return 1.0;
    float t2 = n2 / d2;
    float fresnel = 0.5 * t1 * t1 * (1.0 + t2 * t2);
    return fresnel;
}

__device__ Spectrum fresnel_dielectric(float eta_t_over_eta_i, float mu)
{
    float fresnel = fresnel_dielectric_unpolarized(eta_t_over_eta_i, mu);
    return make_float3(fresnel, fresnel, fresnel);
}

__device__ float fresnel_average_dielectric(float eta_t_over_eta_i)
{
    constexpr float MAX_REASONABLE_IOR = 400.0;
    constexpr float MIN_REASONABLE_IOR = 1.0 / MAX_REASONABLE_IOR;
    float n = clamp(eta_t_over_eta_i, MIN_REASONABLE_IOR, MAX_REASONABLE_IOR);
    if (n >= 1.0)
    {
        float num   = n - 1.0;
        float den   = 4.08567 + 1.00071 * n;
        float f_avg = num / den;
        return f_avg;
    }
    else
    {
        float n2    = n * n;
        float n3    = n2 * n;
        float f_avg = 0.997118 + 0.1014 * n - 0.965241 * n2 - 0.1306073 * n3;
        return f_avg;
    }
}

__device__ float ior_parametrization(float t)
{
    float p   = clamp(t, 0.0, 0.999999);
    float p2  = p * p;
    float ior = (1.0 + p2) / (1.0 - p2);
    return ior;
}

enum Glossy_Specular_Type
{
    GLOSSY_SPECULAR_METAL,
    GLOSSY_SPECULAR_DIELECTRIC_OPAQUE,
    GLOSSY_SPECULAR_DIELECTRIC_TRANSPARENT
};

struct Glossy_Specular_Shading_Info
{
    Glossy_Specular_Type type;
    Vector2              microfacet_alpha;
    float                eta_t_over_eta_i;
};

struct Glossy_Specular_Coefficient_Probability
{
    Spectrum reflect_coefficient;
    Spectrum transmit_coefficient;
    float    reflect_probability;
    float    transmit_probability;
    float    total_probability;
};

__device__ Glossy_Specular_Coefficient_Probability calculate_glossy_specular_coefficients_and_probabilities(const Glossy_Specular_Shading_Info& info, float wo_dot_wh)
{
    Glossy_Specular_Coefficient_Probability coeff;
    coeff.reflect_coefficient  = make_float3(1, 1, 1);
    coeff.transmit_coefficient = make_float3(0, 0, 0);
    coeff.reflect_probability  = 1.0;
    coeff.transmit_probability = 0.0;
    coeff.total_probability    = 1.0;

    if (info.type == GLOSSY_SPECULAR_DIELECTRIC_OPAQUE || info.type == GLOSSY_SPECULAR_DIELECTRIC_TRANSPARENT)
    {
        coeff.reflect_coefficient = fresnel_dielectric(info.eta_t_over_eta_i, wo_dot_wh);
        if (info.type == GLOSSY_SPECULAR_DIELECTRIC_TRANSPARENT)
        {
            coeff.transmit_coefficient = make_float3(1, 1, 1) - coeff.reflect_coefficient;
        }
        coeff.reflect_probability = max_spectrum(coeff.reflect_coefficient);
        coeff.transmit_probability = max_spectrum(coeff.transmit_coefficient);
        coeff.total_probability = coeff.reflect_probability + coeff.transmit_probability;
        if (coeff.total_probability > FLT_EPSILON)
        {
            coeff.reflect_probability /= coeff.total_probability;
            coeff.transmit_probability /= coeff.total_probability;
            coeff.total_probability = 1.0;
        }
        else
        {
            coeff.reflect_probability  = 0.0;
            coeff.transmit_probability = 0.0;
            coeff.total_probability    = 0.0;
        }
    }

    return coeff;
}

__device__ Spectrum sample_glossy_specular(const Glossy_Specular_Shading_Info& info, Vector3 wo, float p, Vector2 u)
{
    if (!is_microfacet_alpha_delta(info.microfacet_alpha))
    {
        Vector3 wh = microfacet_ggx_sample_vndf(wo, info.microfacet_alpha, u.x, u.y);
        float wo_dot_wh = dot(wo, wh);
        Glossy_Specular_Coefficient_Probability coefficients_and_probabilities = calculate_glossy_specular_coefficients_and_probabilities(info, wo_dot_wh);

        if (coefficients_and_probabilities.total_probability == 0.0)
            return make_float3(0, 0, 0);

        Spectrum reflect_coeff  = coefficients_and_probabilities.reflect_coefficient;
        Spectrum transmit_coeff = coefficients_and_probabilities.transmit_coefficient;
        float    reflect_prob   = coefficients_and_probabilities.reflect_probability;
        float    transmit_prob  = coefficients_and_probabilities.transmit_probability;

        if (p < reflect_prob)
        {
            Vector3 wi = normalize(reflect(-wo, wh));
            if (wi.z > 0.0)
            {
                float mask_shadow = microfacet_ggx_mask_shadow(wo, wi, info.microfacet_alpha);
                float mask        = microfacet_ggx_mask(wo, info.microfacet_alpha);
                float shadow      = mask_shadow / mask;
                Spectrum weight   = reflect_coeff * shadow / reflect_prob;
                return weight;
            }
        }
        else
        {
            Vector3 wi;
            bool refracted = refract(-wo, wh, info.eta_t_over_eta_i, &wi);
            if (refracted && wi.z < 0.0)
            {
                float mask_shadow = microfacet_ggx_mask_shadow(wo, wi, info.microfacet_alpha);
                float mask        = microfacet_ggx_mask(wo, info.microfacet_alpha);
                float shadow      = mask_shadow / mask;
                Spectrum weight   = transmit_coeff * shadow / transmit_prob;
                return weight;
            }
        }
    }
    else
    {
        Vector3 wh = make_float3(0, 0, 1);
        float wo_dot_wh = dot(wo, wh);
        Glossy_Specular_Coefficient_Probability coefficients_and_probabilities = calculate_glossy_specular_coefficients_and_probabilities(info, wo_dot_wh);

        if (coefficients_and_probabilities.total_probability == 0.0)
            return make_float3(0, 0, 0);

        Spectrum reflect_coeff  = coefficients_and_probabilities.reflect_coefficient;
        Spectrum transmit_coeff = coefficients_and_probabilities.transmit_coefficient;
        float    reflect_prob   = coefficients_and_probabilities.reflect_probability;
        float    transmit_prob  = coefficients_and_probabilities.transmit_probability;

        if (p < reflect_prob)
        {
            Vector3 wi = normalize(reflect(-wo, wh));
            if (wi.z > 0.0)
            {
                Spectrum weight = reflect_coeff / reflect_prob;
                return weight;
            }
        }
        else
        {
            Vector3 wi;
            bool refracted = refract(-wo, wh, info.eta_t_over_eta_i, &wi);
            if (refracted && wi.z < 0.0)
            {
                Spectrum weight = transmit_coeff / transmit_prob;
                return weight;
            }
        }
    }

    return make_float3(0, 0, 0);
}

__device__ Glossy_Specular_Shading_Info make_glossy_specular(Glossy_Specular_Type type, Vector2 alpha, float eta_t_over_eta_i)
{
    Glossy_Specular_Shading_Info info = {};
    info.type             = type;
    info.microfacet_alpha = alpha;
    info.eta_t_over_eta_i = eta_t_over_eta_i;
    return info;
}

enum Integrate_Method
{
    INTEGRATE_DIRECTIONAL_ALBEDO,
    INTEGRATE_HEMISPHERICAL_ALBEDO,
};

extern "C" __global__ void integrate_glossy_specular(float *dst, int32_t n_x, int32_t n_y, int32_t n_z, int64_t n_samples, Glossy_Specular_Type type, Integrate_Method method)
{
    int x = threadIdx.x + blockIdx.x * blockDim.x;
    int y = threadIdx.y + blockIdx.y * blockDim.y;
    int z = threadIdx.z + blockIdx.z * blockDim.z;

    int32_t  half_z = n_z / 2;
    uint32_t seed   = hash(x, y);

    float alpha     = (n_x > 1) ? ((float)x / (float)(n_x - 1)) : 0.0f;
    float cosine    = (n_y > 1) ? ((float)y / (float)(n_y - 1)) : 0.0f;
    float ior_param = 0.0;

    double sum = 0.0;

    for (int64_t sample = 0; sample < n_samples; ++sample)
    {
        float4 random = sample_random_4D(static_cast<uint32_t>(sample), seed);

        if (method == INTEGRATE_HEMISPHERICAL_ALBEDO)
        {
            cosine = random.z;
        }

        if (n_z > 1)
        {
            if (z < half_z)
            {
                // Mirror the first half to make the sequence (1/ior,1.0) and (1.0,ior)
                ior_param = (float)z / (float)(half_z - 1);
                ior_param = 1.0 - ior_param;
            }
            else
            {
                ior_param = (float)(z - half_z) / (float)(half_z - 1);
            }
        }

        constexpr float MIN_ROUGHNESS = 1.0e-4;

        alpha          = clamp(alpha, MIN_ROUGHNESS * MIN_ROUGHNESS, 1.0f);
        cosine         = clamp(cosine, 1.0e-4, 1.0f);
        ior_param      = clamp(ior_param, 1.0e-4, 0.999999f);

        float ior      = ior_parametrization(ior_param);
        float p        = random.w;

        float   sine   = sqrt(1.0 - cosine * cosine);
        Vector3 wo     = make_float3(sine, 0.0, cosine);

        if (z < half_z)
        {
            ior   = 1.0 / ior;
        }

        Glossy_Specular_Shading_Info info = make_glossy_specular(type, make_float2(alpha, alpha), ior);
        Vector3 weight                    = sample_glossy_specular(info, wo, p, make_float2(random.x, random.y));
        float   albedo                    = (weight.x + weight.y + weight.z) / 3.0f;

        if (method == INTEGRATE_HEMISPHERICAL_ALBEDO)
        {
            albedo *= 2 * cosine;
        }

        sum += (double)albedo;
    }

    double avg   = min(sum / (double)n_samples, 1.0);
    int    index = z * n_x * n_y + y * n_x + x;
    dst[index]   = avg;
}

extern "C" __global__ void calculate_dielectric_reflection_ratio(float *dst, int32_t n_x, int32_t n_y, int32_t n_z, float *avg_energy_lut)
{
    int x = threadIdx.x + blockIdx.x * blockDim.x;
    int y = threadIdx.y + blockIdx.y * blockDim.y;
    int z = threadIdx.z + blockIdx.z * blockDim.z;

    int32_t  half_z           = n_z / 2;
    int32_t  z_t_over_i       = z;
    int32_t  z_i_over_t       = n_z - 1 - z_t_over_i;
    float    eta_t_over_eta_i = 0.0;

    if (z < half_z)
    {
        // Mirror the first half to make the sequence (1/ior,1.0) and (1.0,ior)
        float ior_param  = (float)z / (float)(half_z - 1);
        ior_param        = 1.0 - ior_param;
        ior_param        = clamp(ior_param, 1.0e-4, 0.999999f);
        eta_t_over_eta_i = 1.0 / ior_parametrization(ior_param);
    }
    else
    {
        float ior_param  = (float)(z - half_z) / (float)(half_z - 1);
        ior_param        = clamp(ior_param, 1.0e-4, 0.999999f);
        eta_t_over_eta_i = ior_parametrization(ior_param);
    }

    float eta_i_over_eta_t       = 1.0 / eta_t_over_eta_i;
    float f_avg_eta_t_over_eta_i = fresnel_average_dielectric(eta_t_over_eta_i);
    float f_avg_eta_i_over_eta_t = fresnel_average_dielectric(eta_i_over_eta_t);
    int   e_index_t_over_i       = z_t_over_i * n_x * n_y + y * n_x + x;
    int   e_index_i_over_t       = z_i_over_t * n_x * n_y + y * n_x + x;
    float e_avg_eta_t_over_eta_i = avg_energy_lut[e_index_t_over_i];
    float e_avg_eta_i_over_eta_t = avg_energy_lut[e_index_i_over_t];
    float factor_1               = (1.0 - f_avg_eta_t_over_eta_i) / max(1.0 - e_avg_eta_i_over_eta_t, 1.0e-12);
    float factor_2               = eta_t_over_eta_i * eta_t_over_eta_i * (1.0 - f_avg_eta_i_over_eta_t) / max(1.0 - e_avg_eta_t_over_eta_i, 1.0e-12);
    float num                    = factor_2;
    float den                    = factor_1 + factor_2;
    float ratio                  = f_avg_eta_t_over_eta_i * num / den;

    int    index = z * n_x * n_y + y * n_x + x;
    dst[index]   = ratio;
}
