

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
#define DIS_MAX 1e5
#define DIS_MIN -1e5
#define EPSILON 0.00001f
#define FLT_EPSILON     1.192092896e-07 

// Include structures and functions for lighting.
#include "LightingUtil.hlsl"
#include "inc.hlsli"

Texture2D    gDiffuseMap : register(t0);


SamplerState gsamPointWrap        : register(s0);
SamplerState gsamPointClamp       : register(s1);
SamplerState gsamLinearWrap       : register(s2);
SamplerState gsamLinearClamp      : register(s3);
SamplerState gsamAnisotropicWrap  : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);

// Constant data that floaties per frame.
cbuffer cbPerObject : register(b0)
{
	float4x4 gWorld;
	float4x4 gTexTransform;
	float2 gDisplacementMapTexelSize;
	float gGridSpatialStep;
	float cbPerObjectPad1;
};

// Constant data that floaties per material.
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





//perlin noise
float hash(float n)
{
	return frac(sin(n)*43758.5453);
}

float noisep(float3 x)
{
	// The noise function returns a value in the range -1.0f -> 1.0f

	x.x = x.x + 0.012*gTotalTime;
	x.y = x.y + 0.034*gTotalTime;
	x.z = x.z + 0.027*gTotalTime;

	float3 p = floor(x);
	float3 f = frac(x);

	f = f * f*(3.0 - 2.0*f);
	float n = p.x + p.y*57.0 + 113.0*p.z ;

	return lerp(lerp(lerp(hash(n + 0.0), hash(n + 1.0), f.x),
		lerp(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
		lerp(lerp(hash(n + 113.0), hash(n + 114.0), f.x),
			lerp(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

#define divstep 2.15

//perlin noise



float Layer5( float3 p, float timeslice)
{

	//float dis = (1.0+perlin_noise(vec3(fragCoord.xy/iResolution.xy, iTime*0.05)*8.0)) 
 //       * (1.0+(worley(fragCoord.xy, 32.0)+
 //       0.5*worley(2.0*fragCoord.xy,32.0) +
 //       0.25*worley(4.0*fragCoord.xy,32.0) ));
	float3 q = p - float3(0.0, 0.1, 1.0)*timeslice;
	float f;
	f = 0.50000*noisep(q); q = q * divstep;
	f += 0.25000*noisep(q); q = q * divstep;
	f += 0.12500*noisep(q); q = q * divstep;
	f += 0.06250*noisep(q); q = q * divstep;
	f += 0.03125*noisep(q);
	return clamp(1.5 - p.y / 1 - 2.0 + 1.75*f, 0.0, 511.0);
}

float Layer4( float3 p, float timeslice)
{
	float3 q = p - float3(0.0, 0.1, 1.0)*timeslice;
	float f;
	f = 0.50000*noisep(q); q = q * divstep;
	f += 0.25000*noisep(q); q = q * divstep;
	f += 0.12500*noisep(q); q = q * divstep;
	f += 0.06250*noisep(q);
	return clamp(1.5 - p.y / 1 - 2.0 + 1.75*f, 0.0, 511.0);
}
float Layer3( float3 p, float timeslice)
{
	float3 q = p - float3(0.0, 0.1, 1.0)*timeslice;
	float f;
	f = 0.50000*noisep(q); q = q * divstep;
	f += 0.25000*noisep(q); q = q * divstep;
	f += 0.12500*noisep(q);
	return clamp(1.5 - p.y/1 - 2.0 + 1.75*f, 0.0, 511.0);
}
float Layer2( float3 p, float timeslice)
{
	float3 q = p - float3(0.0, 0.1, 1.0)*timeslice;
	float f;
	f = 0.50000*noisep(q); q = q * divstep;
	f += 0.25000*noisep(q);;
	return clamp(1.5 - p.y / 1 - 2.0 + 1.75*f, 0.0, 511.0);
}


float4 integrate( float4 sum, float dif,  float den,  float3 bgcol,  float t)
{
	// lighting
	float3 lin = float3(0.65, 0.7, 0.75)*1.4 + float3(1.0, 0.6, 0.3)*dif;
	float4 col = float4(lerp(float3(1, 0.95, 0.96), float3(0.25, 0.3, 0.35), den), den*5);
	col.xyz *= lin;
	col.xyz = lerp(col.xyz, bgcol, 1.0 - exp(-0.001*t*t));
	// front to back blending    
	col.a *= 0.4;
	col.rgb *= col.a;
	return sum + col * (1.0 - sum.a);
}


float4 raymarch(float3 ro, float3 rd, float3 bgcol,float2 px)
{
	float4 sum = float4(0.0,0,0,0);
	float3 sundir = normalize(sunDir);
	float timeslice = gTotalTime / 20;
	float t = 0.0;//0.05*texelFetch( iChannel0, px&255, 0 ).x;
	int STEPS = marchStep;
	float stepmultiplier = stepMultiplier;
	
	float shadowMarcherDis = shadowMacherDis;
	int i = 0;
	float minh = - 6.;
	float maxh = 6.;

	for (i = 0; i < STEPS; i++) {
		float3  pos = ro + t * rd;
		if (pos.y<minh || pos.y>maxh || sum.a > 0.99)
			break;
		float den = Layer5(pos, timeslice);
		if (den > densityFilter)
		{
			float dif = clamp((den - Layer5(pos + shadowMarcherDis *sundir, timeslice)) / shadowDivider, 0.0, 2.0);//sample color from current pos to forward pos along sun direction to get self shadow approximation
			sum = integrate(sum, dif, den, bgcol, t);										//limited because we did just one sample, we can actually do another raymarching here but it will be really expensive
		}
		t += max(maximumStepSize, stepmultiplier*t);
	}
	for ( i = 0; i < STEPS; i++) {
		float3  pos = ro + t * rd;
		if (pos.y<minh || pos.y>maxh || sum.a > 0.99)
			break;
		float den = Layer4(pos, timeslice);
		if (den > densityFilter)
		{
			float dif = clamp((den - Layer4(pos + shadowMarcherDis *sundir, timeslice)) / shadowDivider, 0.0, 2.0);
			sum = integrate(sum, dif, den, bgcol, t);
		}
		t += max(maximumStepSize, stepmultiplier*t);
	}
	for ( i = 0; i < STEPS; i++) {
		float3  pos = ro + t * rd;
		if (pos.y<minh || pos.y>maxh || sum.a > 0.99)
			break;
		float den = Layer3(pos, timeslice);
		if (den > densityFilter)
		{
			float dif = clamp((den - Layer3(pos + shadowMarcherDis *sundir, timeslice)) / shadowDivider, 0.0, 2.0);
			sum = integrate(sum, dif, den, bgcol, t);
		}
		t += max(maximumStepSize, stepmultiplier*t);
	}
	for ( i = 0; i < STEPS; i++) {
		float3  pos = ro + t * rd;
		if (pos.y<minh || pos.y>maxh || sum.a > 0.99)
			break;
		float den = Layer2(pos, timeslice);
		if (den > densityFilter)
		{
			float dif = clamp((den - Layer2(pos + shadowMarcherDis *sundir, timeslice)) / shadowDivider, 0.0, 2.0);
			sum = integrate(sum, dif, den, bgcol, t);
		}
		t += max(maximumStepSize, stepmultiplier*t);
	}

	return clamp(sum, 0.0, 1.0);
}

float4 render( float3 ro, float3 rd, float2 px)
{

	float3 sundir = normalize(sunDir);
	// background sky     
	float sun1 = saturate(dot(sundir, rd));
	float3 col = float3(0.6, 0.71, 0.95) - rd.y*0.2*float3(1.0, 0.1, 1.0) + 0.15*0.5;
	col += 0.2*float3(1.0, .6, 0.1)*pow(sun1, 8.0);

	// clouds    
	float4 res =raymarch(ro, rd, col, px);
	col = col * (1.0 - res.w) + res.xyz;


	// sun glare    
	col += 0.2*float3(1.0, 0.4, 0.2)*pow(sun1, 3.0);

	return float4(col, 1.0);
}



//*************************
//duke ray marching
//*************************

float rand(float2 co)
{// implementation found at: lumina.sourceforge.net/Tutorials/Noise.html
	return frac(sin(dot(co*0.123, float2(12.9898, 78.233))) * 43758.5453);
}

float3 cloudd(float3 rd, float3 ro, float2 pos1)
{

	float ld = 0., td = 0., w;
	// t: length of the ray
	// d: distance function
	float d = 1., t = 0.;

	// Distance threshold.
	const float h = .1;

	float3 sundir = normalize(float3(-1.0, 0.15, 1.0));
	// background sky     
	float sun = clamp(dot(sundir, rd), 0.0, 1.0);
	float3 col = float3(0.6, 0.71, 0.75) - rd.y*0.2*float3(1.0, 0.5, 1.0) + 0.15*0.5;
	col += 0.2*float3(1.0, .6, 0.1)*pow(sun, 8.0);
	// clouds  
	float3 bgcol = col;
	float4 sum = { 0,0,0,0 };
	float2 seed = pos1 + frac(gTotalTime);

	for (int i = 0; i < 64; ++i)
	{
		float3 pos = ro + t * rd;
		pos.y = -pos.y*0.8;

		// Loop break conditions.
		if (td > (1. - 1. / 80.) || d<0.0006*t || t>120. || pos.y<-5.0 || pos.y> -0.5 || sum.a > 0.99) break;

		d = Layer5(pos, gTotalTime*0.0001)*0.526;

		if (d < 0.6)
		{
			// compute local density and weighting factor 
			ld = 0.1 - d;

			ld *= clamp((ld - Layer4(pos + 0.3*sundir, gTotalTime*0.0001)) / 0.6, 0.0, 1.0);
			const float kmaxdist = 1;
			w = (1. - td) * ld;

			// accumulate density
			td += w;// + 1./90.;

			float3 lin = float3(0.65, 0.68, 0.7)*1.3 + 0.5*float3(0.7, 0.5, 0.3)*ld;
			float4 col = float4(lerp(1.15*float3(1.0, 0.95, 0.9), float3(0.765, 0.765, 0.765), d), max(kmaxdist, d));
			col.xyz *= lin;
			col.xyz = lerp(col.xyz, bgcol, 1.0 - exp(-0.0004*t*t));
			// front to back blending    
			col.a *= 0.8;
			col.rgb *= col.a;
			sum = sum + col * (1.0 - sum.a);
		}
		td += 1. / 70.;
		// enforce minimum stepsize
		d = max(d, 0.04);
		d = abs(d)*(1. + 0.28*rand(seed*float2(i, i)));
		t += d * .5;
	}


	sum = clamp(sum, 0.0, 1.0);
	float sun1 = saturate(dot(sundir, rd));
	sum.xyz += lerp(0.1, 1, 1 - sum.a)*float3(1.0, .6, 0.1)*pow(sun1, 8.0);

	col = float3(0.6, 0.71, 0.75) - rd.y*0.2*float3(1.0, 0.5, 1.0) + 0.15*0.5;
	col = col * (1.0 - sum.w) + sum.xyz;
	return col;
}


//*************************
//duke ray marching
//*************************

//******************************
//2d fbm noise
//******************************
float random1(float2 _st)
{
	return frac(sin(dot(_st.xy, float2(12.9898, 78.233)))* 43758.5453123);
}

float noise1(float2 _st) {
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
	float2 shift = float2(100.0, 100.0);
	float2x2 rot = float2x2(cos(0.5), sin(0.5),
		-sin(0.5), cos(0.50));
	for (int i = 0; i < NUM_OCTAVES; ++i)
	{
		v += a * noise1(_st);
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


float2 boxIntersect(float3 origin, float3 dir, float3 boxmin, float3 boxmax)
{
	float near = -1;

	float tnear = DIS_MIN;
	float tfar = DIS_MAX;

	for (int i = 0; i < 3; i++)
	{
		float t0, t1;


		t0 = (boxmin[i] - origin[i]) / dir[i];
		t1 = (boxmax[i] - origin[i]) / dir[i];


		tnear = max(tnear, min(t0, t1));
		tfar = min(tfar, max(t0, t1));
	}

	if (tfar < tnear) return false; // no intersection

	if (tfar < 0) return false; // behind origin of ray

	near = tnear;

	return float2(tnear,tfar);

}

//******************************************
//reinder raymarching
//******************************************

#define CLOUD_MARCH_STEPS 12
#define CLOUD_SELF_SHADOW_STEPS 6
#define EARTH_RADIUS    (1500000.) // (6371000.)
#define CLOUDS_BOTTOM   (1350.)
#define CLOUDS_TOP      (2150.)

#define CLOUDS_LAYER_BOTTOM   (-90.)
#define CLOUDS_LAYER_TOP      (0.)

#define CLOUDS_COVERAGE (.52)
#define CLOUDS_LAYER_COVERAGE (.41)

#define CLOUDS_DETAIL_STRENGTH (.2)
#define CLOUDS_BASE_EDGE_SOFTNESS (.1)
#define CLOUDS_BOTTOM_SOFTNESS (.25)
#define CLOUDS_DENSITY (.03)
#define CLOUDS_SHADOW_MARGE_STEP_SIZE (10.)
#define CLOUDS_LAYER_SHADOW_MARGE_STEP_SIZE (4.)
#define CLOUDS_SHADOW_MARGE_STEP_MULTIPLY (1.3)
#define CLOUDS_FORWARD_SCATTERING_G (.8)
#define CLOUDS_BACKWARD_SCATTERING_G (-.2)
#define CLOUDS_SCATTERING_LERP (.5)

#define CLOUDS_AMBIENT_COLOR_TOP (float3(149., 167., 200.)*(1.5/255.))
#define CLOUDS_AMBIENT_COLOR_BOTTOM (float3(39., 67., 87.)*(1.5/255.))
#define CLOUDS_MIN_TRANSMITTANCE .1

#define CLOUDS_BASE_SCALE 1.51
#define CLOUDS_DETAIL_SCALE 20.

#define SUN_DIR normalize(float3(-.7,.5,.75))

#define SCENE_SCALE (10.)
#define SUN_COLOR (float3(1.,.9,.85)*1.4)


float hash12r(float2 p) {
	p = 50.0*frac(p*0.3183099);
	return frac(p.x*p.y*(p.x + p.y));
}

float hash13(float3 p3) {
	p3 = frac(p3 * 1031.1031);
	p3 += dot(p3, p3.yzx + 19.19);
	return frac((p3.x + p3.y) * p3.z);
}

float3 hash33r(float3 p3) {
	p3 = frac(p3 * float3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yxz + 19.19);
	return frac((p3.xxy + p3.yxx)*p3.zyx);
}

float valueHash(float3 p3) {
	p3 = frac(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 19.19);
	return frac((p3.x + p3.y) * p3.z);
}

//
// Noise functions used for cloud shapes
//
float valueNoise(float3 x, float tile) {
	float3 p = floor(x);
	float3 f = frac(x);
	f = f * f*(3.0 - 2.0*f);

	return lerp(lerp(lerp(valueHash(fmod(p + float3(0, 0, 0), tile)),
		valueHash(fmod(p + float3(1, 0, 0), tile)), f.x),
		lerp(valueHash(fmod(p + float3(0, 1, 0), tile)),
			valueHash(fmod(p + float3(1, 1, 0), tile)), f.x), f.y),
		lerp(lerp(valueHash(fmod(p + float3(0, 0, 1), tile)),
			valueHash(fmod(p + float3(1, 0, 1), tile)), f.x),
			lerp(valueHash(fmod(p + float3(0, 1, 1), tile)),
				valueHash(fmod(p + float3(1, 1, 1), tile)), f.x), f.y), f.z);
}

float tilableFbm(float3 p, const int octaves, float tile) {
	float f = 1.;
	float a = 1.;
	float c = 0.;
	float w = 0.;

	if (tile > 0.) f = tile;

	for (int i = 0; i < octaves; i++) {
		c += a * valueNoise(p * f, f);
		f *= 2.0;
		w += a;
		a *= 0.5;
	}

	return c / w;
}


float voronoi(float3 x, float tile) {
	float3 p = floor(x);
	float3 f = frac(x);

	float res = 100.;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				float3 b = float3(i, j, k);
				float3 c = p + b;

				if (tile > 0.) {
					c = fmod(c, float3(tile,tile,tile));
				}

				float3 r = float3(b) - f + hash13(c);
				float d = dot(r, r);

				if (d < res) {
					res = d;
				}
			}
		}
	}

	return 1. - res;
}

float tilableVoronoi(float3 p, const int octaves, float tile) {
	float f = 1.;
	float a = 1.;
	float c = 0.;
	float w = 0.;

	if (tile > 0.) f = tile;

	for (int i = 0; i < octaves; i++) {
		c += a * voronoi(p * f, f);
		f *= 2.0;
		w += a;
		a *= 0.5;
	}

	return c / w;
}

float3 generatedetailmap(float2 pos)
{
	float z = floor(pos.x / 34.) + 8 * floor(pos.y / 34.);
	float2 uv = fmod(pos.xy , 34.) - 1.;
	float3 pos1 = float3(uv, z) / 32.;
	float r = tilableVoronoi(pos1, 16, 3.);
	float g = tilableVoronoi(pos1, 4., 8.);
	float b = tilableVoronoi(pos1, 4., 16.);
	return float3(r, g, b);
}

float3 generatebasemap(float3 pos)
{

	float3 col = { 1,1,1 };

	//float mfbm = 0.9;
	//float mvor = 0.7;
	//col.r = lerp(1., tilableFbm(pos, 4, 4.), mfbm) *
	//	lerp(1., tilableVoronoi(pos, 8, 9.), mvor);
	//col.g = 0.625 * tilableVoronoi(pos + 0., 3, 15.) +
	//	0.250 * tilableVoronoi(pos + 0., 3, 19.) +
	//	0.125 * tilableVoronoi(pos + 0., 3, 23.)
	//	- 1.;
	//col.b = 1. - tilableVoronoi(pos + 0.5, 6, 9.);
	return col;
}

float HenyeyGreenstein(float sundotrd, float g) {
	float gg = g * g;
	return (1. - gg) / pow(1. + gg - 2. * g * sundotrd, 1.5);
}
float interectCloudSphere(float3 rd, float r) {
	float b = EARTH_RADIUS * rd.y;
	float d = b * b + r * r + 2. * EARTH_RADIUS * r;
	return -b + sqrt(d);
}
float linearstep(const float s, const float e, float v) {
	return clamp((v - s)*(1. / (e - s)), 0., 1.);
}
float linearstep0(const float e, float v) {
	return min(v*(1. / e), 1.);
}
float remap(float v, float s, float e) {
	return (v - s) / (e - s);
}

float cloudMapBase(float3 p, float norY) {
	float3 uv = p * (0.00005 * CLOUDS_BASE_SCALE);
	float3 cloud = generatebasemap(uv);

	float n = norY * norY;
	n *= cloud.b;
	n += pow(1. - norY, 16.);
	return remap(cloud.r - n, cloud.g, 1.);
}

float cloudMapDetail(float3 p) {
	// 3d lookup in 2d texture :(
	p = abs(p) * (0.0016 * CLOUDS_BASE_SCALE * CLOUDS_DETAIL_SCALE);

	float yi = fmod(p.y, 32.);
	float2 offset = float2(fmod(yi, 8.), fmod(floor(yi / 8.), 4.)) * 34 + 1;
	float a = generatedetailmap(fmod(p.xz, 32.) + float2(offset.xy) + 1.).r;

	yi = fmod(p.y + 1., 32.);
	offset = float2(fmod(yi, 8.), fmod(floor(yi / 8.), 4.)) * 34 + 1;
	float b = generatedetailmap(fmod(p.xz, 32.) + float2(offset.xy) + 1.).r;

	

	return lerp(a, b, frac(p.y));
}

float cloudMapLayer(float3 pos, float3 rd, float norY) {
	float3 ps = pos;



	float m = voronoi(pos/100,16);

	// m *= cloudGradient( norY );
	float dstrength = smoothstep(1., 0.5, m);

	// erode with detail
	if (dstrength > 0.) {
		m -= tilableFbm(ps,3,8) * dstrength * CLOUDS_DETAIL_STRENGTH;
	}

	m = smoothstep(0., CLOUDS_BASE_EDGE_SOFTNESS, m + (CLOUDS_LAYER_COVERAGE - 1.));

	return clamp(m * CLOUDS_DENSITY, 0., 1.);
}
float volumetricShadow(float3 from, float sundotrd) {
	float dd = CLOUDS_SHADOW_MARGE_STEP_SIZE;
	float3 rd = SUN_DIR;
	float d = dd * .5;
	float shadow = 1.0;

	for (int s = 0; s < CLOUD_SELF_SHADOW_STEPS; s++) {
		float3 pos = from + rd * d;
		float norY = clamp((pos.y - CLOUDS_LAYER_BOTTOM) * (1. / (CLOUDS_LAYER_TOP - CLOUDS_LAYER_BOTTOM)), 0., 1.);

		if (norY > 1.) return shadow;

		float muE = cloudMapLayer(pos, rd,norY);
		shadow *= exp(-muE * dd);

		dd *= CLOUDS_SHADOW_MARGE_STEP_MULTIPLY;
		d += dd;
	}
	return shadow;
}


float4 renderCloudLayer(float3 ro, float3 rd,float dist) {
	//if (rd.y < 0.) {
	//	return float4(0, 0, 0, 10);
	//}

	//ro.xz *= SCENE_SCALE;
	//ro.y = 0.;

	ro.xyz *= 20.f;

	float start = CLOUDS_LAYER_TOP / rd.y;
	float end = CLOUDS_LAYER_BOTTOM / rd.y;

	//if (start > dist) {
	//	return float4(0, 0, 0, 10);
	//}

	end = min(end, dist);

	float sundotrd = dot(rd, -SUN_DIR);

	// raymarch
	float d = start;
	float dD = (end - start) / float(CLOUD_MARCH_STEPS);

	float h = 0.1;
	d -= dD * h;

	float scattering = lerp(HenyeyGreenstein(sundotrd, CLOUDS_FORWARD_SCATTERING_G),
		HenyeyGreenstein(sundotrd, CLOUDS_BACKWARD_SCATTERING_G), CLOUDS_SCATTERING_LERP);

	float transmittance = 1.0;
	float3 scatteredLight = float3(0.0, 0.0, 0.0);

	dist = EARTH_RADIUS;

	for (int s = 0; s < CLOUD_MARCH_STEPS; s++) {
		float3 p = ro + d * rd;

		float norY = clamp((p.y - CLOUDS_LAYER_BOTTOM) * (1. / (CLOUDS_LAYER_TOP - CLOUDS_LAYER_BOTTOM)), 0., 1.);

		float alpha = cloudMapLayer(p, rd,norY);

		if (alpha > 0.) {
			dist = min(dist, d);
			float3 ambientLight = lerp(CLOUDS_AMBIENT_COLOR_BOTTOM, CLOUDS_AMBIENT_COLOR_TOP, norY);

			float3 S = .7 * (ambientLight + SUN_COLOR * (scattering * volumetricShadow(p, sundotrd))) * alpha;
			float dTrans = exp(-alpha * dD);
			float3 Sint = (S - S * dTrans) * (1. / alpha);
			scatteredLight += transmittance * Sint;
			transmittance *= dTrans;
		}

		if (transmittance <= CLOUDS_MIN_TRANSMITTANCE) break;

		d += dD;
	}

	return float4(scatteredLight, transmittance);
}


//******************************************
//reinder raymarching
//******************************************

VertexOut VS(VertexIn vin)
{
	VertexOut vout = (VertexOut)0.0f;

	// Transform to world space.

	float4 posW = mul(float4(vin.PosL, 1.0f), gWorld);
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
	diffuseAlbedo = float4(0.5, 0.5, 0.5, 1);
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
	litColor.a = 1;

	//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	//volume rendering
	//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

	//float stepnum = 10;

	//float3 origin = gEyePosW;
	//float3 dir = -toEyeW;

	//float2 inter = boxIntersect(origin, dir, boxcenter - float3(boxL, boxL, boxL) / 2, boxcenter + float3(boxL, boxL, boxL) / 2);

	//float near = inter.x;
	//float far = inter.y;
	//int stepsize = (far - near) / stepnum;

	//float curr = near;
	//float3 startpos = origin + near * dir;
	//float4 acc = { 0,0,0,0 };

	//for (int i = 0; i < stepnum; ++i)
	//{
	//	curr = i*stepsize;
	//	float3 curloc = startpos + curr * dir;
	//	float rr = Layer3(curloc);
	//	float fbmr = rr;
	//	acc += fbmr;
	//}

	//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	//volume rendering
	//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

	//iq cloud

	float4 acc =  render(gEyePosW/50, -toEyeW, pin.PosH.xy);
	//iq cloud

	//duke cloud
	//float4 res = float4(cloudd(-toEyeW, gEyePosW / 50, pin.PosH), 1);
	//duke cloud
	//toEyeW.y = -toEyeW.y;
	//float4 res = renderCloudLayer(gEyePosW ,toEyeW,  500);

	//return litColor;
	return acc;
}


