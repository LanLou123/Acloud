//***************************************************************************************
// Default.hlsl by Frank Luna (C) 2015 All Rights Reserved.
//
// Default shader, currently supports lighting.
//***************************************************************************************

// Defaults for number of lights.
#ifndef NUM_DIR_LIGHTS
#define NUM_DIR_LIGHTS 3
#endif

#ifndef NUM_POINT_LIGHTS
#define NUM_POINT_LIGHTS 0
#endif

#ifndef NUM_SPOT_LIGHTS
#define NUM_SPOT_LIGHTS 0
#endif

#define NUM_OCTAVES 5

// Include structures and functions for lighting.
#include "LightingUtil.hlsl"

Texture2D    gDiffuseMap : register(t0);
Texture2D    gDisplacementMap : register(t1);

SamplerState gsamPointWrap        : register(s0);
SamplerState gsamPointClamp       : register(s1);
SamplerState gsamLinearWrap       : register(s2);
SamplerState gsamLinearClamp      : register(s3);
SamplerState gsamAnisotropicWrap  : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);

// Constant data that varies per frame.
cbuffer cbPerObject : register(b0)
{
	float4x4 gWorld;
	float4x4 gTexTransform;
	float2 gDisplacementMapTexelSize;
	float gGridSpatialStep;
	float cbPerObjectPad1;
};

// Constant data that varies per material.
cbuffer cbPass : register(b1)
{
	float4x4 gView;
	float4x4 gInvView;
	float4x4 gProj;
	float4x4 gInvProj;
	float4x4 gViewProj;
	float4x4 gInvViewProj;
	float3 gEyePosW;
	float cbPerPassPad1;
	float2 gRenderTargetSize;
	float2 gInvRenderTargetSize;
	float gNearZ;
	float gFarZ;
	float gTotalTime;
	float gDeltaTime;
	float4 gAmbientLight;

	float4 gFogColor;
	float gFogStart;
	float gFogRange;
	float2 cbPerPassPad2;

	// Indices [0, NUM_DIR_LIGHTS) are directional lights;
	// indices [NUM_DIR_LIGHTS, NUM_DIR_LIGHTS+NUM_POINT_LIGHTS) are point lights;
	// indices [NUM_DIR_LIGHTS+NUM_POINT_LIGHTS, NUM_DIR_LIGHTS+NUM_POINT_LIGHT+NUM_SPOT_LIGHTS)
	// are spot lights for a maximum of MaxLights per object.
	Light gLights[MaxLights];
};

cbuffer cbMaterial : register(b2)
{
	float4   gDiffuseAlbedo;
	float3   gFresnelR0;
	float    gRoughness;
	float4x4 gMatTransform;
};

struct VertexIn
{
	float3 PosL    : POSITION;
	float3 NormalL : NORMAL;
	float2 TexC    : TEXCOORD;
};

struct VertexOut
{
	float4 PosH    : SV_POSITION;
	float3 PosW    : POSITION;
	float3 NormalW : NORMAL;
	float2 TexC    : TEXCOORD;
};

//******************************
//3d fbm noise
//******************************

float mod289(float x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 perm(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }

float noise(float3 p) {
	float3 a = floor(p);
	float3 d = p - a;
	d = d * d * (3.0 - 2.0 * d);

	float4 b = a.xxyy + float4(0.0, 1.0, 0.0, 1.0);
	float4 k1 = perm(b.xyxy);
	float4 k2 = perm(k1.xyxy + b.zzww);

	float4 c = k2 + a.zzzz;
	float4 k3 = perm(c);
	float4 k4 = perm(c + 1.0);

	float4 o1 = frac(k3 * (1.0 / 41.0));
	float4 o2 = frac(k4 * (1.0 / 41.0));

	float4 o3 = o2 * d.z + o1 * (1.0 - d.z);
	float2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);

	return o4.y * d.y + o4.x * (1.0 - d.y);
}

float fbm3d(float3 x) {
	float v = 0.0;
	float a = 0.5;
	float3 shift = float3(100,100,100);
	for (int i = 0; i < NUM_OCTAVES; ++i) {
		v += a * noise(x);
		x = x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}
//******************************
//3d fbm noise
//******************************

//******************************
//2d fbm noise
//******************************
float random1(float2 _st)
{
	return frac(sin(dot(_st.xy, float2(12.9898, 78.233)))* 43758.5453123);
}

float noise(float2 _st) {
	float2 i = floor(_st);
	float2 f = frac(_st);

	float a = random1(i);
	float b = random1(i + float2(1.0, 0.0));
	float c = random1(i + float2(0.0, 1.0));
	float d = random1(i + float2(1.0, 1.0));

	float2 u = f * f*(3.0 - 2.0*f);

	return lerp(a, b, u.x) + (c - a)*u.y*(1.0 - u.x) + (d - b)*u.x*u.y;
}


float fbm(float2 _st) {
	float v = 0.0;
	float a = 0.5;
	float2 shift = float2(100.0,100.0);
	float2x2 rot = float2x2(cos(0.5), sin(0.5),
		-sin(0.5), cos(0.50));
	for (int i = 0; i < NUM_OCTAVES; ++i)
	{
		v += a * noise(_st);
		_st = mul(rot, _st)*2.0 + shift;
		a *= 0.5;
	}
	return v;
}

float finalFbm(float2 _st)
{
	

	float2 q = float2(0, 0);

	q.x = fbm(_st + 0.0*gTotalTime);
	q.y = fbm(_st + float2(1, 1));

	float2 r = float2(0, 0);
	r.x = fbm(_st + 1.0*q + float2(1.7, 9.2) + 0.15*gTotalTime);
	r.y = fbm(_st + 1.0*q + float2(8.3, 2.8) + 0.126*gTotalTime);

	return fbm(_st + r);
}
//******************************
//2d fbm noise
//******************************


VertexOut VS(VertexIn vin)
{
	VertexOut vout = (VertexOut)0.0f;

	// Transform to world space.
	vin.PosL.y = 0;

	float4 posW = mul(float4(vin.PosL, 1.0f), gWorld);
	

	float h = finalFbm(float2(posW.x, posW.z)/10);

	posW.y = 10*h;

	vout.PosW = posW.xyz;
	// Assumes nonuniform scaling; otherwise, need to use inverse-transpose of world matrix.
	vout.NormalW = mul(vin.NormalL, (float3x3)gWorld);

	// Transform to homogeneous clip space.
	vout.PosH = mul(posW, gViewProj);

	// Output vertex attributes for interpolation across triangle.
	float4 texC = mul(float4(vin.TexC, 0.0f, 1.0f), gTexTransform);
	vout.TexC = mul(texC, gMatTransform).xy;

	return vout;
}

float4 PS(VertexOut pin) : SV_Target
{
	float4 diffuseAlbedo = gDiffuseMap.Sample(gsamAnisotropicWrap, pin.TexC) * gDiffuseAlbedo;

#ifdef ALPHA_TEST
	// Discard pixel if texture alpha < 0.1.  We do this test as soon 
	// as possible in the shader so that we can potentially exit the
	// shader early, thereby skipping the rest of the shader code.
	clip(diffuseAlbedo.a - 0.1f);
#endif

	// Interpolating normal can unnormalize it, so renormalize it.
	pin.NormalW = normalize(pin.NormalW);

	// Vector from point being lit to eye. 
	float3 toEyeW = gEyePosW - pin.PosW;
	float distToEye = length(toEyeW);
	toEyeW /= distToEye; // normalize

	// Light terms.
	float4 ambient = gAmbientLight * diffuseAlbedo;

	const float shininess = 1.0f - gRoughness;
	Material mat = { diffuseAlbedo, gFresnelR0, shininess };
	float3 shadowFactor = 1.0f;
	float4 directLight = ComputeLighting(gLights, mat, pin.PosW,
		pin.NormalW, toEyeW, shadowFactor);

	float4 litColor = ambient + directLight;

#ifdef FOG
	float fogAmount = saturate((distToEye - gFogStart) / gFogRange);
	litColor = lerp(litColor, gFogColor, fogAmount);
#endif
	//fbm part

	float2 st = float2(pin.PosW.x, pin.PosW.z) / 10;
	float f = finalFbm(st);
	//fbm part

	litColor = float4(f, f, f, 1);
	// Common convention to take alpha from diffuse albedo.
	litColor.a = 1/(pin.PosW.y/5);

	//return litColor;
	return litColor;
}


