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
	float3 norm : NORMAL;
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

	vin.PosL.y = finalFbm(float2(vin.PosL.x, vin.PosL.z) / 10) * 20;

	float l = finalFbm(float2(vin.PosL.x + 1, vin.PosL.z) / 10) * 20;
	float r = finalFbm(float2(vin.PosL.x , vin.PosL.z + 1) / 10) * 20;

	float3 lvec = { vin.PosL.x + 1,l,vin.PosL.z };
	float3 rvec = { vin.PosL.x,r,vin.PosL.z + 1 };


	vout.PosL = vin.PosL;
	vout.norm = -normalize(cross(lvec - vin.PosL, rvec - vin.PosL));

	return vout;
}


struct PatchTess {
	float EdgeTess[3] : SV_TessFactor;
	float InsideTess[1] : SV_InsideTessFactor;
};

PatchTess ConstantHS(InputPatch<VertexOut, 3> patch, uint patchID: SV_PrimitiveID)
{
	PatchTess pt;

	int tessout = 8;

	int tessin = 8;

	pt.EdgeTess[0] = tessout;
	pt.EdgeTess[1] = tessout;
	pt.EdgeTess[2] = tessout;

	pt.InsideTess[0] = tessin;

	return pt;

}

struct HullOut {
	float3 PosL:POSITION;
	float3 norm : NORMAL;
};

[domain("tri")]
[partitioning("integer")]
[outputtopology("triangle_cw")]
[outputcontrolpoints(3)]
[patchconstantfunc("ConstantHS")]
[maxtessfactor(64.0f)]
HullOut HS(InputPatch<VertexOut, 3> p,
	uint i: SV_outputControlPointID,
	uint patchId : SV_PrimitiveID)
{
	HullOut hout;
	hout.PosL = p[i].PosL;
	hout.norm = p[i].norm;
	return hout;
}

struct DomainOut {
	float4 PosH : SV_POSITION;
	float3 norm : NORMAL;
};

[domain("tri")]
DomainOut DS(PatchTess patchTess,
	float3 uvw : SV_DomainLocation,
	const OutputPatch<HullOut, 3> tri)
{
	DomainOut dout;
	// barycentric interpolation
	float3 newcoord = tri[0].PosL*uvw.x + tri[1].PosL*uvw.y + tri[2].PosL*uvw.z;

	float3 norm = tri[0].norm*uvw.x + tri[1].norm*uvw.y + tri[2].norm*uvw.z;
	
	float4 posW = mul(float4(newcoord, 1.0f), gWorld);
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


