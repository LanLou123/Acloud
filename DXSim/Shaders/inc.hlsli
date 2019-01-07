//*****************************
//worley perlin noise
//*****************************

float r(float n)
{
	return frac(cos(n*89.42)*343.42);
}
float2 r(float2 n)
{
	return float2(r(n.x*23.62 - 300.0 + n.y*34.35), r(n.x*45.13 + 256.0 + n.y*38.89));
}
float worley(float2 n, float s)
{
	n *= 25;
	float dis = 2.0;
	for (int x = -1; x <= 1; x++)
	{
		for (int y = -1; y <= 1; y++)
		{
			float2 p = floor(n / s) + float2(x, y);
			float d = length(r(p) + float2(x, y) - frac(n / s));
			if (dis > d)
			{
				dis = d;
			}
		}
	}
	float rr = 1. - dis;
	return dis;

}

#define MOD3 float3(.1031,.11369,.13787)

float3 hash33(float3 p3)
{
	p3 = frac(p3 * MOD3);
	p3 += dot(p3, p3.yxz + 19.19);
	return -1.0 + 2.0 * frac(float3((p3.x + p3.y)*p3.z, (p3.x + p3.z)*p3.y, (p3.y + p3.z)*p3.x));
}
float perlin_noise(float3 p)
{
	float3 pi = floor(p);
	float3 pf = p - pi;

	float3 w = pf * pf * (3.0 - 2.0 * pf);

	return 	lerp(
		lerp(
			lerp(dot(pf - float3(0, 0, 0), hash33(pi + float3(0, 0, 0))),
				dot(pf - float3(1, 0, 0), hash33(pi + float3(1, 0, 0))),
				w.x),
			lerp(dot(pf - float3(0, 0, 1), hash33(pi + float3(0, 0, 1))),
				dot(pf - float3(1, 0, 1), hash33(pi + float3(1, 0, 1))),
				w.x),
			w.z),
		lerp(
			lerp(dot(pf - float3(0, 1, 0), hash33(pi + float3(0, 1, 0))),
				dot(pf - float3(1, 1, 0), hash33(pi + float3(1, 1, 0))),
				w.x),
			lerp(dot(pf - float3(0, 1, 1), hash33(pi + float3(0, 1, 1))),
				dot(pf - float3(1, 1, 1), hash33(pi + float3(1, 1, 1))),
				w.x),
			w.z),
		w.y);
}
//*****************************
//worley perlin noise
//*****************************

//******************************
//3d fbm noise
//******************************

float mod289(float x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 perm(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }

float noise3d(float3 p) {
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
	float3 shift = float3(100, 100, 100);
	for (int i = 0; i < NUM_OCTAVES; ++i) {
		v += a * noise3d(x);
		x = x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

float finalFbm3d(float3 _st,float gTotalTime)
{


	float3 q = float3(0, 0, 0);

	q.x = fbm3d(_st + 0.0*gTotalTime);
	q.y = fbm3d(_st + float3(1, 1, 1));
	q.z = fbm3d(_st + float3(0, 0, 1));

	float3 r = float3(0, 0, 0);
	r.x = fbm3d(_st + 1.0*q + float3(1.7, 9.2, 10.1) + 0.15*gTotalTime);
	r.y = fbm3d(_st + 1.0*q + float3(8.3, 2.8, 2.1) + 0.126*gTotalTime);
	r.z = fbm3d(_st + 1.0*q + float3(3.3, 6.8, 1.1) + 0.176*gTotalTime);
	return fbm3d(_st + r);
}
//******************************
//3d fbm noise
//******************************


