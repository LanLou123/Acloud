#include "inc.hlsli"


RWTexture2D<float4> gnoiseMap : register(u0);

[numthreads(16, 16, 1)]
void noiseComp( uint3 DTid : SV_DispatchThreadID )
{
	int x = DTid.x;
	int y = DTid.y;

	float2 inn = float2(x, y)/20;

	float ww = 0.5* worley(inn, 32);

	float ww2 =  0.25* worley(inn *2, 32);

	float ww3 = 0.125*worley(inn * 4, 32);

	float ww4 = 0.06*worley(inn * 8, 32);

	float finalw = ww + ww2 + ww3 + ww4;
	gnoiseMap[int2(x,y)] = float4(finalw,y,ww,0.2);
}