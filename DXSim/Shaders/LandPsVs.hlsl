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
RWTexture2D<float4> noiseMap : register(u2);

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
	float3 boxcenter;
	float boxL;
	float3 sunDir;

	float marchStep;
	float maximumStepSize;
	float stepMultiplier;
	float densityFilter;
	float shadowDivider;
	float shadowMacherDis;
	int tesselationCount;
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

};

struct VertexOut
{
	float3 PosL   : POSITION;
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

	//float h = finalFbm(float2(posW.x, posW.z) / 10) * 10;

	vin.PosL.y = 0;

	vout.PosL = vin.PosL;


	return vout;
}


struct PatchTess {
	float EdgeTess[4] : SV_TessFactor;
	float InsideTess[2] : SV_InsideTessFactor;
};

PatchTess ConstantHS(InputPatch<VertexOut, 4> patch, uint patchID: SV_PrimitiveID)
{
	PatchTess pt;

	int tessout = tesselationCount;

	int tessin = tesselationCount;

	pt.EdgeTess[0] = tessout;
	pt.EdgeTess[1] = tessout;
	pt.EdgeTess[2] = tessout;
	pt.EdgeTess[3] = tessout;

	pt.InsideTess[0] = tessin;
	pt.InsideTess[1] = tessin;

	return pt;

}

struct HullOut {
	float3 PosL:POSITION;
};

[domain("quad")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(4)]
[patchconstantfunc("ConstantHS")]
[maxtessfactor(64.0f)]
HullOut HS(InputPatch<VertexOut, 4> p,
	uint i: SV_outputControlPointID,
	uint patchId : SV_PrimitiveID)
{
	HullOut hout;
	hout.PosL = p[i].PosL;
	return hout;
}

struct DomainOut {
	float4 PosH : SV_POSITION;
	float3 norm : NORMAL;
};

[domain("quad")]
DomainOut DS(PatchTess patchTess,
	float2 uv : SV_DomainLocation,
	const OutputPatch<HullOut, 4> quad)
{
	DomainOut dout;
	// barycentric interpolation
	float3 v1 = lerp(quad[0].PosL, quad[1].PosL, uv.x);
	float3 v2 = lerp(quad[2].PosL, quad[3].PosL, uv.x);
	float3 p = lerp(v1, v2, uv.y);

	p.y = finalFbm(float2(p.x, p.z) / 10) * 20;

	float l = finalFbm(float2(p.x + 1, p.z) / 10) * 20;
	float r = finalFbm(float2(p.x, p.z + 1) / 10) * 20;

	float3 norm = normalize(cross( p - float3(p.x, r, p.z+1),p - float3(p.x+1, l, p.z)));
	
	float4 posW = mul(float4(p, 1.0f), gWorld);
	norm = mul(norm, (float3x3)gWorld);
	dout.PosH = mul(posW, gViewProj);
	dout.norm = norm;
	return dout;

}


float4 PS(DomainOut pin) : SV_Target
{
	


	//test for noise
	//float mg = noiseMap[(int2(pin.PosW.x*4, pin.PosW.z*4)+int2(320, 320))*1.].x;

	//mg = 1 - mg;

	//litColor = float4(mg, mg, mg, 1);
	//test for noise

	//return litColor;
	float4 litColor={pin.norm.x,pin.norm.y,pin.norm.z,1.f};
	return litColor;
}


